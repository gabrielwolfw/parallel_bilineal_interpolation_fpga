`timescale 1ns / 1ps
//==============================================================================
// Testbench para VJTAG Interface
// Verifica operaciones JTAG: BYPASS, WRITE, READ, SET_ADDR
//==============================================================================

module tb_vjtag_interface;

    // Parámetros
    parameter CLK_PERIOD = 10; // 100 MHz
    parameter DW = 8;
    parameter AW = 16;
    
    // Señales del DUT
    logic              tck;
    logic              tdi;
    logic              aclr;
    logic [1:0]        ir_in;
    logic              v_cdr;
    logic              v_sdr;
    logic              udr;
    logic [DW-1:0]     data_out;
    logic [DW-1:0]     data_in;
    logic [AW-1:0]     addr_out;
    logic              tdo;
    logic [DW-1:0]     debug_dr2;
    logic [DW-1:0]     debug_dr1;
    
    // Estados IR
    typedef enum logic [1:0] {
        BYPASS      = 2'b00,
        WRITE       = 2'b01,
        READ        = 2'b10,
        SET_ADDR    = 2'b11
    } ir_state_t;
    
    // Control de pruebas
    integer test_count = 0;
    integer pass_count = 0;
    integer fail_count = 0;
    
    //==========================================================================
    // Instancia del DUT
    //==========================================================================
    vjtag_interface #(
        .DW(DW),
        .AW(AW)
    ) dut (
        .tck(tck),
        .tdi(tdi),
        .aclr(aclr),
        .ir_in(ir_in),
        .v_cdr(v_cdr),
        .v_sdr(v_sdr),
        .udr(udr),
        .data_out(data_out),
        .data_in(data_in),
        .addr_out(addr_out),
        .tdo(tdo),
        .debug_dr2(debug_dr2),
        .debug_dr1(debug_dr1)
    );
    
    //==========================================================================
    // Generación de reloj
    //==========================================================================
    initial begin
        tck = 0;
        forever #(CLK_PERIOD/2) tck = ~tck;
    end
    
    //==========================================================================
    // Task para verificar resultados
    //==========================================================================
    task check_result(input string test_name, input logic [31:0] expected, input logic [31:0] actual);
        test_count++;
        if (expected === actual) begin
            $display("[PASS] %s: Expected=0x%0h, Got=0x%0h", test_name, expected, actual);
            pass_count++;
        end else begin
            $display("[FAIL] %s: Expected=0x%0h, Got=0x%0h", test_name, expected, actual);
            fail_count++;
        end
    endtask
    
    //==========================================================================
    // Task para simular operación JTAG WRITE
    //==========================================================================
    task jtag_write(input [DW-1:0] write_data);
        integer i;
        
        // Cambiar a estado WRITE
        ir_in = WRITE;
        @(posedge tck);
        
        // Shift-DR: Enviar datos bit por bit (LSB primero)
        v_sdr = 1'b1;
        for (i = 0; i < DW; i = i + 1) begin
            tdi = write_data[i];
            @(posedge tck);
        end
        v_sdr = 1'b0;
        
        // Update-DR: Transferir DR1 a data_out
        @(posedge tck);
        udr = 1'b1;
        @(posedge tck);
        udr = 1'b0;
        @(posedge tck);
    endtask
    
    //==========================================================================
    // Task para simular operación JTAG READ
    //==========================================================================
    task jtag_read(output [DW-1:0] read_data);
        integer i;
        
        // Cambiar a estado READ
        ir_in = READ;
        @(posedge tck);
        
        // Capture-DR: Capturar data_in en DR2
        v_cdr = 1'b1;
        @(posedge tck);
        v_cdr = 1'b0;
        
        // Shift-DR: Leer datos bit por bit desde TDO (LSB primero)
        v_sdr = 1'b1;
        for (i = 0; i < DW; i = i + 1) begin
            @(posedge tck);
            read_data[i] = tdo;
        end
        v_sdr = 1'b0;
        @(posedge tck);
    endtask
    
    //==========================================================================
    // Task para simular operación JTAG SET_ADDR
    //==========================================================================
    task jtag_set_addr(input [AW-1:0] address);
        integer i;
        
        // Cambiar a estado SET_ADDR
        ir_in = SET_ADDR;
        @(posedge tck);
        
        // Shift-DR: Enviar dirección bit por bit (LSB primero)
        v_sdr = 1'b1;
        for (i = 0; i < AW; i = i + 1) begin
            tdi = address[i];
            @(posedge tck);
        end
        v_sdr = 1'b0;
        
        // Update-DR: Transferir DR_ADDR a addr_out
        @(posedge tck);
        udr = 1'b1;
        @(posedge tck);
        udr = 1'b0;
        @(posedge tck);
    endtask
    
    //==========================================================================
    // Task para simular operación JTAG BYPASS
    //==========================================================================
    task jtag_bypass();
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
        check_result("BYPASS TDO", 1'b1, tdo);
        v_sdr = 1'b0;
        @(posedge tck);
    endtask
    
    //==========================================================================
    // Proceso de pruebas
    //==========================================================================
    initial begin
        // Inicialización
        $display("================================================================================");
        $display("  Testbench VJTAG Interface");
        $display("================================================================================");
        $display("Parámetros: DW=%0d, AW=%0d", DW, AW);
        $display("Tiempo: %0t", $time);
        $display("");
        
        // Valores iniciales
        aclr = 1'b0;
        tdi = 1'b0;
        ir_in = BYPASS;
        v_cdr = 1'b0;
        v_sdr = 1'b0;
        udr = 1'b0;
        data_in = '0;
        
        // Reset asíncrono
        #5;
        aclr = 1'b1;
        repeat(3) @(posedge tck);
        
        //----------------------------------------------------------------------
        // TEST 1: Reset y estado inicial
        //----------------------------------------------------------------------
        $display("TEST 1: Reset y estado inicial");
        $display("--------------------------------------------------------------------------------");
        check_result("data_out después de reset", 8'h00, data_out);
        check_result("addr_out después de reset", 18'h00000, addr_out);
        $display("");
        
        //----------------------------------------------------------------------
        // TEST 2: Operación BYPASS
        //----------------------------------------------------------------------
        $display("TEST 2: Operación BYPASS");
        $display("--------------------------------------------------------------------------------");
        jtag_bypass();
        $display("");
        
        //----------------------------------------------------------------------
        // TEST 3: Operación SET_ADDR
        //----------------------------------------------------------------------
        $display("TEST 3: Operación SET_ADDR");
        $display("--------------------------------------------------------------------------------");
        jtag_set_addr(16'h12345);
        check_result("SET_ADDR 0x1234", 16'h12345, addr_out);
        
        jtag_set_addr(16'h00000);
        check_result("SET_ADDR 0x00000", 16'h00000, addr_out);
        
        jtag_set_addr(16'hFFFFF);
        check_result("SET_ADDR 0xFFFF", 16'hFFFFF, addr_out);
        $display("");
        
        //----------------------------------------------------------------------
        // TEST 4: Operación WRITE
        //----------------------------------------------------------------------
        $display("TEST 4: Operación WRITE");
        $display("--------------------------------------------------------------------------------");
        jtag_write(8'hAA);
        check_result("WRITE 0xAA", 8'hAA, data_out);
        check_result("DR1 debug", 8'hAA, debug_dr1);
        
        jtag_write(8'h55);
        check_result("WRITE 0x55", 8'h55, data_out);
        
        jtag_write(8'hFF);
        check_result("WRITE 0xFF", 8'hFF, data_out);
        
        jtag_write(8'h00);
        check_result("WRITE 0x00", 8'h00, data_out);
        $display("");
        
        //----------------------------------------------------------------------
        // TEST 5: Operación READ
        //----------------------------------------------------------------------
        $display("TEST 5: Operación READ");
        $display("--------------------------------------------------------------------------------");
        
        data_in = 8'hCC;
        begin
            logic [DW-1:0] read_val;
            jtag_read(read_val);
            check_result("READ 0xCC", 8'hCC, read_val);
            check_result("DR2 debug", 8'hCC, debug_dr2);
        end
        
        data_in = 8'h33;
        begin
            logic [DW-1:0] read_val;
            jtag_read(read_val);
            check_result("READ 0x33", 8'h33, read_val);
        end
        $display("");
        
        //----------------------------------------------------------------------
        // TEST 6: Secuencia completa SET_ADDR → WRITE → READ
        //----------------------------------------------------------------------
        $display("TEST 6: Secuencia completa SET_ADDR → WRITE → READ");
        $display("--------------------------------------------------------------------------------");
        
        jtag_set_addr(16'h00100);
        check_result("ADDR set to 0x00100", 16'h00100, addr_out);
        
        jtag_write(8'hBE);
        check_result("WRITE 0xBE to addr", 8'hBE, data_out);
        
        data_in = 8'hEF;
        begin
            logic [DW-1:0] read_val;
            jtag_read(read_val);
            check_result("READ 0xEF from data_in", 8'hEF, read_val);
        end
        $display("");
        
        //----------------------------------------------------------------------
        // TEST 7: Múltiples escrituras consecutivas
        //----------------------------------------------------------------------
        $display("TEST 7: Múltiples escrituras consecutivas");
        $display("--------------------------------------------------------------------------------");
        
        begin : write_seq_test
            int i;
            for (i = 0; i < 8; i = i + 1) begin
                jtag_write(8'(i * 17)); // 0x00, 0x11, 0x22, ...
                check_result($sformatf("WRITE seq %0d", i), 8'(i * 17), data_out);
            end
        end
        $display("");
        
        //----------------------------------------------------------------------
        // TEST 8: Test de reset durante operación
        //----------------------------------------------------------------------
        $display("TEST 8: Reset durante operación");
        $display("--------------------------------------------------------------------------------");
        
        jtag_write(8'hAA);
        jtag_set_addr(16'h12345);
        
        // Aplicar reset
        @(posedge tck);
        aclr = 1'b0;
        @(posedge tck);
        @(posedge tck);
        aclr = 1'b1;
        @(posedge tck);
        
        check_result("data_out después de reset", 8'h00, data_out);
        check_result("addr_out después de reset", 16'h00000, addr_out);
        $display("");
        
        //----------------------------------------------------------------------
        // Resumen final
        //----------------------------------------------------------------------
        $display("================================================================================");
        $display("  RESUMEN DE PRUEBAS - VJTAG Interface Testbench");
        $display("================================================================================");
        $display("Total de pruebas: %0d", test_count);
        $display("Pruebas exitosas: %0d", pass_count);
        $display("Pruebas fallidas: %0d", fail_count);
        $display("Tasa de éxito:    %.1f%%", (pass_count * 100.0) / test_count);
        $display("================================================================================");
        
        if (fail_count == 0) begin
            $display("*** TODAS LAS PRUEBAS PASARON ***");
        end else begin
            $display("*** ALGUNAS PRUEBAS FALLARON ***");
        end
        $display("");
        
        // Finalizar simulación
        #100;
        $finish;
    end
    
    //==========================================================================
    // Timeout de seguridad
    //==========================================================================
    initial begin
        #100000; // 100 us timeout
        $display("[ERROR] Timeout de simulación alcanzado");
        $finish;
    end

endmodule
