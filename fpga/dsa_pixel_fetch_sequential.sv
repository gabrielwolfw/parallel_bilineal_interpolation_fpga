
//============================================================
// dsa_pixel_fetch_sequential.sv
// Fetch optimizado para modo secuencial (1 píxel/ciclo)
// Latencia: 4 ciclos, Throughput: 1 fetch cada 4 ciclos
//============================================================

module dsa_pixel_fetch_sequential #(
    parameter ADDR_WIDTH = 18,
    parameter IMG_WIDTH  = 512
)(
    input  logic                    clk,
    input  logic                    rst,

    // Control
    input  logic                    req_valid,
    input  logic [15:0]             src_x_int,      // Parte entera de coordenada X
    input  logic [15:0]             src_y_int,      // Parte entera de coordenada Y
    input  logic [15:0]             frac_x,         // Parte fraccionaria X (Q8.8)
    input  logic [15:0]             frac_y,         // Parte fraccionaria Y (Q8.8)
    input  logic [ADDR_WIDTH-1:0]   img_base_addr,

    // Interfaz memoria
    output logic                    mem_read_en,
    output logic [ADDR_WIDTH-1:0]   mem_addr,
    input  logic [7:0]              mem_data,

    // Salida
    output logic                    fetch_valid,
    output logic [7:0]              p00, p01, p10, p11,
    output logic [15:0]             a, b,           // Coeficientes para interpolación
    output logic                    busy
);

    //========================================================
    // Estados - Pipeline optimizado
    //========================================================
    typedef enum logic [2:0] {
        ST_IDLE     = 3'd0,
        ST_FETCH_0  = 3'd1,   // Fetch p00 y p01 (dirección p00)
        ST_FETCH_1  = 3'd2,   // Latch p00, fetch p01
        ST_FETCH_2  = 3'd3,   // Latch p01, fetch p10
        ST_FETCH_3  = 3'd4,   // Latch p10, fetch p11
        ST_DONE     = 3'd5    // Latch p11, señal de done
    } state_t;

    state_t state, next_state;

    //========================================================
    // Registros internos
    //========================================================
    logic [15:0] x_int_r, y_int_r;
    logic [15:0] frac_x_r, frac_y_r;
    logic [ADDR_WIDTH-1:0] base_addr_r;
    logic [ADDR_WIDTH-1:0] row0_base, row1_base;

    //========================================================
    // Cálculo de direcciones base (se hace una vez)
    //========================================================
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            x_int_r    <= '0;
            y_int_r    <= '0;
            frac_x_r   <= '0;
            frac_y_r   <= '0;
            base_addr_r <= '0;
            row0_base  <= '0;
            row1_base  <= '0;
        end else if (state == ST_IDLE && req_valid) begin
            x_int_r    <= src_x_int;
            y_int_r    <= src_y_int;
            frac_x_r   <= frac_x;
            frac_y_r   <= frac_y;
            base_addr_r <= img_base_addr;
            
            // Precalcular bases de filas
            row0_base  <= img_base_addr + (src_y_int * IMG_WIDTH);
            row1_base  <= img_base_addr + ((src_y_int + 1) * IMG_WIDTH);
        end
    end

    //========================================================
    // FSM - Transiciones
    //========================================================
    always_ff @(posedge clk or posedge rst) begin
        if (rst)
            state <= ST_IDLE;
        else
            state <= next_state;
    end

    always_comb begin
        next_state = state;
        case (state)
            ST_IDLE:    if (req_valid) next_state = ST_FETCH_0;
            ST_FETCH_0: next_state = ST_FETCH_1;
            ST_FETCH_1: next_state = ST_FETCH_2;
            ST_FETCH_2: next_state = ST_FETCH_3;
            ST_FETCH_3: next_state = ST_DONE;
            ST_DONE:    next_state = ST_IDLE;
            default:    next_state = ST_IDLE;
        endcase
    end

    //========================================================
    // Control de memoria y captura de píxeles
    //========================================================
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            mem_read_en <= 1'b0;
            mem_addr    <= '0;
            p00 <= '0;
            p01 <= '0;
            p10 <= '0;
            p11 <= '0;
            a   <= '0;
            b   <= '0;
        end else begin
            mem_read_en <= 1'b0;  // Default
            
            case (state)
                ST_FETCH_0: begin
                    // Solicitar p00
                    mem_addr    <= row0_base + x_int_r;
                    mem_read_en <= 1'b1;
                end
                
                ST_FETCH_1: begin
                    // Capturar p00, solicitar p01
                    p00         <= mem_data;
                    mem_addr    <= row0_base + x_int_r + 1;
                    mem_read_en <= 1'b1;
                end
                
                ST_FETCH_2: begin
                    // Capturar p01, solicitar p10
                    p01         <= mem_data;
                    mem_addr    <= row1_base + x_int_r;
                    mem_read_en <= 1'b1;
                end
                
                ST_FETCH_3: begin
                    // Capturar p10, solicitar p11
                    p10         <= mem_data;
                    mem_addr    <= row1_base + x_int_r + 1;
                    mem_read_en <= 1'b1;
                end
                
                ST_DONE: begin
                    // Capturar p11 y coeficientes
                    p11 <= mem_data;
                    a   <= {8'd0, frac_x_r[15:8]};  // Tomar parte alta de Q8.8
                    b   <= {8'd0, frac_y_r[15:8]};
                end
            endcase
        end
    end

    //========================================================
    // Señales de salida
    //========================================================
    assign fetch_valid = (state == ST_DONE);
    assign busy        = (state != ST_IDLE);

endmodule