`timescale 1ns / 1ps
//==============================================================================
// Testbench Integrado: VJTAG Interface + RAM
// Simula operaciones JTAG para acceso a memoria:
// - SET_ADDR: Establece dirección de memoria
// - WRITE: Escribe datos en la dirección actual
// - READ: Lee datos de la dirección actual
//==============================================================================

module tb_vjtag_ram_integrated;

    // Parámetros
    parameter CLK_PERIOD = 10; // 100 MHz
    parameter DW = 8;
    parameter AW = 16;
    parameter RAM_ADDR_WIDTH = 16;
    
    // Señales VJTAG
    logic              tck;
    logic              tdi;
    logic              aclr;
    logic [1:0]        ir_in;
    logic              v_cdr;
    logic              v_sdr;
    logic              udr;
    logic [DW-1:0]     jtag_data_out;
    logic [DW-1:0]     jtag_data_in;
    logic [AW-1:0]     jtag_addr_out;
    logic              tdo;
    logic [DW-1:0]     debug_dr2;
    logic [DW-1:0]     debug_dr1;
    
    // Señales RAM
    logic                      ram_clock;
    logic [DW-1:0]             ram_data;
    logic [RAM_ADDR_WIDTH-1:0] ram_rdaddress;
    logic [RAM_ADDR_WIDTH-1:0] ram_wraddress;
    logic                      ram_wren;
    wire  [DW-1:0]             ram_q;
    
    // Señales de integración
    logic jtag_write_strobe;
    logic jtag_read_strobe;
    
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
    // Instancia VJTAG Interface
    //==========================================================================
    vjtag_interface #(
        .DW(DW),
        .AW(AW)
    ) vjtag_inst (
        .tck(tck),
        .tdi(tdi),
        .aclr(aclr),
        .ir_in(ir_in),
        .v_cdr(v_cdr),
        .v_sdr(v_sdr),
        .udr(udr),
        .data_out(jtag_data_out),
        .data_in(jtag_data_in),
        .addr_out(jtag_addr_out),
        .tdo(tdo),
        .debug_dr2(debug_dr2),
        .debug_dr1(debug_dr1)
    );
    
    //==========================================================================
    // Instancia RAM
    //==========================================================================
    ram ram_inst (
        .clock(ram_clock),
        .data(ram_data),
        .rdaddress(ram_rdaddress),
        .wraddress(ram_wraddress),
        .wren(ram_wren),
        .q(ram_q)
    );
    
    //==========================================================================
    // Lógica de integración VJTAG-RAM
    //==========================================================================
    
    // Usar el mismo reloj para JTAG y RAM
    assign ram_clock = tck;
    
    // Detectar pulso de escritura JTAG
    logic udr_prev;
    always_ff @(posedge tck or negedge aclr) begin
        if (~aclr) begin
            udr_prev <= 1'b0;
            jtag_write_strobe <= 1'b0;
        end else begin
            udr_prev <= udr;
            // Detectar flanco positivo de UDR cuando IR=WRITE
            jtag_write_strobe <= udr && ~udr_prev && (ir_in == WRITE);
        end
    end
    
    // Conectar dirección de JTAG a RAM (usar los 16 bits menos significativos)
    assign ram_wraddress = jtag_addr_out[RAM_ADDR_WIDTH-1:0];
    assign ram_rdaddress = jtag_addr_out[RAM_ADDR_WIDTH-1:0];
    
    // Conectar datos de escritura
    assign ram_data = jtag_data_out;
    
    // Habilitar escritura en RAM cuando hay strobe de JTAG
    assign ram_wren = jtag_write_strobe;
    
    // Conectar datos de lectura
    assign jtag_data_in = ram_q;
    
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
    // Task para simular operación JTAG SET_ADDR
    //==========================================================================
    task jtag_set_addr(input [AW-1:0] address);
        integer i;
        ir_in = SET_ADDR;
        @(posedge tck);
        
        v_sdr = 1'b1;
        for (i = 0; i < AW; i = i + 1) begin
            tdi = address[i];
            @(posedge tck);
        end
        v_sdr = 1'b0;
        
        @(posedge tck);
        udr = 1'b1;
        @(posedge tck);
        udr = 1'b0;
        @(posedge tck);
    endtask
    
    //==========================================================================
    // Task para simular operación JTAG WRITE (escribe en RAM)
    //==========================================================================
    task jtag_write_to_ram(input [DW-1:0] write_data);
        integer i;
        
        ir_in = WRITE;
        @(posedge tck);
        
        v_sdr = 1'b1;
        for (i = 0; i < DW; i = i + 1) begin
            tdi = write_data[i];
            @(posedge tck);
        end
        v_sdr = 1'b0;
        
        @(posedge tck);
        udr = 1'b1;
        @(posedge tck);
        udr = 1'b0;
        
        // Esperar que la escritura se propague a RAM
        repeat(3) @(posedge tck);
    endtask
    
    //==========================================================================
    // Task para simular operación JTAG READ (lee de RAM)
    //==========================================================================
    task jtag_read_from_ram(output [DW-1:0] read_data);
        integer i;
        
        // Esperar latencia de lectura de RAM
        repeat(3) @(posedge tck);
        
        ir_in = READ;
        @(posedge tck);
        
        v_cdr = 1'b1;
        @(posedge tck);
        v_cdr = 1'b0;
        
        v_sdr = 1'b1;
        for (i = 0; i < DW; i = i + 1) begin
            @(posedge tck);
            read_data[i] = tdo;
        end
        v_sdr = 1'b0;
        @(posedge tck);
    endtask
    
    //==========================================================================
    // Proceso de pruebas
    //==========================================================================
    initial begin
        // Inicialización
        $display("================================================================================");
        $display("  Testbench Integrado: VJTAG Interface + RAM");
        $display("================================================================================");
        $display("Parámetros: DW=%0d, AW=%0d, RAM_ADDR_WIDTH=%0d", DW, AW, RAM_ADDR_WIDTH);
        $display("Tiempo: %0t", $time);
        $display("");
        
        // Valores iniciales
        aclr = 1'b0;
        tdi = 1'b0;
        ir_in = BYPASS;
        v_cdr = 1'b0;
        v_sdr = 1'b0;
        udr = 1'b0;
        
        // Reset
        #5;
        aclr = 1'b1;
        repeat(5) @(posedge tck);
        
        //----------------------------------------------------------------------
        // TEST 1: Escribir y leer datos básicos
        //----------------------------------------------------------------------
        $display("TEST 1: Escritura y lectura básica a través de JTAG");
        $display("--------------------------------------------------------------------------------");
        
        jtag_set_addr(16'h00000);
        jtag_write_to_ram(8'hAA);
        
        jtag_set_addr(16'h00001);
        jtag_write_to_ram(8'h55);
        
        jtag_set_addr(16'h00002);
        jtag_write_to_ram(8'hFF);
        
        // Leer y verificar
        jtag_set_addr(16'h00000);
        begin
            logic [DW-1:0] read_val;
            jtag_read_from_ram(read_val);
            check_result("READ from RAM addr 0x00000", 8'hAA, read_val);
        end
        
        jtag_set_addr(16'h00001);
        begin
            logic [DW-1:0] read_val;
            jtag_read_from_ram(read_val);
            check_result("READ from RAM addr 0x00001", 8'h55, read_val);
        end
        
        jtag_set_addr(16'h00002);
        begin
            logic [DW-1:0] read_val;
            jtag_read_from_ram(read_val);
            check_result("READ from RAM addr 0x00002", 8'hFF, read_val);
        end
        $display("");
        
        //----------------------------------------------------------------------
        // TEST 2: Secuencia de escrituras consecutivas
        //----------------------------------------------------------------------
        $display("TEST 2: Secuencia de escrituras consecutivas (0x10-0x1F)");
        $display("--------------------------------------------------------------------------------");
        
        begin : seq_write_test
            integer i;
            logic [7:0] expected_val;
            for (i = 0; i < 16; i = i + 1) begin
                jtag_set_addr(16'h00010 + i[15:0]);
                jtag_write_to_ram(8'(i * 16));
            end
            
            // Verificar lecturas
            for (i = 0; i < 16; i = i + 1) begin
                logic [DW-1:0] read_val;
                expected_val = i * 16;
                jtag_set_addr(16'h00010 + i[15:0]);
                jtag_read_from_ram(read_val);
                check_result($sformatf("READ RAM[0x%05h]", 16'h00010 + i[15:0]), expected_val, read_val);
            end
        end
        $display("");
        
        //----------------------------------------------------------------------
        // TEST 3: Sobrescritura de datos
        //----------------------------------------------------------------------
        $display("TEST 3: Sobrescritura de datos");
        $display("--------------------------------------------------------------------------------");
        
        jtag_set_addr(16'h00100);
        jtag_write_to_ram(8'hCC);
        
        begin
            logic [DW-1:0] read_val;
            jtag_set_addr(16'h00100);
            jtag_read_from_ram(read_val);
            check_result("Lectura inicial 0x00100", 8'hCC, read_val);
        end
        
        // Sobrescribir
        jtag_set_addr(16'h00100);
        jtag_write_to_ram(8'h33);
        
        begin
            logic [DW-1:0] read_val;
            jtag_set_addr(16'h00100);
            jtag_read_from_ram(read_val);
            check_result("Lectura después de sobrescribir 0x00100", 8'h33, read_val);
        end
        $display("");
        
        //----------------------------------------------------------------------
        // TEST 4: Direcciones límite
        //----------------------------------------------------------------------
        $display("TEST 4: Direcciones límite");
        $display("--------------------------------------------------------------------------------");
        
        // Dirección máxima (usando 16 bits de VJTAG - rango completo)
        // RAM tiene 65,536 palabras, dirección máxima es 0xFFFF
        jtag_set_addr(16'hFFFF);
        jtag_write_to_ram(8'hEE);
        
        begin
            logic [DW-1:0] read_val;
            jtag_set_addr(16'hFFFF);
            jtag_read_from_ram(read_val);
            check_result("READ from MAX addr 0xFFFF", 8'hEE, read_val);
        end
        
        // Dirección mínima
        jtag_set_addr(16'h00000);
        jtag_write_to_ram(8'hDD);
        
        begin
            logic [DW-1:0] read_val;
            jtag_set_addr(16'h00000);
            jtag_read_from_ram(read_val);
            check_result("READ from MIN addr 0x00000", 8'hDD, read_val);
        end
        $display("");
        
        //----------------------------------------------------------------------
        // TEST 5: Patrón de prueba completo (similar a test_memory_debug.py)
        //----------------------------------------------------------------------
        $display("TEST 5: Patrón similar a test_memory_debug.py");
        $display("--------------------------------------------------------------------------------");
        
        // Escribir patrón
        jtag_set_addr(16'h00000); jtag_write_to_ram(8'h11);
        jtag_set_addr(16'h00001); jtag_write_to_ram(8'h22);
        jtag_set_addr(16'h00002); jtag_write_to_ram(8'h33);
        jtag_set_addr(16'h00003); jtag_write_to_ram(8'h44);
        jtag_set_addr(16'h00004); jtag_write_to_ram(8'h55);
        jtag_set_addr(16'h00005); jtag_write_to_ram(8'h66);
        
        // Verificar patrón
        begin : verify_pattern
            logic [DW-1:0] expected_values[6];
            integer i;
            
            expected_values[0] = 8'h11;
            expected_values[1] = 8'h22;
            expected_values[2] = 8'h33;
            expected_values[3] = 8'h44;
            expected_values[4] = 8'h55;
            expected_values[5] = 8'h66;
            
            for (i = 0; i < 6; i = i + 1) begin
                logic [DW-1:0] read_val;
                jtag_set_addr(20'(i));
                jtag_read_from_ram(read_val);
                check_result($sformatf("PATTERN addr 0x%05h", i), expected_values[i], read_val);
            end
        end
        $display("");
        
        //----------------------------------------------------------------------
        // TEST 6: Integración de señales de debug
        //----------------------------------------------------------------------
        $display("TEST 6: Verificación de señales de debug");
        $display("--------------------------------------------------------------------------------");
        
        jtag_set_addr(16'h00500);
        jtag_write_to_ram(8'hBE);
        
        check_result("debug_dr1 después de WRITE", 8'hBE, debug_dr1);
        check_result("jtag_addr_out", 16'h00500, jtag_addr_out);
        
        begin
            logic [DW-1:0] read_val;
            jtag_set_addr(16'h00500);
            jtag_read_from_ram(read_val);
            // Verificar que el valor leído es correcto (esto prueba que debug_dr2 funcionó)
            check_result("READ value después de captura", 8'hBE, read_val);
        end
        $display("");
        
        //----------------------------------------------------------------------
        // Resumen final
        //----------------------------------------------------------------------
        $display("================================================================================");
        $display("  RESUMEN DE PRUEBAS - VJTAG+RAM Integrated Testbench");
        $display("================================================================================");
        $display("Total de pruebas: %0d", test_count);
        $display("Pruebas exitosas: %0d", pass_count);
        $display("Pruebas fallidas: %0d", fail_count);
        $display("Tasa de éxito:    %.1f%%", (pass_count * 100.0) / test_count);
        $display("================================================================================");
        
        if (fail_count == 0) begin
            $display("*** TODAS LAS PRUEBAS PASARON ***");
            $display("*** El sistema VJTAG+RAM está funcionando correctamente ***");
        end else begin
            $display("*** ALGUNAS PRUEBAS FALLARON ***");
        end
        $display("");
        
        // Finalizar simulación
        #100;
        $finish;
    end
    
    //==========================================================================
    // Monitor de señales críticas (opcional para debugging)
    //==========================================================================
    initial begin
        $display("Monitor de señales críticas activado");
        $display("--------------------------------------------------------------------------------");
    end
    
    // Monitorear escrituras a RAM
    always @(posedge ram_wren) begin
        $display("[RAM WRITE] Time=%0t, Addr=0x%05h, Data=0x%02h", 
                 $time, ram_wraddress, ram_data);
    end
    
    //==========================================================================
    // Timeout de seguridad
    //==========================================================================
    initial begin
        #200000; // 200 us timeout
        $display("[ERROR] Timeout de simulación alcanzado");
        $finish;
    end

endmodule
