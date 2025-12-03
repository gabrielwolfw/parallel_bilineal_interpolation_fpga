//============================================================
// dsa_de1soc_top.sv
// Top-level para DE1-SoC con JTAG UART
//============================================================

module dsa_de1soc_top (
    input  logic        CLOCK_50,
    input  logic [3:0]  KEY,
    input  logic [9:0]  SW,
    output logic [9:0]  LEDR,
    output logic [6:0]  HEX0,
    output logic [6:0]  HEX1,
    output logic [6:0]  HEX2,
    output logic [6:0]  HEX3,
    output logic [6:0]  HEX4,
    output logic [6:0]  HEX5
);

    //========================================================
    // Parámetros
    //========================================================
    localparam ADDR_WIDTH = 18;
    localparam DATA_WIDTH = 8;
    localparam MEM_SIZE   = 262144;

    //========================================================
    // Señales de reloj y reset
    //========================================================
    logic clk;
    logic rst_n;
    logic rst;
    
    assign clk = CLOCK_50;
    assign rst_n = KEY[0];
    assign rst = ~rst_n;
    
    //========================================================
    // Señales Avalon-MM para JTAG UART
    //========================================================
    logic        av_chipselect;
    logic        av_address;
    logic        av_read_n;
    logic        av_write_n;
    logic [31:0] av_readdata;
    logic [31:0] av_writedata;
    logic        av_waitrequest;
    
    //========================================================
    // Señales streaming para dsa_jtag_interface
    //========================================================
    logic [7:0] jtag_rx_data;
    logic       jtag_rx_valid;
    logic       jtag_rx_ready;
    logic [7:0] jtag_tx_data;
    logic       jtag_tx_valid;
    logic       jtag_tx_ready;
    
    //========================================================
    // Señales DSA
    //========================================================
    logic        dsa_start;
    logic        dsa_mode_simd;
    logic [15:0] dsa_img_width;
    logic [15:0] dsa_img_height;
    logic [7:0]  dsa_scale_factor;
    logic        dsa_busy;
    logic        dsa_ready;
    logic [15:0] dsa_progress;
    logic [31:0] dsa_flops_count;
    logic [31:0] dsa_mem_reads;
    logic [31:0] dsa_mem_writes;
    
    logic                    ext_mem_write_en;
    logic                    ext_mem_read_en;
    logic [ADDR_WIDTH-1:0]   ext_mem_addr;
    logic [DATA_WIDTH-1:0]   ext_mem_data_in;
    logic [DATA_WIDTH-1:0]   ext_mem_data_out;
    
    //========================================================
    // JTAG UART System (generado desde Platform Designer)
    //========================================================
    dsa_jtag_system u_jtag_uart (
        .clk_clk                                 (clk),
        .reset_reset_n                           (rst_n),
        .jtag_uart_avalon_jtag_slave_chipselect  (av_chipselect),
        . jtag_uart_avalon_jtag_slave_address     (av_address),
        .jtag_uart_avalon_jtag_slave_read_n      (av_read_n),
        . jtag_uart_avalon_jtag_slave_readdata    (av_readdata),
        .jtag_uart_avalon_jtag_slave_write_n     (av_write_n),
        .jtag_uart_avalon_jtag_slave_writedata   (av_writedata),
        .jtag_uart_avalon_jtag_slave_waitrequest (av_waitrequest)
    );
    
    //========================================================
    // Adaptador Avalon-MM <-> Streaming
    //========================================================
    jtag_avalon_adapter u_adapter (
        .clk            (clk),
        .rst            (rst),
        
        // Avalon-MM (active low signals)
        .av_chipselect  (av_chipselect),
        . av_address     (av_address),
        .av_read_n      (av_read_n),
        .av_write_n     (av_write_n),
        .av_readdata    (av_readdata),
        .av_writedata   (av_writedata),
        .av_waitrequest (av_waitrequest),
        
        // Streaming
        .rx_data        (jtag_rx_data),
        . rx_valid       (jtag_rx_valid),
        .rx_ready       (jtag_rx_ready),
        .tx_data        (jtag_tx_data),
        .tx_valid       (jtag_tx_valid),
        .tx_ready       (jtag_tx_ready)
    );
    
    //========================================================
    // Interfaz JTAG (protocolo de comandos)
    //========================================================
    dsa_jtag_interface #(
        . ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH)
    ) u_jtag_if (
        .clk(clk),
        .rst(rst),
        
        . dsa_start(dsa_start),
        .dsa_mode_simd(dsa_mode_simd),
        .dsa_img_width(dsa_img_width),
        .dsa_img_height(dsa_img_height),
        . dsa_scale_factor(dsa_scale_factor),
        .dsa_busy(dsa_busy),
        . dsa_ready(dsa_ready),
        .dsa_progress(dsa_progress),
        .dsa_flops_count(dsa_flops_count),
        . dsa_mem_reads(dsa_mem_reads),
        .dsa_mem_writes(dsa_mem_writes),
        
        .mem_write_en(ext_mem_write_en),
        .mem_read_en(ext_mem_read_en),
        .mem_addr(ext_mem_addr),
        .mem_data_out(ext_mem_data_in),
        .mem_data_in(ext_mem_data_out),
        
        .jtag_rx_data(jtag_rx_data),
        .jtag_rx_valid(jtag_rx_valid),
        .jtag_rx_ready(jtag_rx_ready),
        . jtag_tx_data(jtag_tx_data),
        . jtag_tx_valid(jtag_tx_valid),
        .jtag_tx_ready(jtag_tx_ready)
    );
    
    //========================================================
    // DSA Core
    //========================================================
    dsa_top #(
        . ADDR_WIDTH(ADDR_WIDTH),
        .MEM_SIZE(MEM_SIZE)
    ) u_dsa (
        .clk(clk),
        .rst(rst),
        . start(dsa_start),
        .mode_simd(dsa_mode_simd),
        . img_width_in(dsa_img_width),
        .img_height_in(dsa_img_height),
        .scale_factor(dsa_scale_factor),
        .ext_mem_write_en(ext_mem_write_en),
        .ext_mem_read_en(ext_mem_read_en),
        .ext_mem_addr(ext_mem_addr),
        .ext_mem_data_in(ext_mem_data_in),
        .ext_mem_data_out(ext_mem_data_out),
        .busy(dsa_busy),
        .ready(dsa_ready),
        .progress(dsa_progress),
        .flops_count(dsa_flops_count),
        . mem_reads_count(dsa_mem_reads),
        .mem_writes_count(dsa_mem_writes)
    );
    
    //========================================================
    // LEDs indicadores
    //========================================================
    assign LEDR[0] = dsa_busy;
    assign LEDR[1] = dsa_ready;
    assign LEDR[2] = dsa_mode_simd;
    assign LEDR[3] = jtag_tx_valid;
    assign LEDR[4] = jtag_rx_valid;
    assign LEDR[9:5] = dsa_progress[4:0];
    
    //========================================================
    // 7-Segment Display
    //========================================================
    function logic [6:0] hex7seg(input logic [3:0] hex);
        case (hex)
            4'h0: hex7seg = 7'b1000000;
            4'h1: hex7seg = 7'b1111001;
            4'h2: hex7seg = 7'b0100100;
            4'h3: hex7seg = 7'b0110000;
            4'h4: hex7seg = 7'b0011001;
            4'h5: hex7seg = 7'b0010010;
            4'h6: hex7seg = 7'b0000010;
            4'h7: hex7seg = 7'b1111000;
            4'h8: hex7seg = 7'b0000000;
            4'h9: hex7seg = 7'b0010000;
            4'hA: hex7seg = 7'b0001000;
            4'hB: hex7seg = 7'b0000011;
            4'hC: hex7seg = 7'b1000110;
            4'hD: hex7seg = 7'b0100001;
            4'hE: hex7seg = 7'b0000110;
            4'hF: hex7seg = 7'b0001110;
            default: hex7seg = 7'b1111111;
        endcase
    endfunction
    
    assign HEX0 = hex7seg(dsa_progress[3:0]);
    assign HEX1 = hex7seg(dsa_progress[7:4]);
    assign HEX2 = hex7seg(dsa_progress[11:8]);
    assign HEX3 = hex7seg(dsa_progress[15:12]);
    assign HEX4 = 7'b1111111;
    assign HEX5 = 7'b1111111;

endmodule