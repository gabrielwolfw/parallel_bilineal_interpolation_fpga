`timescale 1ns / 1ps
//==============================================================================
// Testbench para RAM (Dual-Port Altsyncram)
// Verifica operaciones de escritura y lectura en puertos separados
//==============================================================================

module tb_ram;

    // Parámetros
    parameter CLK_PERIOD = 10; // 100 MHz
    parameter ADDR_WIDTH = 16;
    parameter DATA_WIDTH = 8;
    
    // Señales del DUT
    logic                      clock;
    logic [DATA_WIDTH-1:0]     data;
    logic [ADDR_WIDTH-1:0]     rdaddress;
    logic [ADDR_WIDTH-1:0]     wraddress;
    logic                      wren;
    wire  [DATA_WIDTH-1:0]     q;
    
    // Control de pruebas
    integer test_count = 0;
    integer pass_count = 0;
    integer fail_count = 0;
    
    //==========================================================================
    // Instancia del DUT
    //==========================================================================
    ram dut (
        .clock(clock),
        .data(data),
        .rdaddress(rdaddress),
        .wraddress(wraddress),
        .wren(wren),
        .q(q)
    );
    
    //==========================================================================
    // Generación de reloj
    //==========================================================================
    initial begin
        clock = 0;
        forever #(CLK_PERIOD/2) clock = ~clock;
    end
    
    //==========================================================================
    // Task para verificar resultados
    //==========================================================================
    task check_result(input string test_name, input [DATA_WIDTH-1:0] expected, input [DATA_WIDTH-1:0] actual);
        test_count++;
        if (expected === actual) begin
            $display("[PASS] %s: Expected=0x%02h, Got=0x%02h", test_name, expected, actual);
            pass_count++;
        end else begin
            $display("[FAIL] %s: Expected=0x%02h, Got=0x%02h", test_name, expected, actual);
            fail_count++;
        end
    endtask
    
    //==========================================================================
    // Task para escribir en RAM
    //==========================================================================
    task write_ram(input [ADDR_WIDTH-1:0] addr, input [DATA_WIDTH-1:0] value);
        @(posedge clock);
        wraddress = addr;
        data = value;
        wren = 1'b1;
        @(posedge clock);
        wren = 1'b0;
    endtask
    
    //==========================================================================
    // Task para leer de RAM
    //==========================================================================
    task read_ram(input [ADDR_WIDTH-1:0] addr, output [DATA_WIDTH-1:0] read_data);
        @(posedge clock);
        rdaddress = addr;
        @(posedge clock); // Esperar 1 ciclo (latencia de lectura)
        @(posedge clock); // Esperar otro ciclo por seguridad
        read_data = q;
    endtask
    
    //==========================================================================
    // Proceso de pruebas
    //==========================================================================
    initial begin
        // Inicialización
        $display("================================================================================");
        $display("  Testbench RAM - Dual Port Altsyncram");
        $display("================================================================================");
        $display("Tiempo: %0t", $time);
        $display("");
        
        // Valores iniciales
        data = '0;
        rdaddress = '0;
        wraddress = '0;
        wren = 1'b0;
        
        // Esperar estabilización
        repeat(5) @(posedge clock);
        
        //----------------------------------------------------------------------
        // TEST 1: Escritura y lectura básica
        //----------------------------------------------------------------------
        $display("TEST 1: Escritura y lectura básica");
        $display("--------------------------------------------------------------------------------");
        
        write_ram(16'h00000, 8'hAA);
        write_ram(16'h00001, 8'h55);
        write_ram(16'h00002, 8'hFF);
        write_ram(16'h00003, 8'h00);
        
        begin
            logic [DATA_WIDTH-1:0] read_val;
            
            read_ram(16'h00000, read_val);
            check_result("READ addr 0x00000", 8'hAA, read_val);
            
            read_ram(16'h00001, read_val);
            check_result("READ addr 0x00001", 8'h55, read_val);
            
            read_ram(16'h00002, read_val);
            check_result("READ addr 0x00002", 8'hFF, read_val);
            
            read_ram(16'h00003, read_val);
            check_result("READ addr 0x00003", 8'h00, read_val);
        end
        $display("");
        
        //----------------------------------------------------------------------
        // TEST 2: Sobrescritura de datos
        //----------------------------------------------------------------------
        $display("TEST 2: Sobrescritura de datos");
        $display("--------------------------------------------------------------------------------");
        
        write_ram(16'h00000, 8'h11);
        write_ram(16'h00001, 8'h22);
        
        begin
            logic [DATA_WIDTH-1:0] read_val;
            
            read_ram(16'h00000, read_val);
            check_result("OVERWRITE addr 0x00000", 8'h11, read_val);
            
            read_ram(16'h00001, read_val);
            check_result("OVERWRITE addr 0x00001", 8'h22, read_val);
        end
        $display("");
        
        //----------------------------------------------------------------------
        // TEST 3: Direcciones límite
        //----------------------------------------------------------------------
        $display("TEST 3: Direcciones límite (boundary test)");
        $display("--------------------------------------------------------------------------------");
        
        // RAM tiene 1,048,576 palabras (2^20), dirección máxima es 0xFFFF
        write_ram(16'hFFFFF, 8'hEE); // Dirección máxima (1,048,575)
        write_ram(16'hFFFF0, 8'hEF); // Cerca del máximo
        write_ram(16'h00000, 8'hDD); // Dirección mínima
        
        begin
            logic [DATA_WIDTH-1:0] read_val;
            
            read_ram(16'hFFFFF, read_val);
            check_result("READ addr 0xFFFF (MAX)", 8'hEE, read_val);
            
            read_ram(16'hFFFF0, read_val);
            check_result("READ addr 0xFFFF0 (NEAR_MAX)", 8'hEF, read_val);
            
            read_ram(16'h00000, read_val);
            check_result("READ addr 0x00000 (MIN)", 8'hDD, read_val);
        end
        $display("");
        
        //----------------------------------------------------------------------
        // TEST 4: Patrón secuencial
        //----------------------------------------------------------------------
        $display("TEST 4: Escritura/lectura de patrón secuencial");
        $display("--------------------------------------------------------------------------------");
        
        begin : pattern_test
            int i;
            for (i = 0; i < 16; i = i + 1) begin
                write_ram(16'h00100 + i[15:0], 8'(i * 16));
            end
            
            for (i = 0; i < 16; i = i + 1) begin
                logic [DATA_WIDTH-1:0] read_val;
                read_ram(16'h00100 + i[15:0], read_val);
                check_result($sformatf("PATTERN addr 0x%05h", 16'h00100 + i[15:0]), 8'(i * 16), read_val);
            end
        end
        $display("");
        
        //----------------------------------------------------------------------
        // TEST 5: Operaciones simultáneas (escritura y lectura)
        //----------------------------------------------------------------------
        $display("TEST 5: Escritura y lectura simultáneas");
        $display("--------------------------------------------------------------------------------");
        
        @(posedge clock);
        wraddress = 16'h00500;
        data = 8'hCC;
        wren = 1'b1;
        rdaddress = 16'h00100; // Leer de otra dirección mientras escribe
        
        @(posedge clock);
        wren = 1'b0;
        
        @(posedge clock);
        @(posedge clock);
        check_result("SIMULTANEOUS read 0x00100", 8'h00, q); // Debe leer el valor de 0x00100
        
        begin
            logic [DATA_WIDTH-1:0] read_val;
            read_ram(16'h00500, read_val);
            check_result("SIMULTANEOUS write->read 0x00500", 8'hCC, read_val);
        end
        $display("");
        
        //----------------------------------------------------------------------
        // Resumen final
        //----------------------------------------------------------------------
        $display("================================================================================");
        $display("  RESUMEN DE PRUEBAS - RAM Testbench");
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
