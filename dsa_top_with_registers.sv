//==============================================================================
// Module: dsa_top_with_registers
//==============================================================================
// Descripción: Módulo top-level MEJORADO que integra:
//              - VJTAG Interface para debugging y control desde PC
//              - RAM dual-port 64KB con registros memory-mapped
//              - dsa_register_bank para configuración dinámica
//              - DSA (Domain-Specific Architecture) para interpolación bilineal
//              - Control manual con KEYs y visualización con HEX displays
//
// Características:
//   - Memoria: 64KB RAM dual-port (16-bit addressing)
//   - Registros: 0x0000-0x003F (64 bytes) para configuración DSA
//   - VJTAG: Acceso a memoria y registros desde PC
//   - DSA: Lee configuración desde registros (no switches)
//   - Control: SW[0] = modo visualización (0=JTAG debug, 1=Manual address)
//              KEY[0] = Incrementar dirección manual
//              KEY[1] = Decrementar dirección manual
//              KEY[2] = Reset DSA
//              KEY[3] = Reset general
//
// Autor: DSA Project
// Fecha: Diciembre 2024
//==============================================================================

module dsa_top_with_registers #(
    parameter int DATA_WIDTH = 8,     // Ancho de datos (8 bits)
    parameter int ADDR_WIDTH = 16,    // Ancho de dirección (16 bits - 64KB)
    parameter int IMG_WIDTH_MAX = 512,
    parameter int IMG_HEIGHT_MAX = 512
) (
    // Clock
    input  logic clk,
    
    // KEYs (DE1-SoC tiene 4 KEYs, activos en bajo)
    input  logic [3:0] KEY,
    
    // LEDs de debug (DE1-SoC tiene 10 LEDs rojos)
    output logic [9:0] LEDR,
    
    // Displays de 7 segmentos (6 displays en DE1-SoC)
    output logic [6:0] HEX0,
    output logic [6:0] HEX1,
    output logic [6:0] HEX2,
    output logic [6:0] HEX3,
    output logic [6:0] HEX4,
    output logic [6:0] HEX5,
    
    // Switches (10 switches en DE1-SoC)
    // SW[0] = modo visualización (0=JTAG, 1=Manual)
    input  logic [9:0] SW
);

    //==========================================================================
    // Señales de Reset y Control
    //==========================================================================
    logic reset_n;          // Reset general (activo bajo)
    logic dsa_reset;        // Reset DSA (activo alto)
    
    assign reset_n = KEY[3];
    
    // Detección de flancos para KEYs (anti-rebote simple)
    logic [2:0] key_prev;  // KEY[2:0] previo
    logic key2_pulse;      // Pulso para reset DSA
    
    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            key_prev <= 3'b111;
            key2_pulse <= 1'b0;
        end else begin
            key_prev <= KEY[2:0];
            key2_pulse <= (!KEY[2] && key_prev[2]);  // Flanco descendente KEY[2]
        end
    end
    
    assign dsa_reset = key2_pulse;
    
    //==========================================================================
    // Control Manual de Dirección con KEYs
    //==========================================================================
    logic [ADDR_WIDTH-1:0] manual_addr;
    
    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            manual_addr <= '0;
        end else begin
            if (!KEY[0] && key_prev[0])
                manual_addr <= manual_addr + 1'b1;
            
            if (!KEY[1] && key_prev[1] && manual_addr != 0)
                manual_addr <= manual_addr - 1'b1;
        end
    end
    
    logic display_mode;
    assign display_mode = SW[0];
    
    //==========================================================================
    // Señales VJTAG
    //==========================================================================
    logic [DATA_WIDTH-1:0] jtag_data_out;
    logic [DATA_WIDTH-1:0] jtag_data_in;
    logic [ADDR_WIDTH-1:0] jtag_addr_out;
    
    //==========================================================================
    // Señales del Register Bank
    //==========================================================================
    logic [15:0] cfg_width;
    logic [15:0] cfg_height;
    logic [15:0] cfg_scale_q8_8;
    logic        cfg_start;           // Pulso de start
    logic        cfg_mode_simd;
    logic [5:0]  cfg_simd_idx;
    logic [7:0]  cfg_simd_n;
    logic [31:0] cfg_img_in_base;
    logic [31:0] cfg_img_out_base;
    logic        cfg_crc_in_en;
    logic        cfg_crc_out_en;
    logic [7:0]  cfg_step_ctrl;
    logic        cfg_soft_reset;
    logic        cfg_clear_errors;
    
    logic        status_idle;
    logic        status_busy;
    logic        status_done;
    logic        status_error;
    logic [7:0]  status_progress;
    logic [15:0] status_fsm_state;
    logic [15:0] err_code;
    logic [15:0] out_width;
    logic [15:0] out_height;
    logic [15:0] progress_x;
    logic [15:0] progress_y;
    
    logic [31:0] perf_flops;
    logic [31:0] perf_mem_rd;
    logic [31:0] perf_mem_wr;
    logic [31:0] cycle_count;
    logic [31:0] pixels_done;
    logic [15:0] fetch_latency;
    logic [15:0] interp_latency;
    
    logic [7:0]  dbg_state;
    logic [15:0] dbg_last_addr;
    logic [31:0] step_expose;
    logic [31:0] crc_value;
    
    logic [7:0]  reg_rdata;
    logic        reg_hit;             // 1=acceso a registro, 0=acceso a RAM
    
    //==========================================================================
    // Señales DSA
    //==========================================================================
    logic        dsa_busy;
    logic        dsa_ready;
    logic [15:0] dsa_current_x;
    logic [15:0] dsa_current_y;
    
    // Señales fetch
    logic        fetch_req;
    logic        fetch_done;
    logic [15:0] fetch_src_x_int;
    logic [15:0] fetch_src_y_int;
    logic [15:0] fetch_frac_x;
    logic [15:0] fetch_frac_y;
    logic        fetch_valid;
    logic [7:0]  fetch_p00, fetch_p01, fetch_p10, fetch_p11;
    logic [15:0] fetch_a, fetch_b;
    logic        fetch_busy;
    
    // Señales datapath
    logic        dp_start;
    logic        dp_done;
    logic [7:0]  dp_pixel_out;
    
    // Señales de escritura DSA
    logic        dsa_write_enable;
    
    //==========================================================================
    // Señales RAM (DUAL_PORT mode)
    //==========================================================================
    logic [ADDR_WIDTH-1:0] ram_wraddress;
    logic [ADDR_WIDTH-1:0] ram_rdaddress;
    logic [DATA_WIDTH-1:0] ram_data;
    logic                  ram_wren;
    logic [DATA_WIDTH-1:0] ram_q;
    
    //==========================================================================
    // Detección de escritura VJTAG
    //==========================================================================
    logic jtag_write_strobe;
    logic [DATA_WIDTH-1:0] jtag_data_out_prev;
    
    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            jtag_data_out_prev <= '0;
            jtag_write_strobe <= 1'b0;
        end else begin
            jtag_data_out_prev <= jtag_data_out;
            jtag_write_strobe <= (jtag_data_out != jtag_data_out_prev);
        end
    end
    
    //==========================================================================
    // Cálculo de dimensiones de salida
    //==========================================================================
    logic [15:0] img_width_out;
    logic [15:0] img_height_out;
    
    assign img_width_out = (({16'd0, cfg_width} * {16'd0, cfg_scale_q8_8}) >> 8);
    assign img_height_out = (({16'd0, cfg_height} * {16'd0, cfg_scale_q8_8}) >> 8);
    
    //==========================================================================
    // Cálculo de direcciones DSA
    //==========================================================================
    logic [31:0] dsa_write_addr_full;
    logic [ADDR_WIDTH-1:0] dsa_write_addr;
    
    assign dsa_write_addr_full = cfg_img_out_base + 
                                 ({16'd0, dsa_current_y} * {16'd0, img_width_out}) + 
                                 {16'd0, dsa_current_x};
    assign dsa_write_addr = dsa_write_addr_full[ADDR_WIDTH-1:0];
    
    // Dirección de lectura del fetch module
    logic [ADDR_WIDTH-1:0] fetch_mem_addr;
    logic                  fetch_mem_read_en;
    
    //==========================================================================
    // Arbitraje de memoria: Registros vs RAM, VJTAG vs DSA
    //==========================================================================
    logic dsa_enable;
    assign dsa_enable = cfg_start && !dsa_reset;
    
    always_comb begin
        if (dsa_enable && dsa_busy) begin
            // Modo DSA activo: Fetch lee, datapath escribe
            ram_rdaddress = fetch_mem_addr;
            ram_wraddress = dsa_write_addr;
            ram_data = dp_pixel_out;
            ram_wren = dsa_write_enable && !reg_hit;  // No escribir en registros
        end else begin
            // Modo JTAG/Manual: Acceso desde PC o lectura manual
            ram_rdaddress = display_mode ? manual_addr : jtag_addr_out;
            ram_wraddress = jtag_addr_out;
            ram_data = jtag_data_out;
            ram_wren = jtag_write_strobe && !reg_hit;  // No escribir en registros si reg_hit
        end
    end
    
    assign jtag_data_in = ram_q;
    
    //==========================================================================
    // Cálculo de coordenadas fuente para interpolación (Q8.8)
    //==========================================================================
    logic [31:0] inv_scale_q8_8;
    logic [31:0] src_x_full, src_y_full;
    
    assign inv_scale_q8_8 = (cfg_scale_q8_8 != 16'd0) ? 
                            (32'd65536 / {16'd0, cfg_scale_q8_8}) : 
                            32'd256;
    
    assign src_x_full = dsa_current_x * inv_scale_q8_8;
    assign src_y_full = dsa_current_y * inv_scale_q8_8;
    
    assign fetch_src_x_int = src_x_full[23:8];
    assign fetch_src_y_int = src_y_full[23:8];
    assign fetch_frac_x = {src_x_full[7:0], 8'd0};
    assign fetch_frac_y = {src_y_full[7:0], 8'd0};
    
    //==========================================================================
    // Asignación de señales de status
    //==========================================================================
    assign status_idle = dsa_ready;
    assign status_busy = dsa_busy;
    assign status_done = dsa_ready && !dsa_busy;  // Done cuando termina
    assign status_error = 1'b0;  // Por implementar
    assign status_progress = 8'd0;  // Calcular porcentaje real
    assign status_fsm_state = 16'd0;  // Por conectar desde FSM
    assign err_code = 16'd0;
    assign out_width = img_width_out;
    assign out_height = img_height_out;
    assign progress_x = dsa_current_x;
    assign progress_y = dsa_current_y;
    
    // Contadores de performance (placeholder - implementar en módulos DSA)
    assign perf_flops = 32'd0;
    assign perf_mem_rd = 32'd0;
    assign perf_mem_wr = 32'd0;
    assign cycle_count = 32'd0;
    assign pixels_done = 32'd0;
    assign fetch_latency = 16'd0;
    assign interp_latency = 16'd0;
    
    // Debug signals
    assign dbg_state = 8'd0;
    assign dbg_last_addr = 16'd0;
    assign step_expose = 32'd0;
    assign crc_value = 32'd0;
    
    //==========================================================================
    // Instancia del Register Bank
    //==========================================================================
    dsa_register_bank reg_bank_inst (
        .clk(clk),
        .reset_n(reset_n),
        
        // Interfaz de memoria (8-bit bus)
        .addr(jtag_addr_out),
        .wdata(jtag_data_out),
        .wr_en(jtag_write_strobe),
        .rd_en(1'b1),
        .rdata(reg_rdata),
        .reg_hit(reg_hit),
        
        // Configuración (outputs)
        .cfg_width(cfg_width),
        .cfg_height(cfg_height),
        .cfg_scale_q8_8(cfg_scale_q8_8),
        .cfg_start(cfg_start),
        .cfg_mode_simd(cfg_mode_simd),
        .cfg_simd_idx(cfg_simd_idx),
        .cfg_simd_n(cfg_simd_n),
        .cfg_img_in_base(cfg_img_in_base),
        .cfg_img_out_base(cfg_img_out_base),
        .cfg_crc_in_en(cfg_crc_in_en),
        .cfg_crc_out_en(cfg_crc_out_en),
        .cfg_step_ctrl(cfg_step_ctrl),
        .cfg_soft_reset(cfg_soft_reset),
        .cfg_clear_errors(cfg_clear_errors),
        
        // Status (inputs)
        .status_idle(status_idle),
        .status_busy(status_busy),
        .status_done(status_done),
        .status_error(status_error),
        .status_progress(status_progress),
        .status_fsm_state(status_fsm_state),
        .err_code(err_code),
        .out_width(out_width),
        .out_height(out_height),
        .progress_x(progress_x),
        .progress_y(progress_y),
        
        // Performance (inputs)
        .perf_flops(perf_flops),
        .perf_mem_rd(perf_mem_rd),
        .perf_mem_wr(perf_mem_wr),
        .cycle_count(cycle_count),
        .pixels_done(pixels_done),
        .fetch_latency(fetch_latency),
        .interp_latency(interp_latency),
        
        // Debug inputs
        .dbg_state(dbg_state),
        .dbg_last_addr(dbg_last_addr),
        .step_expose(step_expose),
        .crc_value(crc_value)
    );
    
    //==========================================================================
    // VJTAG Interface
    //==========================================================================
    vjtag_interface #(
        .DW(DATA_WIDTH),
        .AW(ADDR_WIDTH)
    ) vjtag_inst (
        .sys_clk(clk),
        .aclr(reset_n),
        .data_out(jtag_data_out),
        .data_in(jtag_data_in),
        .addr_out(jtag_addr_out),
        .debug_dr1(),
        .debug_dr2()
    );
    
    //==========================================================================
    // RAM dual-port (64KB)
    //==========================================================================
    ram ram_inst (
        .clock(clk),
        .data(ram_data),
        .rdaddress(ram_rdaddress),
        .wraddress(ram_wraddress),
        .wren(ram_wren),
        .q(ram_q)
    );
    
    //==========================================================================
    // FSM de control DSA (secuencial)
    //==========================================================================
    dsa_control_fsm_sequential #(
        .IMG_WIDTH_MAX(IMG_WIDTH_MAX),
        .IMG_HEIGHT_MAX(IMG_HEIGHT_MAX)
    ) dsa_fsm (
        .clk(clk),
        .rst(dsa_reset || !reset_n || cfg_soft_reset),
        .enable(dsa_enable),
        .img_width_out(img_width_out),
        .img_height_out(img_height_out),
        .fetch_req(fetch_req),
        .fetch_done(fetch_done),
        .dp_start(dp_start),
        .dp_done(dp_done),
        .write_enable(dsa_write_enable),
        .current_x(dsa_current_x),
        .current_y(dsa_current_y),
        .busy(dsa_busy),
        .ready(dsa_ready)
    );
    
    //==========================================================================
    // Pixel Fetch (secuencial)
    //==========================================================================
    dsa_pixel_fetch_sequential #(
        .ADDR_WIDTH(ADDR_WIDTH)
    ) dsa_fetch (
        .clk(clk),
        .rst(dsa_reset || !reset_n || cfg_soft_reset),
        .req_valid(fetch_req),
        .src_x_int(fetch_src_x_int),
        .src_y_int(fetch_src_y_int),
        .frac_x(fetch_frac_x),
        .frac_y(fetch_frac_y),
        .img_base_addr(cfg_img_in_base[15:0]),
        .img_width(cfg_width),
        .img_height(cfg_height),
        .mem_read_en(fetch_mem_read_en),
        .mem_addr(fetch_mem_addr),
        .mem_data(ram_q),
        .fetch_valid(fetch_valid),
        .p00(fetch_p00),
        .p01(fetch_p01),
        .p10(fetch_p10),
        .p11(fetch_p11),
        .a(fetch_a),
        .b(fetch_b),
        .busy(fetch_busy)
    );
    
    assign fetch_done = fetch_valid;
    
    //==========================================================================
    // Datapath de interpolación
    //==========================================================================
    dsa_datapath dsa_dp (
        .clk(clk),
        .rst(dsa_reset || !reset_n || cfg_soft_reset),
        .start(dp_start),
        .p00(fetch_p00),
        .p01(fetch_p01),
        .p10(fetch_p10),
        .p11(fetch_p11),
        .a(fetch_a),
        .b(fetch_b),
        .pixel_out(dp_pixel_out),
        .done(dp_done)
    );
    
    //==========================================================================
    // LEDs de Debug
    //==========================================================================
    assign LEDR[0] = display_mode;      // SW[0]
    assign LEDR[1] = cfg_start;         // START desde registro
    assign LEDR[2] = dsa_ready;
    assign LEDR[3] = dsa_busy;
    assign LEDR[4] = ~KEY[0];
    assign LEDR[5] = ~KEY[1];
    assign LEDR[6] = dsa_write_enable;
    assign LEDR[7] = fetch_busy;
    assign LEDR[8] = reg_hit;           // Acceso a registro
    assign LEDR[9] = status_done;
    
    //==========================================================================
    // HEX Displays
    //==========================================================================
    logic [3:0] hex0_val, hex1_val, hex2_val, hex3_val, hex4_val, hex5_val;
    logic [ADDR_WIDTH-1:0] display_addr;
    logic [DATA_WIDTH-1:0] display_data;
    
    always_comb begin
        if (display_mode) begin
            display_addr = manual_addr;
            display_data = ram_q;
        end else begin
            display_addr = jtag_addr_out;
            display_data = ram_q;
        end
        
        hex0_val = display_data[3:0];
        hex1_val = display_data[7:4];
        hex2_val = display_addr[3:0];
        hex3_val = display_addr[7:4];
        hex4_val = display_addr[11:8];
        hex5_val = display_addr[15:12];
    end
    
    hex7seg hex7seg_0 (.in(hex0_val), .out(HEX0));
    hex7seg hex7seg_1 (.in(hex1_val), .out(HEX1));
    hex7seg hex7seg_2 (.in(hex2_val), .out(HEX2));
    hex7seg hex7seg_3 (.in(hex3_val), .out(HEX3));
    hex7seg hex7seg_4 (.in(hex4_val), .out(HEX4));
    hex7seg hex7seg_5 (.in(hex5_val), .out(HEX5));

endmodule

//==============================================================================
// Módulo auxiliar: Decodificador hexadecimal a 7 segmentos
//==============================================================================
module hex7seg (
    input  logic [3:0] in,
    output logic [6:0] out
);
    always_comb begin
        case (in)
            4'h0: out = 7'b1000000;
            4'h1: out = 7'b1111001;
            4'h2: out = 7'b0100100;
            4'h3: out = 7'b0110000;
            4'h4: out = 7'b0011001;
            4'h5: out = 7'b0010010;
            4'h6: out = 7'b0000010;
            4'h7: out = 7'b1111000;
            4'h8: out = 7'b0000000;
            4'h9: out = 7'b0010000;
            4'hA: out = 7'b0001000;
            4'hB: out = 7'b0000011;
            4'hC: out = 7'b1000110;
            4'hD: out = 7'b0100001;
            4'hE: out = 7'b0000110;
            4'hF: out = 7'b0001110;
            default: out = 7'b1111111;
        endcase
    end
endmodule
