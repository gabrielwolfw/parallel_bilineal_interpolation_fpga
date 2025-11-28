//============================================================
// dsa_jtag_interface_tb. sv
// Testbench para la interfaz JTAG
//============================================================

`timescale 1ns/1ps

module dsa_jtag_interface_tb;

    //========================================================
    // Parámetros
    //========================================================
    parameter CLK_PERIOD = 20;
    parameter ADDR_WIDTH = 18;
    parameter DATA_WIDTH = 8;

    //========================================================
    // Señales del DUT
    //========================================================
    logic        clk;
    logic        rst;
    
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
    
    logic                    mem_write_en;
    logic                    mem_read_en;
    logic [ADDR_WIDTH-1:0]   mem_addr;
    logic [DATA_WIDTH-1:0]   mem_data_out;
    logic [DATA_WIDTH-1:0]   mem_data_in;
    
    logic [7:0]  jtag_rx_data;
    logic        jtag_rx_valid;
    logic        jtag_rx_ready;
    logic [7:0]  jtag_tx_data;
    logic        jtag_tx_valid;
    logic        jtag_tx_ready;

    //========================================================
    // Comandos del protocolo
    //========================================================
    localparam [7:0] CMD_NOP           = 8'h00;
    localparam [7:0] CMD_SET_WIDTH     = 8'h01;
    localparam [7:0] CMD_SET_HEIGHT    = 8'h02;
    localparam [7:0] CMD_SET_SCALE     = 8'h03;
    localparam [7:0] CMD_SET_MODE      = 8'h04;
    localparam [7:0] CMD_START         = 8'h05;
    localparam [7:0] CMD_GET_STATUS    = 8'h06;
    localparam [7:0] CMD_GET_PROGRESS  = 8'h07;
    localparam [7:0] CMD_GET_METRICS   = 8'h08;
    localparam [7:0] CMD_WRITE_MEM     = 8'h10;
    localparam [7:0] CMD_READ_MEM      = 8'h11;
    localparam [7:0] CMD_SET_ADDR      = 8'h12;
    
    localparam [7:0] RSP_OK            = 8'hA0;
    localparam [7:0] RSP_ERROR         = 8'hE0;
    localparam [7:0] RSP_BUSY          = 8'hB0;

    //========================================================
    // Memoria simulada
    //========================================================
    logic [7:0] sim_memory [0:1023];
    
    //========================================================
    // Variables de prueba
    //========================================================
    integer test_num;
    integer errors;

    //========================================================
    // Generación de reloj
    //========================================================
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    //========================================================
    // Instancia del DUT
    //========================================================
    dsa_jtag_interface #(
        . ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH)
    ) dut (
        .clk(clk),
        .rst(rst),
        . dsa_start(dsa_start),
        .dsa_mode_simd(dsa_mode_simd),
        .dsa_img_width(dsa_img_width),
        . dsa_img_height(dsa_img_height),
        .dsa_scale_factor(dsa_scale_factor),
        .dsa_busy(dsa_busy),
        .dsa_ready(dsa_ready),
        . dsa_progress(dsa_progress),
        .dsa_flops_count(dsa_flops_count),
        .dsa_mem_reads(dsa_mem_reads),
        .dsa_mem_writes(dsa_mem_writes),
        . mem_write_en(mem_write_en),
        . mem_read_en(mem_read_en),
        . mem_addr(mem_addr),
        .mem_data_out(mem_data_out),
        .mem_data_in(mem_data_in),
        .jtag_rx_data(jtag_rx_data),
        . jtag_rx_valid(jtag_rx_valid),
        . jtag_rx_ready(jtag_rx_ready),
        .jtag_tx_data(jtag_tx_data),
        .jtag_tx_valid(jtag_tx_valid),
        .jtag_tx_ready(jtag_tx_ready)
    );

    //========================================================
    // Simulación de memoria
    //========================================================
    always_ff @(posedge clk) begin
        if (mem_write_en) begin
            sim_memory[mem_addr[9:0]] <= mem_data_out;
        end
        if (mem_read_en) begin
            mem_data_in <= sim_memory[mem_addr[9:0]];
        end
    end

    //========================================================
    // Tasks para comunicación JTAG
    //========================================================
    
    task send_byte(input logic [7:0] data);
        begin
            while (! jtag_rx_ready) @(posedge clk);
            jtag_rx_data = data;
            jtag_rx_valid = 1'b1;
            @(posedge clk);
            jtag_rx_valid = 1'b0;
            @(posedge clk);
        end
    endtask
    
    task receive_byte(output logic [7:0] data);
        integer timeout;
        begin
            timeout = 0;
            jtag_tx_ready = 1'b1;
            
            while (!jtag_tx_valid && timeout < 1000) begin
                @(posedge clk);
                timeout = timeout + 1;
            end
            
            if (timeout >= 1000) begin
                $display("ERROR: Timeout esperando respuesta TX");
                data = 8'hFF;
            end else begin
                data = jtag_tx_data;
                @(posedge clk);
            end
            
            jtag_tx_ready = 1'b0;
            @(posedge clk);
        end
    endtask

    //========================================================
    // Tasks de comandos
    //========================================================
    
    task cmd_nop();
        logic [7:0] resp;
        begin
            $display("  Enviando CMD_NOP.. .");
            send_byte(CMD_NOP);
            receive_byte(resp);
            
            if (resp == RSP_OK)
                $display("  -> Respuesta OK");
            else begin
                $display("  -> ERROR: Respuesta 0x%02X", resp);
                errors = errors + 1;
            end
        end
    endtask
    
    task cmd_set_width(input logic [15:0] width);
        logic [7:0] resp;
        begin
            $display("  Enviando CMD_SET_WIDTH = %0d...", width);
            send_byte(CMD_SET_WIDTH);
            send_byte(width[15:8]);
            send_byte(width[7:0]);
            receive_byte(resp);
            
            if (resp == RSP_OK && dsa_img_width == width)
                $display("  -> OK: Width = %0d", dsa_img_width);
            else begin
                $display("  -> ERROR");
                errors = errors + 1;
            end
        end
    endtask
    
    task cmd_set_height(input logic [15:0] height);
        logic [7:0] resp;
        begin
            $display("  Enviando CMD_SET_HEIGHT = %0d...", height);
            send_byte(CMD_SET_HEIGHT);
            send_byte(height[15:8]);
            send_byte(height[7:0]);
            receive_byte(resp);
            
            if (resp == RSP_OK && dsa_img_height == height)
                $display("  -> OK: Height = %0d", dsa_img_height);
            else begin
                $display("  -> ERROR");
                errors = errors + 1;
            end
        end
    endtask
    
    task cmd_set_scale(input logic [7:0] scale);
        logic [7:0] resp;
        begin
            $display("  Enviando CMD_SET_SCALE = 0x%02X...", scale);
            send_byte(CMD_SET_SCALE);
            send_byte(scale);
            receive_byte(resp);
            
            if (resp == RSP_OK && dsa_scale_factor == scale)
                $display("  -> OK: Scale = 0x%02X", dsa_scale_factor);
            else begin
                $display("  -> ERROR");
                errors = errors + 1;
            end
        end
    endtask
    
    task cmd_set_mode(input logic simd);
        logic [7:0] resp;
        begin
            $display("  Enviando CMD_SET_MODE = %s...", simd ?  "SIMD" : "SEQ");
            send_byte(CMD_SET_MODE);
            send_byte({7'd0, simd});
            receive_byte(resp);
            
            if (resp == RSP_OK && dsa_mode_simd == simd)
                $display("  -> OK: Mode = %s", dsa_mode_simd ? "SIMD" : "SEQ");
            else begin
                $display("  -> ERROR");
                errors = errors + 1;
            end
        end
    endtask
    
    task cmd_start();
        logic [7:0] resp;
        begin
            $display("  Enviando CMD_START...");
            send_byte(CMD_START);
            receive_byte(resp);
            
            if (resp == RSP_OK)
                $display("  -> OK: Start enviado");
            else if (resp == RSP_BUSY)
                $display("  -> DSA ocupado");
            else begin
                $display("  -> ERROR: 0x%02X", resp);
                errors = errors + 1;
            end
        end
    endtask
    
    task cmd_get_status();
        logic [7:0] resp0, resp1;
        begin
            $display("  Enviando CMD_GET_STATUS...");
            send_byte(CMD_GET_STATUS);
            receive_byte(resp0);
            receive_byte(resp1);
            
            if (resp0 == RSP_OK)
                $display("  -> OK: busy=%0d, ready=%0d", resp1[0], resp1[1]);
            else begin
                $display("  -> ERROR");
                errors = errors + 1;
            end
        end
    endtask
    
    task cmd_get_progress();
        logic [7:0] resp0, resp1, resp2;
        logic [15:0] progress;
        begin
            $display("  Enviando CMD_GET_PROGRESS...");
            send_byte(CMD_GET_PROGRESS);
            receive_byte(resp0);
            receive_byte(resp1);
            receive_byte(resp2);
            
            if (resp0 == RSP_OK) begin
                progress = {resp1, resp2};
                $display("  -> OK: Progress = %0d", progress);
            end else begin
                $display("  -> ERROR");
                errors = errors + 1;
            end
        end
    endtask
    
    task cmd_get_metrics();
        logic [7:0] resp [0:12];
        logic [31:0] flops, reads, writes;
        integer i;
        begin
            $display("  Enviando CMD_GET_METRICS...");
            send_byte(CMD_GET_METRICS);
            
            for (i = 0; i < 13; i = i + 1)
                receive_byte(resp[i]);
            
            if (resp[0] == RSP_OK) begin
                flops  = {resp[1], resp[2], resp[3], resp[4]};
                reads  = {resp[5], resp[6], resp[7], resp[8]};
                writes = {resp[9], resp[10], resp[11], resp[12]};
                $display("  -> OK: FLOPs=%0d, Reads=%0d, Writes=%0d", flops, reads, writes);
            end else begin
                $display("  -> ERROR");
                errors = errors + 1;
            end
        end
    endtask

    //========================================================
    // Tests
    //========================================================
    
    task reset_system();
        integer i;
        begin
            $display("\n[RESET] Reseteando sistema...");
            rst = 1;
            jtag_rx_data = 8'd0;
            jtag_rx_valid = 1'b0;
            jtag_tx_ready = 1'b0;
            
            dsa_busy = 1'b0;
            dsa_ready = 1'b0;
            dsa_progress = 16'd0;
            dsa_flops_count = 32'd12345;
            dsa_mem_reads = 32'd1000;
            dsa_mem_writes = 32'd2000;
            
            for (i = 0; i < 1024; i = i + 1)
                sim_memory[i] = i[7:0];
            
            repeat(10) @(posedge clk);
            rst = 0;
            repeat(5) @(posedge clk);
            $display("[RESET] Completado\n");
        end
    endtask
    
    task test_basic_commands();
        begin
            test_num = test_num + 1;
            $display("========================================");
            $display("TEST %0d: Comandos basicos", test_num);
            $display("========================================");
            
            cmd_nop();
            repeat(5) @(posedge clk);
            
            cmd_set_width(16'd256);
            repeat(5) @(posedge clk);
            
            cmd_set_height(16'd256);
            repeat(5) @(posedge clk);
            
            cmd_set_scale(8'h80);
            repeat(5) @(posedge clk);
            
            cmd_set_mode(1'b1);
            repeat(5) @(posedge clk);
            
            $display("TEST %0d COMPLETADO\n", test_num);
        end
    endtask
    
    task test_status_commands();
        begin
            test_num = test_num + 1;
            $display("========================================");
            $display("TEST %0d: Comandos de estado", test_num);
            $display("========================================");
            
            dsa_busy = 1'b0;
            dsa_ready = 1'b1;
            dsa_progress = 16'd12345;
            
            cmd_get_status();
            repeat(5) @(posedge clk);
            
            cmd_get_progress();
            repeat(5) @(posedge clk);
            
            cmd_get_metrics();
            repeat(5) @(posedge clk);
            
            $display("TEST %0d COMPLETADO\n", test_num);
        end
    endtask
    
    task test_start_command();
        begin
            test_num = test_num + 1;
            $display("========================================");
            $display("TEST %0d: Comando START", test_num);
            $display("========================================");
            
            dsa_busy = 1'b0;
            cmd_start();
            repeat(5) @(posedge clk);
            
            dsa_busy = 1'b1;
            cmd_start();
            repeat(5) @(posedge clk);
            
            dsa_busy = 1'b0;
            
            $display("TEST %0d COMPLETADO\n", test_num);
        end
    endtask
    
    task test_full_workflow();
        integer i;
        begin
            test_num = test_num + 1;
            $display("========================================");
            $display("TEST %0d: Flujo completo", test_num);
            $display("========================================");
            
            $display("  Paso 1: Configuracion.. .");
            cmd_set_width(16'd512);
            cmd_set_height(16'd512);
            cmd_set_scale(8'h80);
            cmd_set_mode(1'b1);
            
            $display("  Paso 2: Verificar estado...");
            dsa_busy = 1'b0;
            dsa_ready = 1'b0;
            cmd_get_status();
            
            $display("  Paso 3: Iniciar.. .");
            cmd_start();
            
            $display("  Paso 4: Simulando procesamiento...");
            dsa_busy = 1'b1;
            dsa_progress = 16'd0;
            
            for (i = 0; i < 3; i = i + 1) begin
                repeat(50) @(posedge clk);
                dsa_progress = dsa_progress + 16'd1000;
                cmd_get_progress();
            end
            
            $display("  Paso 5: Completando...");
            dsa_busy = 1'b0;
            dsa_ready = 1'b1;
            cmd_get_status();
            
            $display("  Paso 6: metricas...");
            cmd_get_metrics();
            
            $display("TEST %0d COMPLETADO\n", test_num);
        end
    endtask

    //========================================================
    // Secuencia principal
    //========================================================
    initial begin
        $display("\n");
        $display("====================================================");
        $display("TESTBENCH: dsa_jtag_interface");
        $display("====================================================\n");
        
        test_num = 0;
        errors = 0;
        
        reset_system();
        
        test_basic_commands();
        test_status_commands();
        test_start_command();
        test_full_workflow();
        
        $display("====================================================");
        $display("RESUMEN FINAL");
        $display("====================================================");
        $display("Tests ejecutados: %0d", test_num);
        $display("Errores: %0d", errors);
        
        if (errors == 0)
            $display("RESULTADO: PASS");
        else
            $display("RESULTADO: FAIL");
            
        $display("====================================================\n");
        
        $finish;
    end

    //========================================================
    // Timeout
    //========================================================
    initial begin
        #1000000;
        $display("ERROR: Timeout global");
        $finish;
    end

endmodule