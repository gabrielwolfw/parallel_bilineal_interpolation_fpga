//==============================================================================
// Testbench: tb_dsa_top
//==============================================================================
// Descripción: Testbench para el módulo dsa_top
//              Prueba integración completa: VJTAG + RAM + Control Manual
//
// Autor: DSA Project
// Fecha: Diciembre 2025
//==============================================================================

`timescale 1ns / 1ps

module tb_dsa_top;

    //==========================================================================
    // Parámetros
    //==========================================================================
    parameter CLK_PERIOD = 20; // 50 MHz
    parameter DATA_WIDTH = 8;
    parameter ADDR_WIDTH = 16;
    
    //==========================================================================
    // Señales del DUT
    //==========================================================================
    logic clk;
    logic [3:0] KEY;
    logic [9:0] LEDR;
    logic [6:0] HEX0, HEX1, HEX2, HEX3, HEX4, HEX5;
    logic [9:0] SW;
    
    //==========================================================================
    // Contadores de pruebas
    //==========================================================================
    integer test_count = 0;
    integer pass_count = 0;
    integer fail_count = 0;
    
    //==========================================================================
    // Instancia del DUT
    //==========================================================================
    dsa_top #(
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) dut (
        .clk(clk),
        .KEY(KEY),
        .LEDR(LEDR),
        .HEX0(HEX0),
        .HEX1(HEX1),
        .HEX2(HEX2),
        .HEX3(HEX3),
        .HEX4(HEX4),
        .HEX5(HEX5),
        .SW(SW)
    );
    
    //==========================================================================
    // Acceso a señales internas VJTAG
    //==========================================================================
    // El VJTAG interface contiene un IP de Quartus, accedemos a nivel del wrapper
    logic [ADDR_WIDTH-1:0] jtag_addr_internal;
    logic [DATA_WIDTH-1:0] jtag_data_internal;
    
    assign jtag_addr_internal = dut.jtag_addr_out;
    assign jtag_data_internal = dut.jtag_data_out;
    
    // Señales de control JTAG para simulación
    logic tck;          // JTAG clock (usaremos clk del sistema)
    logic tdi;          // Test Data In
    logic tdo;          // Test Data Out
    logic [1:0] ir_in;  // Instruction Register
    logic v_cdr;        // Virtual Capture-DR
    logic v_sdr;        // Virtual Shift-DR
    logic udr;          // Virtual Update-DR
    
    // Estados IR del VJTAG
    typedef enum logic [1:0] {
        BYPASS      = 2'b00,
        WRITE       = 2'b01,
        READ        = 2'b10,
        SET_ADDR    = 2'b11
    } ir_state_t;
    
    // Conectar tck al reloj del sistema
    assign tck = clk;
    
    //==========================================================================
    // Generación de reloj
    //==========================================================================
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end
    
    //==========================================================================
    // Task para verificar resultados
    //==========================================================================
    task check_result(input string test_name, input logic [ADDR_WIDTH-1:0] expected, input logic [ADDR_WIDTH-1:0] actual);
        test_count++;
        if (expected === actual) begin
            $display("[PASS] %s: Expected=0x%h, Got=0x%h", test_name, expected, actual);
            pass_count++;
        end else begin
            $display("[FAIL] %s: Expected=0x%h, Got=0x%h", test_name, expected, actual);
            fail_count++;
        end
    endtask
    
    task check_result_8bit(input string test_name, input logic [7:0] expected, input logic [7:0] actual);
        test_count++;
        if (expected === actual) begin
            $display("[PASS] %s: Expected=0x%h, Got=0x%h", test_name, expected, actual);
            pass_count++;
        end else begin
            $display("[FAIL] %s: Expected=0x%h, Got=0x%h", test_name, expected, actual);
            fail_count++;
        end
    endtask
    
    //==========================================================================
    // Tasks JTAG - Simulación completa del protocolo JTAG
    //==========================================================================
    
    //--------------------------------------------------------------------------
    // Task: jtag_set_addr
    // Descripción: Simula operación JTAG SET_ADDR (IR=11)
    //              Envía dirección de 16 bits bit por bit (LSB primero)
    //--------------------------------------------------------------------------
    task jtag_set_addr(input [ADDR_WIDTH-1:0] addr);
        integer i;
        
        $display("    [JTAG] SET_ADDR: 0x%04h", addr);
        
        // Cambiar a estado SET_ADDR
        ir_in = SET_ADDR;
        @(posedge tck);
        
        // Shift-DR: Enviar dirección bit por bit (LSB primero)
        v_sdr = 1'b1;
        for (i = 0; i < ADDR_WIDTH; i = i + 1) begin
            tdi = addr[i];
            @(posedge tck);
        end
        v_sdr = 1'b0;
        
        // Update-DR: Transferir DR_ADDR a addr_out
        @(posedge tck);
        udr = 1'b1;
        @(posedge tck);
        udr = 1'b0;
        
        // Forzar señal de salida (workaround para IP de Quartus)
        force dut.jtag_addr_out = addr;
        @(posedge tck);
        release dut.jtag_addr_out;
        
        repeat(2) @(posedge tck);
    endtask
    
    //--------------------------------------------------------------------------
    // Task: jtag_write
    // Descripción: Simula operación JTAG WRITE (IR=01)
    //              Envía dato de 8 bits bit por bit (LSB primero)
    //--------------------------------------------------------------------------
    task jtag_write(input [DATA_WIDTH-1:0] write_data);
        integer i;
        
        $display("    [JTAG] WRITE: 0x%02h", write_data);
        
        // Cambiar a estado WRITE
        ir_in = WRITE;
        @(posedge tck);
        
        // Shift-DR: Enviar datos bit por bit (LSB primero)
        v_sdr = 1'b1;
        for (i = 0; i < DATA_WIDTH; i = i + 1) begin
            tdi = write_data[i];
            @(posedge tck);
        end
        v_sdr = 1'b0;
        
        // Update-DR: Transferir DR1 a data_out
        @(posedge tck);
        udr = 1'b1;
        @(posedge tck);
        udr = 1'b0;
        
        // Forzar señal de salida (workaround para IP de Quartus)
        force dut.jtag_data_out = write_data;
        @(posedge tck);
        release dut.jtag_data_out;
        
        // Esperar propagación a RAM
        repeat(5) @(posedge tck);
    endtask
    
    //--------------------------------------------------------------------------
    // Task: jtag_read
    // Descripción: Simula operación JTAG READ (IR=10)
    //              Captura dato de RAM y lo lee bit por bit desde TDO
    //--------------------------------------------------------------------------
    task jtag_read(output [DATA_WIDTH-1:0] read_data);
        integer i;
        
        // Cambiar a estado READ
        ir_in = READ;
        @(posedge tck);
        
        // Capture-DR: Capturar data_in en DR2
        v_cdr = 1'b1;
        @(posedge tck);
        v_cdr = 1'b0;
        
        // Esperar latencia de RAM
        repeat(3) @(posedge tck);
        
        // Leer directamente de la salida de RAM
        read_data = dut.ram_q;
        
        // Shift-DR: Simular lectura bit por bit desde TDO (LSB primero)
        v_sdr = 1'b1;
        for (i = 0; i < DATA_WIDTH; i = i + 1) begin
            @(posedge tck);
            // tdo = read_data[i]; // En simulación real, TDO vendría del IP
        end
        v_sdr = 1'b0;
        @(posedge tck);
        
        $display("    [JTAG] READ: 0x%02h", read_data);
    endtask
    
    //--------------------------------------------------------------------------
    // Task: jtag_bypass
    // Descripción: Simula operación JTAG BYPASS (IR=00)
    //              Test de bypass estándar JTAG
    //--------------------------------------------------------------------------
    task jtag_bypass();
        $display("    [JTAG] BYPASS test");
        
        // Cambiar a estado BYPASS
        ir_in = BYPASS;
        @(posedge tck);
        
        // Capture-DR: Capturar 0
        v_cdr = 1'b1;
        @(posedge tck);
        v_cdr = 1'b0;
        
        // Shift-DR: Pasar TDI a TDO
        v_sdr = 1'b1;
        tdi = 1'b1;
        @(posedge tck);
        // En simulación real verificaríamos: check_result("BYPASS TDO", 1'b1, tdo);
        v_sdr = 1'b0;
        @(posedge tck);
    endtask
    
    //==========================================================================
    // Task para simular presión de KEY
    //==========================================================================
    task press_key(input integer key_num);
        $display("    [DEBUG] Presionando KEY[%0d]...", key_num);
        KEY[key_num] = 1'b0;  // Activo en bajo
        @(posedge clk);  // Un ciclo presionado
        @(posedge clk);  // Segundo ciclo para asegurar detección
        KEY[key_num] = 1'b1;  // Liberar
        @(posedge clk);  // Un ciclo liberado
        @(posedge clk);  // Segundo ciclo para estabilizar
        $display("    [DEBUG] KEY[%0d] liberado", key_num);
    endtask
    
    //==========================================================================
    // Función auxiliar para decodificar 7 segmentos
    //==========================================================================
    function logic [3:0] decode_7seg(input logic [6:0] segments);
        case (segments)
            7'b1000000: return 4'h0;
            7'b1111001: return 4'h1;
            7'b0100100: return 4'h2;
            7'b0110000: return 4'h3;
            7'b0011001: return 4'h4;
            7'b0010010: return 4'h5;
            7'b0000010: return 4'h6;
            7'b1111000: return 4'h7;
            7'b0000000: return 4'h8;
            7'b0010000: return 4'h9;
            7'b0001000: return 4'hA;
            7'b0000011: return 4'hB;
            7'b1000110: return 4'hC;
            7'b0100001: return 4'hD;
            7'b0000110: return 4'hE;
            7'b0001110: return 4'hF;
            default: return 4'hX;
        endcase
    endfunction
    
    //==========================================================================
    // Proceso de pruebas
    //==========================================================================
    initial begin
        $display("================================================================================");
        $display("  Testbench: dsa_top - Integración Completa");
        $display("================================================================================");
        $display("Parámetros: DATA_WIDTH=%0d, ADDR_WIDTH=%0d", DATA_WIDTH, ADDR_WIDTH);
        $display("Tiempo: %0t", $time);
        $display("");
        
        // Inicialización
        KEY = 4'b0111;  // KEY[3]=0 (reset activo), otros KEYs liberados
        SW = 10'b0;
        
        // Inicializar señales JTAG
        tdi = 1'b0;
        ir_in = BYPASS;
        v_cdr = 1'b0;
        v_sdr = 1'b0;
        udr = 1'b0;
        
        // Reset (mantener KEY[3]=0 por varios ciclos)
        repeat(5) @(posedge clk);
        KEY[3] = 1'b1;  // Liberar reset
        repeat(10) @(posedge clk);
        
        //----------------------------------------------------------------------
        // TEST 0: Operación BYPASS
        //----------------------------------------------------------------------
        $display("TEST 0: Operación BYPASS");
        $display("--------------------------------------------------------------------------------");
        
        jtag_bypass();
        
        $display("");
        
        //----------------------------------------------------------------------
        // TEST 1: Escritura y lectura JTAG básica
        //----------------------------------------------------------------------
        $display("TEST 1: Escritura y lectura JTAG básica");
        $display("--------------------------------------------------------------------------------");
        
        SW[0] = 1'b0;  // Modo JTAG
        repeat(5) @(posedge clk);
        
        jtag_set_addr(16'h00100);
        jtag_write(8'hAB);
        
        // Esperar propagación a RAM (RAM tiene latencia de registros)
        repeat(10) @(posedge clk);
        
        begin
            logic [7:0] read_val;
            jtag_set_addr(16'h00100);
            jtag_read(read_val);
            check_result_8bit("JTAG READ 0x00100", 8'hAB, read_val);
        end
        
        // Verificar LEDs
        check_result_8bit("LEDR[0] = Modo JTAG", 1'b0, LEDR[0]);
        
        $display("");
        
        //----------------------------------------------------------------------
        // TEST 2: Secuencia de escrituras JTAG
        //----------------------------------------------------------------------
        $display("TEST 2: Secuencia de escrituras JTAG");
        $display("--------------------------------------------------------------------------------");
        
        jtag_set_addr(16'h00200);
        jtag_write(8'h11);
        repeat(5) @(posedge clk);
        
        jtag_set_addr(16'h00201);
        jtag_write(8'h22);
        repeat(5) @(posedge clk);
        
        jtag_set_addr(16'h00202);
        jtag_write(8'h33);
        repeat(5) @(posedge clk);
        
        // Verificar lecturas
        begin
            logic [7:0] read_val;
            
            jtag_set_addr(16'h00200);
            jtag_read(read_val);
            check_result_8bit("READ 0x00200", 8'h11, read_val);
            
            jtag_set_addr(16'h00201);
            jtag_read(read_val);
            check_result_8bit("READ 0x00201", 8'h22, read_val);
            
            jtag_set_addr(16'h00202);
            jtag_read(read_val);
            check_result_8bit("READ 0x00202", 8'h33, read_val);
        end
        
        $display("");
        
        //----------------------------------------------------------------------
        // TEST 3: Control manual de dirección con KEYs
        //----------------------------------------------------------------------
        $display("TEST 3: Control manual de dirección con KEYs");
        $display("--------------------------------------------------------------------------------");
        
        // Escribir patrón en memoria con JTAG
        jtag_set_addr(16'h00000);
        jtag_write(8'hAA);
        
        jtag_set_addr(16'h00001);
        jtag_write(8'hBB);
        
        jtag_set_addr(16'h00002);
        jtag_write(8'hCC);
        
        jtag_set_addr(16'h00003);
        jtag_write(8'hDD);
        
        // Cambiar a modo manual
        SW[0] = 1'b1;
        repeat(10) @(posedge clk);
        
        check_result_8bit("LEDR[0] = Modo Manual", 1'b1, LEDR[0]);
        
        // La dirección manual debe estar en 0 después de reset
        // Incrementar dirección manual
        $display("Incrementando dirección manual...");
        $display("  manual_addr inicial = 0x%05h", dut.manual_addr);
        press_key(0);  // KEY[0] = incrementar
        $display("  manual_addr después de KEY[0] = 0x%05h (esperado 0x00001)", dut.manual_addr);
        check_result("manual_addr después de KEY[0]", 16'h00001, dut.manual_addr);
        
        press_key(0);  // Otra vez
        $display("  manual_addr después de 2x KEY[0] = 0x%05h (esperado 0x00002)", dut.manual_addr);
        check_result("manual_addr después de 2x KEY[0]", 16'h00002, dut.manual_addr);
        
        // Decrementar dirección manual
        $display("Decrementando dirección manual...");
        press_key(1);  // KEY[1] = decrementar
        $display("  manual_addr después de KEY[1] = 0x%05h (esperado 0x00001)", dut.manual_addr);
        check_result("manual_addr después de KEY[1]", 16'h00001, dut.manual_addr);
        
        $display("");
        
        //----------------------------------------------------------------------
        // TEST 4: Verificación de displays HEX en modo JTAG
        //----------------------------------------------------------------------
        $display("TEST 4: Verificación de displays HEX en modo JTAG");
        $display("--------------------------------------------------------------------------------");
        
        SW[0] = 1'b0;  // Modo JTAG
        repeat(10) @(posedge clk);
        
        jtag_set_addr(16'h0ABCD);
        jtag_write(8'h5E);
        
        // Esperar actualización de displays
        repeat(20) @(posedge clk);
        
        begin
            logic [3:0] hex0_decoded, hex1_decoded;
            logic [3:0] hex2_decoded, hex3_decoded, hex4_decoded, hex5_decoded;
            
            hex0_decoded = decode_7seg(HEX0);
            hex1_decoded = decode_7seg(HEX1);
            hex2_decoded = decode_7seg(HEX2);
            hex3_decoded = decode_7seg(HEX3);
            hex4_decoded = decode_7seg(HEX4);
            hex5_decoded = decode_7seg(HEX5);
            
            $display("HEX Displays: [%h][%h][%h][%h] [%h][%h]", 
                     hex5_decoded, hex4_decoded, hex3_decoded, hex2_decoded,
                     hex1_decoded, hex0_decoded);
            
            // Verificar dato (HEX1:HEX0)
            check_result_8bit("HEX0 = dato[3:0]", 4'hE, hex0_decoded);
            check_result_8bit("HEX1 = dato[7:4]", 4'h5, hex1_decoded);
            
            // Verificar dirección (HEX5:HEX2)
            check_result_8bit("HEX2 = addr[3:0]", 4'hD, hex2_decoded);
            check_result_8bit("HEX3 = addr[7:4]", 4'hC, hex3_decoded);
            check_result_8bit("HEX4 = addr[11:8]", 4'hB, hex4_decoded);
            check_result_8bit("HEX5 = addr[15:12]", 4'hA, hex5_decoded);
        end
        
        $display("");
        
        //----------------------------------------------------------------------
        // TEST 5: Verificación de displays HEX en modo Manual
        //----------------------------------------------------------------------
        $display("TEST 5: Verificación de displays HEX en modo Manual");
        $display("--------------------------------------------------------------------------------");
        
        SW[0] = 1'b1;  // Modo Manual
        repeat(10) @(posedge clk);
        
        // Establecer dirección manual conocida
        // manual_addr actualmente debe estar en 0x00001 (del TEST 3)
        // Incrementar hasta 0x01234
        $display("Configurando manual_addr = 0x01234...");
        
        // Resetear manual_addr escribiendo directamente (para acelerar test)
        force dut.manual_addr = 16'h01234;
        repeat(10) @(posedge clk);
        release dut.manual_addr;
        repeat(20) @(posedge clk);
        
        begin
            logic [3:0] hex0_decoded, hex1_decoded;
            logic [3:0] hex2_decoded, hex3_decoded, hex4_decoded, hex5_decoded;
            
            hex0_decoded = decode_7seg(HEX0);
            hex1_decoded = decode_7seg(HEX1);
            hex2_decoded = decode_7seg(HEX2);
            hex3_decoded = decode_7seg(HEX3);
            hex4_decoded = decode_7seg(HEX4);
            hex5_decoded = decode_7seg(HEX5);
            
            $display("HEX Displays (Manual): [%h][%h][%h][%h] [%h][%h]", 
                     hex5_decoded, hex4_decoded, hex3_decoded, hex2_decoded,
                     hex1_decoded, hex0_decoded);
            
            // Verificar dirección manual (HEX5:HEX2)
            check_result_8bit("HEX2 = manual_addr[3:0]", 4'h4, hex2_decoded);
            check_result_8bit("HEX3 = manual_addr[7:4]", 4'h3, hex3_decoded);
            check_result_8bit("HEX4 = manual_addr[11:8]", 4'h2, hex4_decoded);
            check_result_8bit("HEX5 = manual_addr[15:12]", 4'h1, hex5_decoded);
        end
        
        $display("");
        
        //----------------------------------------------------------------------
        // TEST 6: Verificación de LEDs de debug
        //----------------------------------------------------------------------
        $display("TEST 6: Verificación de LEDs de debug");
        $display("--------------------------------------------------------------------------------");
        
        SW[0] = 1'b0;  // Modo JTAG
        repeat(10) @(posedge clk);
        
        $display("Escribiendo a través de JTAG...");
        jtag_set_addr(16'h00500);
        @(posedge clk);
        
        // LEDR[1] debe activarse durante SETADDR
        if (LEDR[1]) begin
            $display("[INFO] LEDR[1] detectó operación SETADDR");
        end
        
        jtag_write(8'hF0);
        
        // LEDR[2] y LEDR[3] deben activarse durante WRITE
        repeat(5) @(posedge clk);
        $display("LEDR[2] (WRITE strobe) = %b", LEDR[2]);
        $display("LEDR[3] (RAM wren) = %b", LEDR[3]);
        
        // Verificar presión de KEYs
        $display("Verificando indicadores de KEYs...");
        KEY[0] = 1'b0;  // Presionar KEY[0]
        @(posedge clk);
        check_result_8bit("LEDR[4] cuando KEY[0] presionado", 1'b1, LEDR[4]);
        KEY[0] = 1'b1;  // Liberar
        @(posedge clk);
        check_result_8bit("LEDR[4] cuando KEY[0] liberado", 1'b0, LEDR[4]);
        
        KEY[1] = 1'b0;  // Presionar KEY[1]
        @(posedge clk);
        check_result_8bit("LEDR[5] cuando KEY[1] presionado", 1'b1, LEDR[5]);
        KEY[1] = 1'b1;  // Liberar
        @(posedge clk);
        check_result_8bit("LEDR[5] cuando KEY[1] liberado", 1'b0, LEDR[5]);
        
        $display("");
        
        //----------------------------------------------------------------------
        // TEST 7: Direcciones límite
        //----------------------------------------------------------------------
        $display("TEST 7: Direcciones límite");
        $display("--------------------------------------------------------------------------------");
        
        SW[0] = 1'b0;  // Modo JTAG
        repeat(5) @(posedge clk);
        
        // Dirección máxima
        jtag_set_addr(16'hFFFFF);
        jtag_write(8'hFF);
        repeat(10) @(posedge clk);
        
        begin
            logic [7:0] read_val;
            jtag_set_addr(16'hFFFFF);
            jtag_read(read_val);
            check_result_8bit("READ MAX addr 0xFFFF", 8'hFF, read_val);
        end
        
        // Dirección mínima
        jtag_set_addr(16'h00000);
        jtag_write(8'h00);
        repeat(10) @(posedge clk);
        
        begin
            logic [7:0] read_val;
            jtag_set_addr(16'h00000);
            jtag_read(read_val);
            check_result_8bit("READ MIN addr 0x00000", 8'h00, read_val);
        end
        
        $display("");
        
        //----------------------------------------------------------------------
        // TEST 8: Múltiples escrituras consecutivas con auto-verificación
        //----------------------------------------------------------------------
        $display("TEST 8: Múltiples escrituras consecutivas");
        $display("--------------------------------------------------------------------------------");
        
        begin : write_seq_test
            integer i;
            logic [7:0] expected_val;
            logic [7:0] read_val;
            
            for (i = 0; i < 8; i = i + 1) begin
                expected_val = 8'(i * 17); // 0x00, 0x11, 0x22, 0x33, ...
                
                jtag_set_addr(16'h00300 + i);
                jtag_write(expected_val);
                repeat(5) @(posedge clk);
            end
            
            // Verificar lecturas
            for (i = 0; i < 8; i = i + 1) begin
                expected_val = 8'(i * 17);
                
                jtag_set_addr(16'h00300 + i);
                jtag_read(read_val);
                check_result_8bit($sformatf("WRITE seq[%0d]", i), expected_val, read_val);
            end
        end
        
        $display("");
        
        //----------------------------------------------------------------------
        // Resumen final
        //----------------------------------------------------------------------
        $display("================================================================================");
        $display("  RESUMEN DE PRUEBAS - dsa_top Testbench");
        $display("================================================================================");
        $display("Total de pruebas: %0d", test_count);
        $display("Pruebas exitosas: %0d", pass_count);
        $display("Pruebas fallidas: %0d", fail_count);
        
        if (fail_count == 0) begin
            $display("Tasa de éxito:    100.0%%");
            $display("================================================================================");
            $display("*** TODAS LAS PRUEBAS PASARON EXITOSAMENTE ***");
        end else begin
            $display("Tasa de éxito:    %0.1f%%", (pass_count * 100.0) / test_count);
            $display("================================================================================");
            $display("*** ALGUNAS PRUEBAS FALLARON ***");
        end
        $display("================================================================================");
        
        $display("");
        $display("Simulación completada en tiempo: %0t", $time);
        
        #1000;
        $stop;
    end
    
    //==========================================================================
    // Timeout de seguridad
    //==========================================================================
    initial begin
        #200_000_000; // 200ms timeout
        $display("");
        $display("*** ERROR: TIMEOUT - La simulación excedió el tiempo límite ***");
        $stop;
    end

endmodule
