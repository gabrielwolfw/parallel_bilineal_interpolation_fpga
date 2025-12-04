//============================================================
// dsa_pixel_fetch_sequential.sv
// Fetch secuencial con dimensiones dinámicas
//============================================================

module dsa_pixel_fetch_sequential #(
    parameter ADDR_WIDTH = 18
)(
    input  logic                    clk,
    input  logic                    rst,

    // Control
    input  logic                    req_valid,
    input  logic [15:0]             src_x_int,
    input  logic [15:0]             src_y_int,
    input  logic [15:0]             frac_x,
    input  logic [15:0]             frac_y,
    input  logic [ADDR_WIDTH-1:0]   img_base_addr,
    input  logic [15:0]             img_width,      // ← Dinámico
    input  logic [15:0]             img_height,     // ← Dinámico

    // Interfaz memoria
    output logic                    mem_read_en,
    output logic [ADDR_WIDTH-1:0]   mem_addr,
    input  logic [7:0]              mem_data,

    // Salida
    output logic                    fetch_valid,
    output logic [7:0]              p00, p01, p10, p11,
    output logic [15:0]             a, b,
    output logic                    busy
);

    typedef enum logic [2:0] {
        ST_IDLE     = 3'd0,
        ST_SETUP    = 3'd1,
        ST_FETCH_0  = 3'd2,
        ST_FETCH_1  = 3'd3,
        ST_FETCH_2  = 3'd4,
        ST_FETCH_3  = 3'd5,
        ST_DONE     = 3'd6
    } state_t;

    state_t state, next_state;

    // Registros internos
    logic [15:0] x_int_r, y_int_r;
    logic [15:0] frac_x_r, frac_y_r;
    logic [15:0] img_width_r, img_height_r;
    logic [ADDR_WIDTH-1:0] base_addr_r;
    logic [ADDR_WIDTH-1:0] addr_p00, addr_p01, addr_p10, addr_p11;
    logic [7:0] p00_r, p01_r, p10_r, p11_r;

    // FSM
    always_ff @(posedge clk or posedge rst) begin
        if (rst) state <= ST_IDLE;
        else     state <= next_state;
    end

    always_comb begin
        next_state = state;
        case (state)
            ST_IDLE:    if (req_valid) next_state = ST_SETUP;
            ST_SETUP:   next_state = ST_FETCH_0;
            ST_FETCH_0: next_state = ST_FETCH_1;
            ST_FETCH_1: next_state = ST_FETCH_2;
            ST_FETCH_2: next_state = ST_FETCH_3;
            ST_FETCH_3: next_state = ST_DONE;
            ST_DONE:    next_state = ST_IDLE;
            default:    next_state = ST_IDLE;
        endcase
    end

    // Captura de parámetros y cálculo de direcciones
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            x_int_r      <= '0;
            y_int_r      <= '0;
            frac_x_r     <= '0;
            frac_y_r     <= '0;
            img_width_r  <= 16'd512;
            img_height_r <= 16'd512;
            base_addr_r  <= '0;
            addr_p00     <= '0;
            addr_p01     <= '0;
            addr_p10     <= '0;
            addr_p11     <= '0;
        end else if (state == ST_IDLE && req_valid) begin
            x_int_r      <= src_x_int;
            y_int_r      <= src_y_int;
            frac_x_r     <= frac_x;
            frac_y_r     <= frac_y;
            img_width_r  <= img_width;
            img_height_r <= img_height;
            base_addr_r  <= img_base_addr;
        end else if (state == ST_SETUP) begin
            // Calcular direcciones usando dimensiones dinámicas
            addr_p00 <= base_addr_r + (y_int_r * img_width_r) + x_int_r;
            addr_p01 <= base_addr_r + (y_int_r * img_width_r) + x_int_r + 1;
            addr_p10 <= base_addr_r + ((y_int_r + 1) * img_width_r) + x_int_r;
            addr_p11 <= base_addr_r + ((y_int_r + 1) * img_width_r) + x_int_r + 1;
        end
    end

    // Control de memoria
    always_comb begin
        mem_read_en = 1'b0;
        mem_addr = '0;
        case (state)
            ST_FETCH_0: begin mem_read_en = 1'b1; mem_addr = addr_p00; end
            ST_FETCH_1: begin mem_read_en = 1'b1; mem_addr = addr_p01; end
            ST_FETCH_2: begin mem_read_en = 1'b1; mem_addr = addr_p10; end
            ST_FETCH_3: begin mem_read_en = 1'b1; mem_addr = addr_p11; end
            default:    begin mem_read_en = 1'b0; mem_addr = '0; end
        endcase
    end

    // Captura de datos
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            p00_r <= 8'd0;
            p01_r <= 8'd0;
            p10_r <= 8'd0;
            p11_r <= 8'd0;
        end else begin
            case (state)
                ST_FETCH_1: p00_r <= mem_data;
                ST_FETCH_2: p01_r <= mem_data;
                ST_FETCH_3: p10_r <= mem_data;
                ST_DONE:    p11_r <= mem_data;
                default: ;
            endcase
        end
    end

    // Salidas
    assign p00 = p00_r;
    assign p01 = p01_r;
    assign p10 = p10_r;
    assign p11 = p11_r;
    assign a = {8'd0, frac_x_r[15:8]};
    assign b = {8'd0, frac_y_r[15:8]};
    assign fetch_valid = (state == ST_DONE);
    assign busy = (state != ST_IDLE);

endmodule