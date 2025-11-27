//============================================================
// CORRECCIÓN PARA dsa_pixel_fetch_simd.sv
//============================================================

module dsa_pixel_fetch_simd #(
    parameter ADDR_WIDTH = 18,
    parameter IMG_WIDTH  = 512,
    parameter SIMD_WIDTH = 4
)(
    // ... (mismos puertos que el original) ...
    input  logic                    clk,
    input  logic                    rst,
    input  logic                    req_valid,
    input  logic [15:0]             base_x,
    input  logic [15:0]             base_y,
    input  logic [7:0]              scale_factor,
    input  logic [ADDR_WIDTH-1:0]   img_base_addr,
    output logic                    mem_read_en,
    output logic [ADDR_WIDTH-1:0]   mem_addr,
    input  logic [7:0]              mem_data,
    output logic                    fetch_valid,
    output logic [7:0]              p00 [0:SIMD_WIDTH-1],
    output logic [7:0]              p01 [0:SIMD_WIDTH-1],
    output logic [7:0]              p10 [0:SIMD_WIDTH-1],
    output logic [7:0]              p11 [0:SIMD_WIDTH-1],
    output logic [15:0]             a   [0:SIMD_WIDTH-1],
    output logic [15:0]             b   [0:SIMD_WIDTH-1],
    output logic                    busy
);

    // Estados
    typedef enum logic [2:0] {
        ST_IDLE         = 3'd0,
        ST_CALC         = 3'd1, // Calculamos todo en un estado o pipelineamos
        ST_FETCH_PIPE   = 3'd2, // Fetch continuo
        ST_DONE         = 3'd3
    } state_t;
    state_t state, next_state;

    // Contadores y registros
    logic [4:0] fetch_idx_req;  // Índice para SOLICITAR datos (0 a 15)
    logic [4:0] fetch_idx_save; // Índice para GUARDAR datos (retardado 1 ciclo)
    logic [4:0] calc_idx;       // Para el cálculo inicial

    // Arrays internos (reutilizamos la lógica original de registros)
    logic [15:0] src_x_int_r [0:SIMD_WIDTH-1];
    logic [15:0] src_y_int_r [0:SIMD_WIDTH-1];
    logic [15:0] frac_x_r    [0:SIMD_WIDTH-1];
    logic [15:0] frac_y_r    [0:SIMD_WIDTH-1];

    logic [25:0] inv_scale_fixed;
    assign inv_scale_fixed = (scale_factor != 8'd0) ? (26'd65536 / {18'd0, scale_factor}) : 26'd65536;

    // Lógica de cálculo de dirección actual
    logic [1:0]  req_pixel_idx;
    logic [1:0]  req_neighbor_idx;
    assign req_pixel_idx    = fetch_idx_req[3:2];
    assign req_neighbor_idx = fetch_idx_req[1:0];

    logic [1:0]  save_pixel_idx;
    logic [1:0]  save_neighbor_idx;
    assign save_pixel_idx    = fetch_idx_save[3:2];
    assign save_neighbor_idx = fetch_idx_save[1:0];
	 
	 logic [25:0] temp_x, temp_y;

    logic [ADDR_WIDTH-1:0] row_addr;

    // FSM Secuencial
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= ST_IDLE;
            calc_idx <= '0;
            fetch_idx_req <= '0;
            fetch_idx_save <= '0;
            // Reset outputs...
        end else begin
            state <= next_state;

            // LOGICA DE CÁLCULO DE COORDENADAS
            if (state == ST_CALC) begin
                // Hacemos el cálculo iterativo para ahorrar hardware o usamos tu lógica combinacional
                // Aquí uso una versión simplificada de tu lógica original pero serializada para no explotar el área
                
                temp_x = (base_x + calc_idx) * inv_scale_fixed;
                temp_y = base_y * inv_scale_fixed;
                
                src_x_int_r[calc_idx] <= temp_x[25:16];
                src_y_int_r[calc_idx] <= temp_y[25:16];
                frac_x_r[calc_idx]    <= temp_x[15:0];
                frac_y_r[calc_idx]    <= temp_y[15:0];
                
                calc_idx <= calc_idx + 1;
            end else if (state == ST_IDLE) begin
                calc_idx <= '0;
            end

            // LOGICA DE FETCH (PIPELINED)
            if (state == ST_FETCH_PIPE) begin
                // Incrementamos request counter hasta llegar al final
                if (fetch_idx_req < 16) 
                    fetch_idx_req <= fetch_idx_req + 1;
                
                // Incrementamos save counter (va 1 ciclo detrás del request)
                // Cuando req es 0, save es inválido. Cuando req es 1, save captura el 0.
                if (fetch_idx_req > 0 || (fetch_idx_req == 16 && fetch_idx_save < 16))
                     fetch_idx_save <= fetch_idx_save + 1;
            end else begin
                fetch_idx_req <= '0;
                fetch_idx_save <= '0;
            end
        end
    end

    // FSM Combinacional
    always_comb begin
        next_state = state;
        case (state)
            ST_IDLE: if (req_valid) next_state = ST_CALC;
            ST_CALC: if (calc_idx == SIMD_WIDTH-1) next_state = ST_FETCH_PIPE;
            ST_FETCH_PIPE: begin
                // Terminamos cuando hemos guardado el último dato (índice 15)
                if (fetch_idx_save == 15) next_state = ST_DONE;
            end
            ST_DONE: next_state = ST_IDLE;
        endcase
    end

    // Lógica de Memoria y Guardado
    always_ff @(posedge clk) begin
        mem_read_en <= 1'b0;
        
        // 1. REQUEST PHASE
        if (state == ST_FETCH_PIPE && fetch_idx_req < 16) begin
            mem_read_en <= 1'b1;
            // Seleccionar base row
            if (req_neighbor_idx[1] == 0) // Vecinos 0 y 1 (fila superior)
                row_addr = img_base_addr + (src_y_int_r[req_pixel_idx] * IMG_WIDTH);
            else // Vecinos 2 y 3 (fila inferior)
                row_addr = img_base_addr + ((src_y_int_r[req_pixel_idx] + 16'd1) * IMG_WIDTH);
            
            // Seleccionar offset X
            if (req_neighbor_idx[0] == 0) // Vecinos 0 y 2 (izq)
                mem_addr <= row_addr + src_x_int_r[req_pixel_idx];
            else // Vecinos 1 y 3 (der)
                mem_addr <= row_addr + src_x_int_r[req_pixel_idx] + 16'd1;
        end

        // 2. SAVE PHASE (Data available from previous cycle)
        // Usamos un retardo implícito: si pedimos en ciclo T, data llega en T+1
        if (state == ST_FETCH_PIPE && (fetch_idx_req > 0 || fetch_idx_save < 16)) begin
             // Usamos fetch_idx_save para saber qué dato está llegando
             case (save_neighbor_idx)
                2'd0: p00[save_pixel_idx] <= mem_data;
                2'd1: p01[save_pixel_idx] <= mem_data;
                2'd2: p10[save_pixel_idx] <= mem_data;
                2'd3: begin
                    p11[save_pixel_idx] <= mem_data;
                    a[save_pixel_idx]   <= {8'd0, frac_x_r[save_pixel_idx][15:8]};
                    b[save_pixel_idx]   <= {8'd0, frac_y_r[save_pixel_idx][15:8]};
                end
             endcase
        end
    end

    assign fetch_valid = (state == ST_DONE);
    assign busy = (state != ST_IDLE);

endmodule