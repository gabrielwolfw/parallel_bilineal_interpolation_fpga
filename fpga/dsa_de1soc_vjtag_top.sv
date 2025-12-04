//============================================================
// dsa_de1soc_vjtag_top.sv
// Top-level completo para DE1-SoC con Virtual JTAG
// Permite comunicación PC <-> FPGA para control de DSA
//============================================================

module dsa_de1soc_vjtag_top (
    //////////// CLOCK //////////
    input  logic        CLOCK_50,
    
    //////////// KEY //////////
    input  logic [3:0]  KEY,
    
    //////////// SW //////////
    input  logic [9:0]  SW,
    
    //////////// LED //////////
    output logic [9:0]  LEDR,
    
    //////////// 7-SEG //////////
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
    localparam DATA_WIDTH = 16;  // Ancho de datos VJTAG (debe coincidir con TCL/Python)
    localparam MEM_SIZE   = 262144;
    localparam IMG_WIDTH  = 512;
    localparam IMG_HEIGHT = 512;
    localparam SIMD_WIDTH = 4;

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
    // Señales Virtual JTAG IP
    //========================================================
    wire        vjtag_tdi;
    wire        vjtag_tdo;
    wire [1:0]  vjtag_ir_in;
    wire        vjtag_v_cdr;
    wire        vjtag_v_sdr;
    wire        vjtag_v_udr;
    wire        vjtag_tck;
    
    //========================================================
    // Señales VJTAG Interface
    //========================================================
    logic [DATA_WIDTH-1:0] jtag_data_out;  // PC -> FPGA
    logic [DATA_WIDTH-1:0] jtag_data_in;   // FPGA -> PC
    logic [DATA_WIDTH-1:0] debug_dr1;
    logic [DATA_WIDTH-1:0] debug_dr2;
    
    //========================================================
    // Registros de control (mapeo de comandos)
    //========================================================
    typedef enum logic [3:0] {
        REG_CONTROL       = 4'd0,  // [0]=start, [1]=mode_simd
        REG_IMG_WIDTH_LO  = 4'd1,  // Bits [7:0] del ancho
        REG_IMG_WIDTH_HI  = 4'd2,  // Bits [15:8] del ancho
        REG_IMG_HEIGHT_LO = 4'd3,  // Bits [7:0] del alto
        REG_IMG_HEIGHT_HI = 4'd4,  // Bits [15:8] del alto
        REG_SCALE_FACTOR  = 4'd5,  // Factor de escala
        REG_STATUS        = 4'd6,  // [0]=busy, [1]=ready
        REG_PROGRESS_LO   = 4'd7,  // Progress[7:0]
        REG_PROGRESS_HI   = 4'd8,  // Progress[15:8]
        REG_MEM_ADDR_LO   = 4'd9,  // Dirección memoria [7:0]
        REG_MEM_ADDR_HI   = 4'd10, // Dirección memoria [15:8]
        REG_MEM_DATA      = 4'd11, // Dato para leer/escribir memoria
        REG_FLOPS_0       = 4'd12, // FLOPs counter [7:0]
        REG_FLOPS_1       = 4'd13, // FLOPs counter [15:8]
        REG_FLOPS_2       = 4'd14, // FLOPs counter [23:16]
        REG_FLOPS_3       = 4'd15  // FLOPs counter [31:24]
    } reg_addr_t;
    
    logic [3:0]  current_reg_addr;
    logic [15:0] img_width_reg;
    logic [15:0] img_height_reg;
    logic [7:0]  scale_factor_reg;
    logic        mode_simd_reg;
    logic        start_pulse;
    logic [17:0] mem_addr_reg;
    
    //========================================================
    // Señales DSA
    //========================================================
    logic        dsa_start;
    logic        dsa_busy;
    logic        dsa_ready;
    logic [15:0] dsa_progress;
    logic [31:0] dsa_flops_count;
    logic [31:0] dsa_mem_reads;
    logic [31:0] dsa_mem_writes;
    
    logic                    ext_mem_write_en;
    logic                    ext_mem_read_en;
    logic [ADDR_WIDTH-1:0]   ext_mem_addr;
    logic [7:0]              ext_mem_data_in;
    logic [7:0]              ext_mem_data_out;
    
    //========================================================
    // Lógica de sincronización para comandos desde VJTAG
    //========================================================
    logic [DATA_WIDTH-1:0] jtag_data_sync;
    logic                  jtag_data_valid;
    
    // Sincronizar datos de VJTAG (dominio tck) a clk del sistema
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            jtag_data_sync <= '0;
            jtag_data_valid <= 1'b0;
        end else begin
            jtag_data_sync <= jtag_data_out;
            jtag_data_valid <= (jtag_data_sync != jtag_data_out);
        end
    end
    
    //========================================================
    // Decodificación de comandos VJTAG
    // Bits [15:12] = Dirección de registro
    // Bits [11:8]  = Comando (0=NOP, 1=WRITE_REG, 2=READ_REG, 3=WRITE_MEM, 4=READ_MEM)
    // Bits [7:0]   = Datos
    //========================================================
    logic [3:0] cmd_addr;
    logic [3:0] cmd_type;
    logic [7:0] cmd_data;
    
    assign cmd_addr = jtag_data_sync[15:12];
    assign cmd_type = jtag_data_sync[11:8];
    assign cmd_data = jtag_data_sync[7:0];
    
    localparam CMD_NOP       = 4'd0;
    localparam CMD_WRITE_REG = 4'd1;
    localparam CMD_READ_REG  = 4'd2;
    localparam CMD_WRITE_MEM = 4'd3;
    localparam CMD_READ_MEM  = 4'd4;
    
    //========================================================
    // Procesamiento de comandos
    //========================================================
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            img_width_reg <= 16'd512;
            img_height_reg <= 16'd512;
            scale_factor_reg <= 8'h80;  // 0.5x (128 en Q8.8)
            mode_simd_reg <= 1'b0;
            start_pulse <= 1'b0;
            current_reg_addr <= 4'd0;
            mem_addr_reg <= 18'd0;
            ext_mem_write_en <= 1'b0;
            ext_mem_read_en <= 1'b0;
        end else begin
            // Defaults
            start_pulse <= 1'b0;
            ext_mem_write_en <= 1'b0;
            ext_mem_read_en <= 1'b0;
            
            if (jtag_data_valid) begin
                case (cmd_type)
                    CMD_WRITE_REG: begin
                        case (reg_addr_t'(cmd_addr))
                            REG_CONTROL: begin
                                mode_simd_reg <= cmd_data[1];
                                start_pulse <= cmd_data[0];
                            end
                            REG_IMG_WIDTH_LO:  img_width_reg[7:0] <= cmd_data;
                            REG_IMG_WIDTH_HI:  img_width_reg[15:8] <= cmd_data;
                            REG_IMG_HEIGHT_LO: img_height_reg[7:0] <= cmd_data;
                            REG_IMG_HEIGHT_HI: img_height_reg[15:8] <= cmd_data;
                            REG_SCALE_FACTOR:  scale_factor_reg <= cmd_data;
                            REG_MEM_ADDR_LO:   mem_addr_reg[7:0] <= cmd_data;
                            REG_MEM_ADDR_HI:   mem_addr_reg[17:8] <= {2'b00, cmd_data};
                            default: ;
                        endcase
                    end
                    
                    CMD_READ_REG: begin
                        current_reg_addr <= cmd_addr;
                    end
                    
                    CMD_WRITE_MEM: begin
                        ext_mem_write_en <= 1'b1;
                        ext_mem_addr <= mem_addr_reg;
                        ext_mem_data_in <= cmd_data;
                        mem_addr_reg <= mem_addr_reg + 1;
                    end
                    
                    CMD_READ_MEM: begin
                        ext_mem_read_en <= 1'b1;
                        ext_mem_addr <= mem_addr_reg;
                        mem_addr_reg <= mem_addr_reg + 1;
                    end
                    
                    default: ;
                endcase
            end
        end
    end
    
    //========================================================
    // Multiplexor de lectura de registros
    //========================================================
    always_comb begin
        case (reg_addr_t'(current_reg_addr))
            REG_CONTROL:       jtag_data_in = {14'd0, mode_simd_reg, dsa_start};
            REG_IMG_WIDTH_LO:  jtag_data_in = {8'd0, img_width_reg[7:0]};
            REG_IMG_WIDTH_HI:  jtag_data_in = {8'd0, img_width_reg[15:8]};
            REG_IMG_HEIGHT_LO: jtag_data_in = {8'd0, img_height_reg[7:0]};
            REG_IMG_HEIGHT_HI: jtag_data_in = {8'd0, img_height_reg[15:8]};
            REG_SCALE_FACTOR:  jtag_data_in = {8'd0, scale_factor_reg};
            REG_STATUS:        jtag_data_in = {14'd0, dsa_ready, dsa_busy};
            REG_PROGRESS_LO:   jtag_data_in = {8'd0, dsa_progress[7:0]};
            REG_PROGRESS_HI:   jtag_data_in = {8'd0, dsa_progress[15:8]};
            REG_MEM_ADDR_LO:   jtag_data_in = {8'd0, mem_addr_reg[7:0]};
            REG_MEM_ADDR_HI:   jtag_data_in = {6'd0, mem_addr_reg[17:8]};
            REG_MEM_DATA:      jtag_data_in = {8'd0, ext_mem_data_out};
            REG_FLOPS_0:       jtag_data_in = {8'd0, dsa_flops_count[7:0]};
            REG_FLOPS_1:       jtag_data_in = {8'd0, dsa_flops_count[15:8]};
            REG_FLOPS_2:       jtag_data_in = {8'd0, dsa_flops_count[23:16]};
            REG_FLOPS_3:       jtag_data_in = {8'd0, dsa_flops_count[31:24]};
            default:           jtag_data_in = 16'hDEAD;
        endcase
    end
    
    //========================================================
    // Generador de pulso de start
    //========================================================
    assign dsa_start = start_pulse;
    
    //========================================================
    // Virtual JTAG IP Core
    //========================================================
    vjtag_dsa u_vjtag (
        .tdi                (vjtag_tdi),
        .tdo                (vjtag_tdo),
        .ir_in              (vjtag_ir_in),
        .ir_out             (),
        .virtual_state_cdr  (vjtag_v_cdr),
        .virtual_state_sdr  (vjtag_v_sdr),
        .virtual_state_e1dr (),
        .virtual_state_pdr  (),
        .virtual_state_e2dr (),
        .virtual_state_udr  (vjtag_v_udr),
        .virtual_state_cir  (),
        .virtual_state_uir  (),
        .tck                (vjtag_tck)
    );
    
    //========================================================
    // VJTAG Interface
    //========================================================
    vjtag_interface #(
        .DW(DATA_WIDTH)
    ) u_vjtag_interface (
        .tck        (vjtag_tck),
        .tdi        (vjtag_tdi),
        .aclr       (rst_n),
        .ir_in      (vjtag_ir_in),
        .v_sdr      (vjtag_v_sdr),
        .v_cdr      (vjtag_v_cdr),
        .udr        (vjtag_v_udr),
        .data_out   (jtag_data_out),
        .data_in    (jtag_data_in),
        .tdo        (vjtag_tdo),
        .debug_dr1  (debug_dr1),
        .debug_dr2  (debug_dr2)
    );
    
    //========================================================
    // DSA Core (Acelerador de interpolación)
    //========================================================
    dsa_top #(
        .ADDR_WIDTH (ADDR_WIDTH),
        .IMG_WIDTH  (IMG_WIDTH),
        .IMG_HEIGHT (IMG_HEIGHT),
        .SIMD_WIDTH (SIMD_WIDTH),
        .MEM_SIZE   (MEM_SIZE)
    ) u_dsa (
        .clk                (clk),
        .rst                (rst),
        .start              (dsa_start),
        .mode_simd          (mode_simd_reg),
        .img_width_in       (img_width_reg),
        .img_height_in      (img_height_reg),
        .scale_factor       (scale_factor_reg),
        .ext_mem_write_en   (ext_mem_write_en),
        .ext_mem_read_en    (ext_mem_read_en),
        .ext_mem_addr       (ext_mem_addr),
        .ext_mem_data_in    (ext_mem_data_in),
        .ext_mem_data_out   (ext_mem_data_out),
        .busy               (dsa_busy),
        .ready              (dsa_ready),
        .progress           (dsa_progress),
        .flops_count        (dsa_flops_count),
        .mem_reads_count    (dsa_mem_reads),
        .mem_writes_count   (dsa_mem_writes)
    );
    
    //========================================================
    // LEDs indicadores
    //========================================================
    assign LEDR[0] = dsa_busy;
    assign LEDR[1] = dsa_ready;
    assign LEDR[2] = mode_simd_reg;
    assign LEDR[3] = ext_mem_write_en;
    assign LEDR[4] = ext_mem_read_en;
    assign LEDR[5] = start_pulse;
    assign LEDR[9:6] = dsa_progress[3:0];
    
    //========================================================
    // 7-Segment Display (muestra progreso)
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
    assign HEX4 = hex7seg(mem_addr_reg[3:0]);
    assign HEX5 = hex7seg(mem_addr_reg[7:4]);

endmodule
