//============================================================
// dsa_pixel_fetch_simd.sv - VERSIÓN CORREGIDA v2
// Con lógica de captura simplificada y correcta
//============================================================

module dsa_pixel_fetch_simd #(
    parameter ADDR_WIDTH = 18,
    parameter SIMD_WIDTH = 4
)(
    input  logic                    clk,
    input  logic                    rst,
    input  logic                    req_valid,
    input  logic [15:0]             base_x,
    input  logic [15:0]             base_y,
    input  logic [7:0]              scale_factor,
    input  logic [ADDR_WIDTH-1:0]   img_base_addr,
    input  logic [15:0]             img_width,
    input  logic [15:0]             img_height,
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

    //========================================================
    // Estados
    //========================================================
    typedef enum logic [2:0] {
        ST_IDLE         = 3'd0,
        ST_CALC         = 3'd1,
        ST_FETCH        = 3'd2,
        ST_CAPTURE_LAST = 3'd3,
        ST_DONE         = 3'd4
    } state_t;
    state_t state, next_state;

    //========================================================
    // Contadores y registros
    //========================================================
    logic [4:0] fetch_count;      // 0-16: qué fetch estamos haciendo
    logic [4:0] capture_count;    // 0-16: qué dato estamos capturando
    logic [2:0] calc_idx;
    
    // Registro para saber si hay dato pendiente de captura
    logic capture_pending;
    
    // Registros para coordenadas calculadas
    logic [15:0] src_x_int_r [0:SIMD_WIDTH-1];
    logic [15:0] src_y_int_r [0:SIMD_WIDTH-1];
    logic [15:0] frac_x_r    [0:SIMD_WIDTH-1];
    logic [15:0] frac_y_r    [0:SIMD_WIDTH-1];
    
    // Registros de configuración
    logic [15:0] base_x_r, base_y_r;
    logic [15:0] img_width_r, img_height_r;
    logic [ADDR_WIDTH-1:0] img_base_addr_r;
    logic [7:0]  scale_factor_r;

    // Cálculo de escala inversa
    logic [31:0] inv_scale_q8_8;
    assign inv_scale_q8_8 = (scale_factor_r != 8'd0) ? 
                            (32'd65536 / {24'd0, scale_factor_r}) : 
                            32'd256;

    // Índices derivados de capture_count
    logic [1:0] cap_pixel_idx;
    logic [1:0] cap_neighbor_idx;
    assign cap_pixel_idx    = capture_count[3:2];
    assign cap_neighbor_idx = capture_count[1:0];

    // Índices para solicitud de memoria (basados en fetch_count)
    logic [1:0] req_pixel_idx;
    logic [1:0] req_neighbor_idx;
    assign req_pixel_idx    = fetch_count[3:2];
    assign req_neighbor_idx = fetch_count[1:0];

    // Variables para cálculo de direcciones
    logic [31:0] temp_x, temp_y;
    logic [ADDR_WIDTH-1:0] row_addr;
    
    // Registros de salida de memoria
    logic [ADDR_WIDTH-1:0] mem_addr_r;
    logic mem_read_en_r;

    //========================================================
    // FSM Principal
    //========================================================
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= ST_IDLE;
            calc_idx <= '0;
            fetch_count <= '0;
            capture_count <= '0;
            capture_pending <= 1'b0;
            base_x_r <= '0;
            base_y_r <= '0;
            img_width_r <= 16'd512;
            img_height_r <= 16'd512;
            img_base_addr_r <= '0;
            scale_factor_r <= 8'h80;
            mem_read_en_r <= 1'b0;
            mem_addr_r <= '0;
            
            for (int i = 0; i < SIMD_WIDTH; i++) begin
                src_x_int_r[i] <= '0;
                src_y_int_r[i] <= '0;
                frac_x_r[i] <= '0;
                frac_y_r[i] <= '0;
                p00[i] <= 8'd0;
                p01[i] <= 8'd0;
                p10[i] <= 8'd0;
                p11[i] <= 8'd0;
                a[i] <= 16'd0;
                b[i] <= 16'd0;
            end
        end else begin
            state <= next_state;
            
            case (state)
                ST_IDLE: begin
                    if (req_valid) begin
                        // Capturar configuración
                        base_x_r <= base_x;
                        base_y_r <= base_y;
                        img_width_r <= img_width;
                        img_height_r <= img_height;
                        img_base_addr_r <= img_base_addr;
                        scale_factor_r <= scale_factor;
                        calc_idx <= '0;
                        fetch_count <= '0;
                        capture_count <= '0;
                        capture_pending <= 1'b0;
                        mem_read_en_r <= 1'b0;
                        
                        // Limpiar buffers de salida
                        for (int i = 0; i < SIMD_WIDTH; i++) begin
                            p00[i] <= 8'd0;
                            p01[i] <= 8'd0;
                            p10[i] <= 8'd0;
                            p11[i] <= 8'd0;
                        end
                    end
                end
                
                ST_CALC: begin
                    // Calcular coordenadas fuente para cada píxel SIMD
                    temp_x = (base_x_r + {13'd0, calc_idx}) * inv_scale_q8_8;
                    temp_y = base_y_r * inv_scale_q8_8;
                    
                    src_x_int_r[calc_idx] <= temp_x[23:8];
                    src_y_int_r[calc_idx] <= temp_y[23:8];
                    frac_x_r[calc_idx]    <= {temp_x[7:0], 8'd0};
                    frac_y_r[calc_idx]    <= {temp_y[7:0], 8'd0};
                    
                    if (calc_idx < SIMD_WIDTH - 1)
                        calc_idx <= calc_idx + 1;
                end
                
                ST_FETCH: begin
                    // === CAPTURA del dato anterior (si hay pendiente) ===
                    if (capture_pending && capture_count < 16) begin
                        case (cap_neighbor_idx)
                            2'd0: p00[cap_pixel_idx] <= mem_data;
                            2'd1: p01[cap_pixel_idx] <= mem_data;
                            2'd2: p10[cap_pixel_idx] <= mem_data;
                            2'd3: begin
                                p11[cap_pixel_idx] <= mem_data;
                                a[cap_pixel_idx] <= {8'd0, frac_x_r[cap_pixel_idx][15:8]};
                                b[cap_pixel_idx] <= {8'd0, frac_y_r[cap_pixel_idx][15:8]};
                            end
                        endcase
                        capture_count <= capture_count + 1;
                    end
                    
                    // === SOLICITUD de nuevo dato ===
                    if (fetch_count < 16) begin
                        mem_read_en_r <= 1'b1;
                        
                        // Calcular dirección
                        if (req_neighbor_idx[1] == 0)
                            row_addr = img_base_addr_r + (src_y_int_r[req_pixel_idx] * img_width_r);
                        else
                            row_addr = img_base_addr_r + ((src_y_int_r[req_pixel_idx] + 16'd1) * img_width_r);
                        
                        if (req_neighbor_idx[0] == 0)
                            mem_addr_r <= row_addr + src_x_int_r[req_pixel_idx];
                        else
                            mem_addr_r <= row_addr + src_x_int_r[req_pixel_idx] + 16'd1;
                        
                        fetch_count <= fetch_count + 1;
                        capture_pending <= 1'b1;  // Próximo ciclo habrá dato para capturar
                    end else begin
                        mem_read_en_r <= 1'b0;
                    end
                end
                
                ST_CAPTURE_LAST: begin
                    // Capturar el último dato
                    mem_read_en_r <= 1'b0;
                    
                    if (capture_count < 16) begin
                        case (cap_neighbor_idx)
                            2'd0: p00[cap_pixel_idx] <= mem_data;
                            2'd1: p01[cap_pixel_idx] <= mem_data;
                            2'd2: p10[cap_pixel_idx] <= mem_data;
                            2'd3: begin
                                p11[cap_pixel_idx] <= mem_data;
                                a[cap_pixel_idx] <= {8'd0, frac_x_r[cap_pixel_idx][15:8]};
                                b[cap_pixel_idx] <= {8'd0, frac_y_r[cap_pixel_idx][15:8]};
                            end
                        endcase
                        capture_count <= capture_count + 1;
                    end
                end
                
                ST_DONE: begin
                    capture_pending <= 1'b0;
                    fetch_count <= '0;
                    capture_count <= '0;
                end
                
                default: ;
            endcase
        end
    end

    //========================================================
    // FSM Combinacional
    //========================================================
    always_comb begin
        next_state = state;
        case (state)
            ST_IDLE:        if (req_valid) next_state = ST_CALC;
            ST_CALC:        if (calc_idx >= SIMD_WIDTH - 1) next_state = ST_FETCH;
            ST_FETCH:       if (fetch_count >= 16) next_state = ST_CAPTURE_LAST;
            ST_CAPTURE_LAST: if (capture_count >= 16) next_state = ST_DONE;
            ST_DONE:        next_state = ST_IDLE;
            default:        next_state = ST_IDLE;
        endcase
    end

    //========================================================
    // Salidas
    //========================================================
    assign mem_addr = mem_addr_r;
    assign mem_read_en = mem_read_en_r;
    assign fetch_valid = (state == ST_DONE);
    assign busy = (state != ST_IDLE);

endmodule