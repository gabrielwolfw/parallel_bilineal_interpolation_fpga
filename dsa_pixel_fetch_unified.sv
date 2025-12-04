//============================================================
// dsa_pixel_fetch_unified.sv
// Wrapper con dimensiones dinámicas
//============================================================

module dsa_pixel_fetch_unified #(
    parameter ADDR_WIDTH = 18,
    parameter SIMD_WIDTH = 4
)(
    input  logic                    clk,
    input  logic                    rst,

    // Control
    input  logic                    mode_simd,
    input  logic                    req_valid,
    input  logic [15:0]             img_width,      // ← Dinámico
    input  logic [15:0]             img_height,     // ← Dinámico
    
    // Entradas secuenciales
    input  logic [15:0]             seq_src_x_int,
    input  logic [15:0]             seq_src_y_int,
    input  logic [15:0]             seq_frac_x,
    input  logic [15:0]             seq_frac_y,
    
    // Entradas SIMD
    input  logic [15:0]             simd_base_x,
    input  logic [15:0]             simd_base_y,
    input  logic [7:0]              scale_factor,
    
    input  logic [ADDR_WIDTH-1:0]   img_base_addr,

    // Interfaz memoria
    output logic                    mem_read_en,
    output logic [ADDR_WIDTH-1:0]   mem_addr,
    input  logic [7:0]              mem_data,

    // Salidas secuenciales
    output logic                    seq_fetch_valid,
    output logic [7:0]              seq_p00,
    output logic [7:0]              seq_p01,
    output logic [7:0]              seq_p10,
    output logic [7:0]              seq_p11,
    output logic [15:0]             seq_a,
    output logic [15:0]             seq_b,
    output logic                    seq_busy,

    // Salidas SIMD
    output logic                    simd_fetch_valid,
    output logic [7:0]              simd_p00_0, simd_p00_1, simd_p00_2, simd_p00_3,
    output logic [7:0]              simd_p01_0, simd_p01_1, simd_p01_2, simd_p01_3,
    output logic [7:0]              simd_p10_0, simd_p10_1, simd_p10_2, simd_p10_3,
    output logic [7:0]              simd_p11_0, simd_p11_1, simd_p11_2, simd_p11_3,
    output logic [15:0]             simd_a_0, simd_a_1, simd_a_2, simd_a_3,
    output logic [15:0]             simd_b_0, simd_b_1, simd_b_2, simd_b_3,
    output logic                    simd_busy
);

    // Señales internas
    logic                    seq_mem_read_en;
    logic [ADDR_WIDTH-1:0]   seq_mem_addr;
    logic                    simd_mem_read_en;
    logic [ADDR_WIDTH-1:0]   simd_mem_addr;
    
    logic [7:0]  simd_p00_array [0:SIMD_WIDTH-1];
    logic [7:0]  simd_p01_array [0:SIMD_WIDTH-1];
    logic [7:0]  simd_p10_array [0:SIMD_WIDTH-1];
    logic [7:0]  simd_p11_array [0:SIMD_WIDTH-1];
    logic [15:0] simd_a_array   [0:SIMD_WIDTH-1];
    logic [15:0] simd_b_array   [0:SIMD_WIDTH-1];

    // Conversión de arrays
    always_comb begin
        simd_p00_0 = simd_p00_array[0];
        simd_p00_1 = simd_p00_array[1];
        simd_p00_2 = simd_p00_array[2];
        simd_p00_3 = simd_p00_array[3];
        simd_p01_0 = simd_p01_array[0];
        simd_p01_1 = simd_p01_array[1];
        simd_p01_2 = simd_p01_array[2];
        simd_p01_3 = simd_p01_array[3];
        simd_p10_0 = simd_p10_array[0];
        simd_p10_1 = simd_p10_array[1];
        simd_p10_2 = simd_p10_array[2];
        simd_p10_3 = simd_p10_array[3];
        simd_p11_0 = simd_p11_array[0];
        simd_p11_1 = simd_p11_array[1];
        simd_p11_2 = simd_p11_array[2];
        simd_p11_3 = simd_p11_array[3];
        simd_a_0 = simd_a_array[0];
        simd_a_1 = simd_a_array[1];
        simd_a_2 = simd_a_array[2];
        simd_a_3 = simd_a_array[3];
        simd_b_0 = simd_b_array[0];
        simd_b_1 = simd_b_array[1];
        simd_b_2 = simd_b_array[2];
        simd_b_3 = simd_b_array[3];
    end

    // Fetch secuencial
    dsa_pixel_fetch_sequential #(
        .ADDR_WIDTH(ADDR_WIDTH)
    ) seq_fetch (
        .clk(clk),
        .rst(rst),
        .req_valid(req_valid && ! mode_simd),
        .src_x_int(seq_src_x_int),
        .src_y_int(seq_src_y_int),
        .frac_x(seq_frac_x),
        .frac_y(seq_frac_y),
        .img_base_addr(img_base_addr),
        .img_width(img_width),
        .img_height(img_height),
        . mem_read_en(seq_mem_read_en),
        .mem_addr(seq_mem_addr),
        .mem_data(mem_data),
        . fetch_valid(seq_fetch_valid),
        .p00(seq_p00),
        .p01(seq_p01),
        .p10(seq_p10),
        .p11(seq_p11),
        . a(seq_a),
        .b(seq_b),
        .busy(seq_busy)
    );

    // Fetch SIMD
    dsa_pixel_fetch_simd #(
        .ADDR_WIDTH(ADDR_WIDTH),
        . SIMD_WIDTH(SIMD_WIDTH)
    ) simd_fetch (
        .clk(clk),
        .rst(rst),
        .req_valid(req_valid && mode_simd),
        . base_x(simd_base_x),
        .base_y(simd_base_y),
        .scale_factor(scale_factor),
        .img_base_addr(img_base_addr),
        .img_width(img_width),
        .img_height(img_height),
        . mem_read_en(simd_mem_read_en),
        .mem_addr(simd_mem_addr),
        .mem_data(mem_data),
        .fetch_valid(simd_fetch_valid),
        . p00(simd_p00_array),
        .p01(simd_p01_array),
        .p10(simd_p10_array),
        .p11(simd_p11_array),
        .a(simd_a_array),
        .b(simd_b_array),
        . busy(simd_busy)
    );

    // Multiplexor de memoria
    always_comb begin
        if (mode_simd) begin
            mem_read_en = simd_mem_read_en;
            mem_addr    = simd_mem_addr;
        end else begin
            mem_read_en = seq_mem_read_en;
            mem_addr    = seq_mem_addr;
        end
    end

endmodule