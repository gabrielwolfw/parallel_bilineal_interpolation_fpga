//==============================================================================
// Module: dsa_top_integrated
//==============================================================================
// Descripción: Módulo top-level que integra:
//              - VJTAG Interface para debugging y control desde PC
//              - RAM dual-port 64KB para almacenamiento de imágenes
//              - DSA (Domain-Specific Architecture) para interpolación bilineal
//              - Control manual con KEYs y visualización con HEX displays
//
// Características:
//   - Memoria: 64KB RAM dual-port (16-bit addressing)
//   - VJTAG: Acceso a memoria desde PC para cargar imágenes
//   - DSA: Procesamiento de interpolación bilinear (modo secuencial)
//   - Control: SW[0] = modo (0=JTAG debug, 1=DSA processing)
//              SW[9:1] = scale factor (0-255)
//              KEY[0] = Start DSA processing
//              KEY[1] = Reset DSA
//
// Autor: DSA Project
// Fecha: Diciembre 2025
//==============================================================================

module dsa_top_integrated #(
    parameter int DATA_WIDTH = 8,     // Ancho de datos (8 bits)
    parameter int ADDR_WIDTH = 16,    // Ancho de dirección (16 bits - 64KB)
    parameter int IMG_WIDTH_MAX = 512,
    parameter int IMG_HEIGHT_MAX = 512
) (
    // Clock
    input  logic clk,
    
    // KEYs (DE1-SoC tiene 4 KEYs, activos en bajo)
    // KEY[3] = reset_n general
    // KEY[2] = reset DSA
    // KEY[1] = decrementar dirección manual
    // KEY[0] = incrementar dirección manual
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
    // SW[1] = start DSA (activar procesamiento)
    // SW[9:2] = scale factor (0-255, formato Q8.8 dividido por 256)
    //           Ejemplo: SW[9:2]=192 → factor=0.75 (192/256)
    input  logic [9:0] SW
);

    //==========================================================================
    // Señales de Reset y Control
    //==========================================================================
    logic reset_n;          // Reset general (activo bajo)
    logic dsa_reset;        // Reset DSA (activo alto)
    logic dsa_start;        // Start DSA (pulso)
    
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
    assign dsa_start = SW[1];  // SW[1] activa procesamiento continuo
    
    //==========================================================================
    // Control Manual de Dirección con KEYs
    //==========================================================================
    // KEY[0]: Incrementar dirección manual
    // KEY[1]: Decrementar dirección manual
    // KEYs son activos en bajo (presionado = 0)
    
    logic [ADDR_WIDTH-1:0] manual_addr;    // Dirección manual controlada por KEYs
    
    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            manual_addr <= '0;
        end else begin
            // KEY[0]: Incrementar (detectar flanco descendente)
            if (!KEY[0] && key_prev[0])
                manual_addr <= manual_addr + 1'b1;
            
            // KEY[1]: Decrementar (detectar flanco descendente)
            if (!KEY[1] && key_prev[1] && manual_addr != 0)
                manual_addr <= manual_addr - 1'b1;
        end
    end
    
    //==========================================================================
    // Configuración DSA
    //==========================================================================
    logic [15:0] img_width_in;
    logic [15:0] img_height_in;
    logic [7:0]  scale_factor;
    logic        display_mode;       // 0=JTAG, 1=Manual
    logic        dsa_enable;
    
    // Configuración fija para pruebas (puede hacerse configurable vía VJTAG)
    assign img_width_in = 16'd256;   // Imagen de entrada 256x256
    assign img_height_in = 16'd256;
    assign scale_factor = SW[9:2];   // SW[9:2] como 8 bits de factor de escala (0-255)
    assign display_mode = SW[0];     // SW[0]: 0=mostrar JTAG, 1=mostrar Manual
    assign dsa_enable = SW[1] && dsa_start;  // SW[1] habilita DSA
    
    //==========================================================================
    // Señales VJTAG
    //==========================================================================
    logic [DATA_WIDTH-1:0] jtag_data_out;  // Datos de VJTAG a RAM (escritura)
    logic [DATA_WIDTH-1:0] jtag_data_in;   // Datos de RAM a VJTAG (lectura)
    logic [ADDR_WIDTH-1:0] jtag_addr_out;  // Dirección desde VJTAG
    
    //==========================================================================
    // Señales DSA
    //==========================================================================
    logic        dsa_busy;
    logic        dsa_ready;
    logic [15:0] dsa_progress;
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
    logic [ADDR_WIDTH-1:0] ram_wraddress;  // Dirección de escritura
    logic [ADDR_WIDTH-1:0] ram_rdaddress;  // Dirección de lectura
    logic [DATA_WIDTH-1:0] ram_data;       // Datos para escritura
    logic                  ram_wren;       // Write enable
    logic [DATA_WIDTH-1:0] ram_q;          // Datos de lectura
    
    //==========================================================================
    // Arbitraje de memoria: VJTAG vs DSA
    //==========================================================================
    logic jtag_write_strobe;
    logic [DATA_WIDTH-1:0] jtag_data_out_prev;
    
    // Detectar escritura VJTAG (cambio en data_out)
    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            jtag_data_out_prev <= '0;
            jtag_write_strobe <= 1'b0;
        end else begin
            jtag_data_out_prev <= jtag_data_out;
            jtag_write_strobe <= (jtag_data_out != jtag_data_out_prev);
        end
    end
    
    // Cálculo de direcciones DSA
    logic [31:0] dsa_write_addr_full;
    logic [31:0] dsa_read_addr_full;
    logic [ADDR_WIDTH-1:0] dsa_write_addr;
    logic [ADDR_WIDTH-1:0] dsa_read_addr;
    
    // Calcular dimensiones de salida
    logic [15:0] img_width_out;
    logic [15:0] img_height_out;
    
    assign img_width_out = (({16'd0, img_width_in} * {24'd0, scale_factor}) >> 8);
    assign img_height_out = (({16'd0, img_height_in} * {24'd0, scale_factor}) >> 8);
    
    // Dirección base de salida: segunda mitad de memoria (32KB)
    parameter logic [ADDR_WIDTH-1:0] OUTPUT_BASE = 16'h8000;  // 32KB offset
    
    assign dsa_write_addr_full = OUTPUT_BASE + 
                                 ({16'd0, dsa_current_y} * {16'd0, img_width_out}) + 
                                 {16'd0, dsa_current_x};
    assign dsa_write_addr = dsa_write_addr_full[ADDR_WIDTH-1:0];
    
    // Dirección de lectura del fetch module (imagen de entrada en primera mitad)
    logic [ADDR_WIDTH-1:0] fetch_mem_addr;
    logic                  fetch_mem_read_en;
    
    // Multiplexor de RAM basado en modo DSA activo
    always_comb begin
        if (dsa_enable && dsa_busy) begin
            // Modo DSA activo: Fetch lee, datapath escribe
            ram_rdaddress = fetch_mem_addr;
            ram_wraddress = dsa_write_addr;
            ram_data = dp_pixel_out;
            ram_wren = dsa_write_enable;
        end else begin
            // Modo JTAG/Manual: Acceso desde PC o lectura manual
            ram_rdaddress = display_mode ? manual_addr : jtag_addr_out;
            ram_wraddress = jtag_addr_out;
            ram_data = jtag_data_out;
            ram_wren = jtag_write_strobe;
        end
    end
    
    assign jtag_data_in = ram_q;
    
    //==========================================================================
    // Cálculo de coordenadas fuente para interpolación (Q8.8)
    //==========================================================================
    logic [31:0] inv_scale_q8_8;
    logic [31:0] src_x_full, src_y_full;
    
    assign inv_scale_q8_8 = (scale_factor != 8'd0) ? 
                            (32'd65536 / {24'd0, scale_factor}) : 
                            32'd256;
    
    assign src_x_full = dsa_current_x * inv_scale_q8_8;
    assign src_y_full = dsa_current_y * inv_scale_q8_8;
    
    assign fetch_src_x_int = src_x_full[23:8];   // Parte entera
    assign fetch_src_y_int = src_y_full[23:8];
    assign fetch_frac_x = {src_x_full[7:0], 8'd0};  // Fracción en Q8.8
    assign fetch_frac_y = {src_y_full[7:0], 8'd0};
    
    //==========================================================================
    // Instancias de módulos
    //==========================================================================
    
    // VJTAG Interface
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
    
    // RAM dual-port (64KB)
    ram ram_inst (
        .clock(clk),
        .data(ram_data),
        .rdaddress(ram_rdaddress),
        .wraddress(ram_wraddress),
        .wren(ram_wren),
        .q(ram_q)
    );
    
    // FSM de control DSA (secuencial)
    dsa_control_fsm_sequential #(
        .IMG_WIDTH_MAX(IMG_WIDTH_MAX),
        .IMG_HEIGHT_MAX(IMG_HEIGHT_MAX)
    ) dsa_fsm (
        .clk(clk),
        .rst(dsa_reset || !reset_n),
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
    
    // Pixel Fetch (secuencial)
    dsa_pixel_fetch_sequential #(
        .ADDR_WIDTH(ADDR_WIDTH)
    ) dsa_fetch (
        .clk(clk),
        .rst(dsa_reset || !reset_n),
        .req_valid(fetch_req),
        .src_x_int(fetch_src_x_int),
        .src_y_int(fetch_src_y_int),
        .frac_x(fetch_frac_x),
        .frac_y(fetch_frac_y),
        .img_base_addr('0),  // Imagen de entrada en dirección 0
        .img_width(img_width_in),
        .img_height(img_height_in),
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
    
    // Datapath de interpolación
    dsa_datapath dsa_dp (
        .clk(clk),
        .rst(dsa_reset || !reset_n),
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
    // LEDR[0]: Modo visualización (0=JTAG, 1=Manual)
    // LEDR[1]: DSA enable (SW[1])
    // LEDR[2]: DSA ready
    // LEDR[3]: DSA busy
    // LEDR[4]: KEY[0] presionado (incrementar)
    // LEDR[5]: KEY[1] presionado (decrementar)
    // LEDR[6]: Write enable
    // LEDR[7]: Fetch busy
    // LEDR[9:8]: Estado superior
    
    assign dsa_progress = ({dsa_current_y, dsa_current_x} >> 8);
    
    assign LEDR[0] = display_mode;      // SW[0]
    assign LEDR[1] = dsa_enable;        // SW[1]
    assign LEDR[2] = dsa_ready;
    assign LEDR[3] = dsa_busy;
    assign LEDR[4] = ~KEY[0];           // LED ON cuando KEY presionado
    assign LEDR[5] = ~KEY[1];
    assign LEDR[6] = dsa_write_enable;
    assign LEDR[7] = fetch_busy;
    assign LEDR[9:8] = dsa_progress[1:0];
    
    //==========================================================================
    // HEX Displays
    //==========================================================================
    // SW[0] = 0: Modo "JTAG" - Muestra dirección JTAG y dato de RAM
    // SW[0] = 1: Modo "Manual" - Muestra dirección manual y dato de RAM
    
    logic [3:0] hex0_val, hex1_val, hex2_val, hex3_val, hex4_val, hex5_val;
    logic [ADDR_WIDTH-1:0] display_addr;
    logic [DATA_WIDTH-1:0] display_data;
    
    // Seleccionar qué mostrar según SW[0]
    always_comb begin
        if (display_mode) begin
            // Modo Manual: mostrar dirección manual y dato leído
            display_addr = manual_addr;
            display_data = ram_q;
        end else begin
            // Modo JTAG: mostrar dirección JTAG y dato leído
            display_addr = jtag_addr_out;
            display_data = ram_q;
        end
        
        // Asignar a displays: Dato (HEX1-HEX0) y Dirección (HEX5-HEX2)
        hex0_val = display_data[3:0];
        hex1_val = display_data[7:4];
        hex2_val = display_addr[3:0];
        hex3_val = display_addr[7:4];
        hex4_val = display_addr[11:8];
        hex5_val = display_addr[15:12];
    end
    
    // Decodificadores 7 segmentos
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
    // Segmentos: {g, f, e, d, c, b, a}
    // Activo en bajo (0 = encendido)
    always_comb begin
        case (in)
            4'h0: out = 7'b1000000; // 0
            4'h1: out = 7'b1111001; // 1
            4'h2: out = 7'b0100100; // 2
            4'h3: out = 7'b0110000; // 3
            4'h4: out = 7'b0011001; // 4
            4'h5: out = 7'b0010010; // 5
            4'h6: out = 7'b0000010; // 6
            4'h7: out = 7'b1111000; // 7
            4'h8: out = 7'b0000000; // 8
            4'h9: out = 7'b0010000; // 9
            4'hA: out = 7'b0001000; // A
            4'hB: out = 7'b0000011; // b
            4'hC: out = 7'b1000110; // C
            4'hD: out = 7'b0100001; // d
            4'hE: out = 7'b0000110; // E
            4'hF: out = 7'b0001110; // F
            default: out = 7'b1111111; // apagado
        endcase
    end
endmodule
