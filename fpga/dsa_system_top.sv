//============================================================
// dsa_system_top.sv
// Sistema completo con interfaz de comunicación
//============================================================

module dsa_system_top #(
    parameter IMG_WIDTH_MAX  = 512,
    parameter IMG_HEIGHT_MAX = 512,
    parameter MEM_SIZE       = 262144,
    parameter SIMD_WIDTH     = 4,
    parameter USE_UART       = 1,  // 1: UART, 0: JTAG
    parameter CLK_FREQ       = 50_000_000,
    parameter BAUD_RATE      = 115200
)(
    input  logic       clk,
    input  logic       rst,
    
    // UART (si USE_UART = 1)
    input  logic       uart_rx,
    output logic       uart_tx,
    
    // LEDs de estado
    output logic [3:0] status_leds
);

    //=================================================================
    // Señales de interconexión
    //=================================================================
    
    logic        dsa_start;
    logic        dsa_mode_simd;
    logic [9:0]  dsa_img_width_in;
    logic [9:0]  dsa_img_height_in;
    logic [7:0]  dsa_scale_factor;
    logic        dsa_mem_write_en;
    logic        dsa_mem_read_en;
    logic [17:0] dsa_mem_addr;
    logic [7:0]  dsa_mem_data_in;
    logic [7:0]  dsa_mem_data_out;
    logic        dsa_busy;
    logic        dsa_ready;
    logic        dsa_error;
    logic [15:0] dsa_progress;
    logic [31:0] dsa_flops_count;
    logic [31:0] dsa_mem_reads_count;
    logic [31:0] dsa_mem_writes_count;
    
    //=================================================================
    // Instancia del DSA core
    //=================================================================
    
    dsa_top #(
        .IMG_WIDTH_MAX(IMG_WIDTH_MAX),
        .IMG_HEIGHT_MAX(IMG_HEIGHT_MAX),
        .MEM_SIZE(MEM_SIZE),
        .SIMD_WIDTH(SIMD_WIDTH)
    ) dsa_core (
        .clk(clk),
        .rst(rst),
        .start(dsa_start),
        .mode_simd(dsa_mode_simd),
        .img_width_in(dsa_img_width_in),
        .img_height_in(dsa_img_height_in),
        .scale_factor(dsa_scale_factor),
        .mem_write_en(dsa_mem_write_en),
        .mem_read_en(dsa_mem_read_en),
        .mem_addr(dsa_mem_addr),
        .mem_data_in(dsa_mem_data_in),
        .mem_data_out(dsa_mem_data_out),
        .busy(dsa_busy),
        .ready(dsa_ready),
        .error(dsa_error),
        .progress(dsa_progress),
        .flops_count(dsa_flops_count),
        .mem_reads_count(dsa_mem_reads_count),
        .mem_writes_count(dsa_mem_writes_count)
    );
    
    //=================================================================
    // Interfaz de comunicación
    //=================================================================
    
    generate
        if (USE_UART) begin : uart_interface
            dsa_uart_interface #(
                .CLK_FREQ(CLK_FREQ),
                .BAUD_RATE(BAUD_RATE),
                .MEM_SIZE(MEM_SIZE)
            ) comm_if (
                .clk(clk),
                .rst(rst),
                .uart_rx(uart_rx),
                .uart_tx(uart_tx),
                .dsa_start(dsa_start),
                .dsa_mode_simd(dsa_mode_simd),
                .dsa_img_width_in(dsa_img_width_in),
                .dsa_img_height_in(dsa_img_height_in),
                .dsa_scale_factor(dsa_scale_factor),
                .dsa_mem_write_en(dsa_mem_write_en),
                .dsa_mem_read_en(dsa_mem_read_en),
                .dsa_mem_addr(dsa_mem_addr),
                .dsa_mem_data_in(dsa_mem_data_in),
                .dsa_mem_data_out(dsa_mem_data_out),
                .dsa_busy(dsa_busy),
                .dsa_ready(dsa_ready),
                .dsa_error(dsa_error),
                .dsa_progress(dsa_progress),
                .dsa_flops_count(dsa_flops_count),
                .dsa_mem_reads_count(dsa_mem_reads_count),
                .dsa_mem_writes_count(dsa_mem_writes_count)
            );
        end else begin : jtag_interface
            dsa_jtag_interface #(
                .MEM_SIZE(MEM_SIZE)
            ) comm_if (
                .clk(clk),
                .rst(rst),
                .dsa_start(dsa_start),
                .dsa_mode_simd(dsa_mode_simd),
                .dsa_img_width_in(dsa_img_width_in),
                .dsa_img_height_in(dsa_img_height_in),
                .dsa_scale_factor(dsa_scale_factor),
                .dsa_mem_write_en(dsa_mem_write_en),
                .dsa_mem_read_en(dsa_mem_read_en),
                .dsa_mem_addr(dsa_mem_addr),
                .dsa_mem_data_in(dsa_mem_data_in),
                .dsa_mem_data_out(dsa_mem_data_out),
                .dsa_busy(dsa_busy),
                .dsa_ready(dsa_ready),
                .dsa_error(dsa_error),
                .dsa_progress(dsa_progress),
                .dsa_flops_count(dsa_flops_count),
                .dsa_mem_reads_count(dsa_mem_reads_count),
                .dsa_mem_writes_count(dsa_mem_writes_count),
                .step_enable(),
                .step_trigger()
            );
        end
    endgenerate
    
    //=================================================================
    // LEDs de estado
    //=================================================================
    
    assign status_leds[0] = dsa_busy;
    assign status_leds[1] = dsa_ready;
    assign status_leds[2] = dsa_error;
    assign status_leds[3] = dsa_mode_simd;

endmodule