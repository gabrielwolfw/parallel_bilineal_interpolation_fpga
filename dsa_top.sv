//==============================================================================
// Module: dsa_top
//==============================================================================
// Descripción: Módulo top-level que integra VJTAG Interface y RAM
//              Permite acceso a memoria mediante JTAG para debugging
//
// Autor: DSA Project
// Fecha: Diciembre 2025
//==============================================================================

module dsa_top #(
    parameter int DATA_WIDTH = 8,    // Ancho de datos (8 bits)
    parameter int ADDR_WIDTH = 16    // Ancho de dirección (16 bits - 64KB)
) (
    // Clock
    input  logic clk,
    
    // KEYs (DE1-SoC tiene 4 KEYs, activos en bajo)
    // KEY[3] se usa como reset_n
    // KEY[0] = incrementar dirección manual
    // KEY[1] = decrementar dirección manual
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
    input  logic [9:0] SW
);

    //==========================================================================
    // Señales internas
    //==========================================================================
    
    // Reset interno conectado desde KEY[3]
    logic reset_n;
    assign reset_n = KEY[3];  // KEY[3] como reset (activo en bajo)
    
    // Señales VJTAG
    logic [DATA_WIDTH-1:0] jtag_data_out;  // Datos de VJTAG a RAM (escritura)
    logic [DATA_WIDTH-1:0] jtag_data_in;   // Datos de RAM a VJTAG (lectura)
    logic [ADDR_WIDTH-1:0] jtag_addr_out;  // Dirección desde VJTAG
    
    // Señales RAM (DUAL_PORT mode: separate read/write ports)
    logic [ADDR_WIDTH-1:0] ram_wraddress;  // Dirección de escritura
    logic [ADDR_WIDTH-1:0] ram_rdaddress;  // Dirección de lectura
    logic [DATA_WIDTH-1:0] ram_data;       // Datos para escritura
    logic                  ram_wren;       // Write enable
    logic [DATA_WIDTH-1:0] ram_q;          // Datos de lectura
    
    // Señales de control
    logic jtag_write_strobe;               // Pulso de escritura desde VJTAG
    logic jtag_read_strobe;                // Pulso de lectura desde VJTAG
    
    // Control manual de dirección
    logic [ADDR_WIDTH-1:0] manual_addr;    // Dirección manual controlada por KEYs
    logic [ADDR_WIDTH-1:0] display_addr;   // Dirección a mostrar en displays
    logic [DATA_WIDTH-1:0] display_data;   // Dato a mostrar en displays
    
    // Detección de flancos para KEYs (simple edge detection)
    logic [1:0] key_prev;  // Registro de estado previo de KEY[1:0]
    
    // Registros para detección de cambios
    logic [DATA_WIDTH-1:0] jtag_data_out_prev;
    logic [ADDR_WIDTH-1:0] jtag_addr_out_prev;
    
    // Registros para display
    logic [ADDR_WIDTH-1:0] last_addr;      // Última dirección accedida
    logic [DATA_WIDTH-1:0] last_data;      // Último dato accedido
    logic [ADDR_WIDTH-1:0] current_read_addr; // Dirección de lectura actual
    logic [DATA_WIDTH-1:0] current_read_data; // Dato leído actual
    
    //==========================================================================
    // Instancia VJTAG Interface
    //==========================================================================
    vjtag_interface #(
        .DW(DATA_WIDTH),
        .AW(ADDR_WIDTH)
    ) vjtag_inst (
        .tck(clk),
        .aclr(reset_n),
        .data_out(jtag_data_out),
        .data_in(jtag_data_in),
        .addr_out(jtag_addr_out),
        .debug_dr1(),  // No usado en top-level
        .debug_dr2()   // No usado en top-level
    );
    
    //==========================================================================
    // Instancia RAM (DUAL_PORT mode)
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
    // Control Manual de Dirección con KEYs
    //==========================================================================
    // KEY[0]: Incrementar dirección manual
    // KEY[1]: Decrementar dirección manual
    // KEYs son activos en bajo (presionado = 0)
    
    // Detección de flancos simple (edge detection)
    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            key_prev <= 2'b11;
            manual_addr <= '0;
        end else begin
            key_prev <= KEY[1:0];
            
            // KEY[0]: Incrementar (detectar flanco descendente)
            if (!KEY[0] && key_prev[0])
                manual_addr <= manual_addr + 1'b1;
            
            // KEY[1]: Decrementar (detectar flanco descendente)
            if (!KEY[1] && key_prev[1] && manual_addr != 0)
                manual_addr <= manual_addr - 1'b1;
        end
    end
    
    //==========================================================================
    // Lógica de Control: Detección de escritura/lectura JTAG
    //==========================================================================
    
    // Detectar cambio en data_out (indica operación WRITE desde JTAG)
    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            jtag_data_out_prev <= '0;
            jtag_write_strobe <= 1'b0;
        end else begin
            jtag_data_out_prev <= jtag_data_out;
            jtag_write_strobe <= (jtag_data_out != jtag_data_out_prev);
        end
    end
    
    // Detectar cambio en addr_out (indica operación SETADDR desde JTAG)
    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            jtag_addr_out_prev <= '0;
        end else begin
            jtag_addr_out_prev <= jtag_addr_out;
        end
    end
    
    //==========================================================================
    // Conexión RAM: Mapeo de señales JTAG a RAM
    //==========================================================================
    
    // La RAM siempre usa la dirección JTAG para lectura/escritura
    assign ram_wraddress = jtag_addr_out;
    assign ram_rdaddress = SW[0] ? manual_addr : jtag_addr_out; // Leer desde manual o JTAG
    assign ram_data = jtag_data_out;
    assign ram_wren = jtag_write_strobe;
    assign jtag_data_in = ram_q;
    
    //==========================================================================
    // Registros de debug: Capturar última operación
    //==========================================================================
    
    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            last_addr <= '0;
            last_data <= '0;
        end else begin
            if (jtag_write_strobe) begin
                last_addr <= jtag_addr_out;
                last_data <= jtag_data_out;
            end else if (jtag_addr_out != jtag_addr_out_prev) begin
                last_addr <= jtag_addr_out;
            end
        end
    end
    
    // Actualizar dirección y dato para display según SW[0]
    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            display_addr <= '0;
            display_data <= '0;
        end else begin
            if (SW[0]) begin
                // Modo Manual: mostrar dirección manual y dato leído
                display_addr <= manual_addr;
                display_data <= ram_q;
            end else begin
                // Modo JTAG: mostrar dirección JTAG y dato leído
                display_addr <= jtag_addr_out;
                display_data <= ram_q;
            end
        end
    end
    
    // Mantener compatibilidad con señales previas (no usadas ahora)
    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            current_read_addr <= '0;
            current_read_data <= '0;
        end else begin
            current_read_addr <= jtag_addr_out;
            current_read_data <= ram_q;
        end
    end
    
    //==========================================================================
    // LEDs de Debug
    //==========================================================================
    // LEDR[0]: Modo de visualización (0=JTAG, 1=Manual)
    // LEDR[1]: SETADDR operation (cambio de dirección JTAG)
    // LEDR[2]: WRITE operation (escritura a RAM)
    // LEDR[3]: RAM write enable activo
    // LEDR[4]: KEY[0] presionado (incrementar)
    // LEDR[5]: KEY[1] presionado (decrementar)
    // LEDR[9:6]: Bits superiores del dato mostrado
    
    assign LEDR[0] = SW[0];  // Indicador de modo
    assign LEDR[1] = (jtag_addr_out != jtag_addr_out_prev);
    assign LEDR[2] = jtag_write_strobe;
    assign LEDR[3] = ram_wren;
    assign LEDR[4] = ~KEY[0];  // LED encendido cuando KEY presionado
    assign LEDR[5] = ~KEY[1];
    assign LEDR[9:6] = display_data[7:4];
    
    //==========================================================================
    // HEX Displays
    //==========================================================================
    // SW[0] = 0: Modo "JTAG" - Muestra dirección JTAG y dato de RAM
    // SW[0] = 1: Modo "Manual" - Muestra dirección manual y dato de RAM
    
    logic [3:0] hex0_val, hex1_val, hex2_val, hex3_val, hex4_val, hex5_val;
    
    always_comb begin
        // Siempre mostrar display_addr y display_data
        // (que ya están seleccionados por SW[0] en el bloque always_ff anterior)
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
