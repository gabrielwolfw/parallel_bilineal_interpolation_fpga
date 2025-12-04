//============================================================
// dsa_top_tb.sv
// Testbench completo para dsa_top
// Compatible con la nueva interfaz
//============================================================

`timescale 1ns/1ps

module dsa_top_tb;

    //========================================================
    // Parámetros
    //========================================================
    parameter CLK_PERIOD = 10;
    parameter ADDR_WIDTH = 18;
    parameter IMG_WIDTH_MAX = 1024;
    parameter IMG_HEIGHT_MAX = 1024;
    parameter SIMD_WIDTH = 4;
    parameter MEM_SIZE = 262144;

    //========================================================
    // Señales del DUT
    //========================================================
    logic                   clk;
    logic                   rst;
    logic                   start;
    logic                   mode_simd;
    logic [15:0]            img_width_in;
    logic [15:0]            img_height_in;
    logic [7:0]             scale_factor;
    logic                   ext_mem_write_en;
    logic                   ext_mem_read_en;
    logic [ADDR_WIDTH-1:0]  ext_mem_addr;
    logic [7:0]             ext_mem_data_in;
    logic [7:0]             ext_mem_data_out;
    logic                   busy;
    logic                   ready;
    logic [15:0]            progress;
    logic [31:0]            flops_count;
    logic [31:0]            mem_reads_count;
    logic [31:0]            mem_writes_count;

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
    dsa_top #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .IMG_WIDTH(IMG_WIDTH_MAX),
        .IMG_HEIGHT(IMG_HEIGHT_MAX),
        .SIMD_WIDTH(SIMD_WIDTH),
        .MEM_SIZE(MEM_SIZE)
    ) dut (
        .clk(clk),
        .rst(rst),
        .start(start),
        .mode_simd(mode_simd),
        .img_width_in(img_width_in),
        .img_height_in(img_height_in),
        .scale_factor(scale_factor),
        .ext_mem_write_en(ext_mem_write_en),
        .ext_mem_read_en(ext_mem_read_en),
        .ext_mem_addr(ext_mem_addr),
        .ext_mem_data_in(ext_mem_data_in),
        .ext_mem_data_out(ext_mem_data_out),
        .busy(busy),
        .ready(ready),
        .progress(progress),
        .flops_count(flops_count),
        .mem_reads_count(mem_reads_count),
        .mem_writes_count(mem_writes_count)
    );

    //========================================================
    // Variables de prueba
    //========================================================
    integer test_num;
    integer cycle_count;
    integer seq_cycles;
    integer simd_cycles;
    real speedup;
    //========================================================
    // Tasks
    //========================================================

    // Reset del sistema
    task reset_system();
        begin
            $display("[%0t] Reseteando sistema...", $time);
            rst = 1;
            start = 0;
            mode_simd = 0;
            img_width_in = 0;
            img_height_in = 0;
            scale_factor = 0;
            ext_mem_write_en = 0;
            ext_mem_read_en = 0;
            ext_mem_addr = 0;
            ext_mem_data_in = 0;
            
            repeat(10) @(posedge clk);
            rst = 0;
            repeat(5) @(posedge clk);
            $display("[%0t] Reset completado", $time);
        end
    endtask

    // Cargar imagen de prueba en memoria
    task load_test_image(input integer width, input integer height);
        integer x, y;
        integer addr;
        logic [7:0] pixel_value;
        begin
            $display("[%0t] Cargando imagen de prueba %0dx%0d...", $time, width, height);
            
            ext_mem_write_en = 1;
            
            for (y = 0; y < height; y = y + 1) begin
                for (x = 0; x < width; x = x + 1) begin
                    addr = y * width + x;
                    
                    // Patrón de prueba: gradiente diagonal
                    pixel_value = ((x + y) * 255) / (width + height - 2);
                    
                    ext_mem_addr = addr[ADDR_WIDTH-1:0];
                    ext_mem_data_in = pixel_value;
                    
                    @(posedge clk);
                end
                
                // Mostrar progreso cada 8 filas
                if (y % 8 == 0) begin
                    $display("  Cargando fila %0d/%0d", y, height);
                end
            end
            
            ext_mem_write_en = 0;
            @(posedge clk);
            
            $display("[%0t] Imagen cargada exitosamente", $time);
        end
    endtask

    // Iniciar procesamiento
    task start_processing(input logic simd_mode);
        begin
            $display("[%0t] Iniciando procesamiento en modo %s", 
                     $time, simd_mode ? "SIMD" : "SECUENCIAL");
            
            mode_simd = simd_mode;
            cycle_count = 0;
            
            start = 1;
            @(posedge clk);
            start = 0;
            @(posedge clk);
        end
    endtask

    // Esperar a que termine el procesamiento
    task wait_for_completion();
        integer timeout_cycles;
        begin
            timeout_cycles = 1000000;
            
            $display("[%0t] Esperando completar procesamiento...", $time);
            
            while (!ready && cycle_count < timeout_cycles) begin
                @(posedge clk);
                cycle_count = cycle_count + 1;
                
                // Mostrar progreso cada 1000 ciclos
                if (cycle_count % 1000 == 0) begin
                    $display("  Ciclo %0d: Progreso = %0d pixeles", cycle_count, progress);
                end
            end
            
            if (cycle_count >= timeout_cycles) begin
                $display("ERROR: Timeout después de %0d ciclos", timeout_cycles);
                $finish;
            end
            
            $display("[%0t] Procesamiento completado en %0d ciclos", $time, cycle_count);
            $display("  FLOPs ejecutadas: %0d", flops_count);
            $display("  Lecturas de memoria: %0d", mem_reads_count);
            $display("  Escrituras de memoria: %0d", mem_writes_count);
            
            if (cycle_count > 0) begin
                $display("  Throughput: %.2f FLOPs/ciclo", 
                         real'(flops_count) / real'(cycle_count));
            end
        end
    endtask

    // Verificar píxel de salida
    task verify_output_pixel(
        input integer x, 
        input integer y, 
        input integer width_out,
        input logic [7:0] expected
    );
        integer addr;
        logic [7:0] actual;
        integer tolerance;
        begin
            tolerance = 2; // Tolerancia para errores de redondeo
            
            addr = (MEM_SIZE/2) + (y * width_out + x);
            
            ext_mem_read_en = 1;
            ext_mem_addr = addr[ADDR_WIDTH-1:0];
            @(posedge clk);
            actual = ext_mem_data_out;
            ext_mem_read_en = 0;
            @(posedge clk);
            
            if ((actual >= expected - tolerance) && (actual <= expected + tolerance)) begin
                // Correcto
            end else begin
                $display("ERROR: Píxel (%0d,%0d) esperado=%0d obtenido=%0d diferencia=%0d",
                         x, y, expected, actual, $signed(actual - expected));
            end
        end
    endtask

    // Mostrar imagen de salida
    task dump_output_image(input integer width_out, input integer height_out);
        integer x, y, addr;
        logic [7:0] pixel;
        begin
            $display("");
            $display("========================================");
            $display("Imagen de salida (%0dx%0d)", width_out, height_out);
            $display("========================================");
            
            for (y = 0; y < height_out; y = y + 1) begin
                $write("Fila %2d: ", y);
                for (x = 0; x < width_out; x = x + 1) begin
                    addr = (MEM_SIZE/2) + (y * width_out + x);
                    ext_mem_read_en = 1;
                    ext_mem_addr = addr[ADDR_WIDTH-1:0];
                    @(posedge clk); // Ciclo 1: Dirección registrada
						  @(posedge clk); // Ciclo 2: Dato disponible
                    pixel = ext_mem_data_out;
                    ext_mem_read_en = 0;
                    
                    $write("%3d ", pixel);
                end
                $write("\n");
            end
            
            $display("========================================");
            $display("");
        end
    endtask

    //========================================================
    // Test 1: Imagen pequeña secuencial
    //========================================================
    task test_small_sequential();
        integer test_width, test_height;
        integer width_out, height_out;
        begin
            test_num = test_num + 1;
            $display("");
            $display("========================================");
            $display("TEST %0d: Imagen 16x16 Secuencial", test_num);
            $display("========================================");
            
            test_width = 16;
            test_height = 16;
            
            reset_system();
            load_test_image(test_width, test_height);
            
            img_width_in = test_width;
            img_height_in = test_height;
            scale_factor = 8'h80;  // 0.5
				
            
            width_out = (test_width * 8'h80) >> 8;
            height_out = (test_height * 8'h80) >> 8;
            
            $display("Dimensiones salida esperadas: %0dx%0d", width_out, height_out);
            
            start_processing(0); // Secuencial
            wait_for_completion();
            
            seq_cycles = cycle_count;
            
            // Mostrar resultado
            dump_output_image(width_out, height_out);
            
            $display("TEST %0d COMPLETADO", test_num);
        end
    endtask

    //========================================================
    // Test 2: Imagen pequeña SIMD
    //========================================================
    task test_small_simd();
        integer test_width, test_height;
        integer width_out, height_out;
        begin
            test_num = test_num + 1;
            $display("");
            $display("========================================");
            $display("TEST %0d: Imagen 16x16 SIMD", test_num);
            $display("========================================");
            
            test_width = 16;
            test_height = 16;
            
            reset_system();
            load_test_image(test_width, test_height);
            
            img_width_in = test_width;
            img_height_in = test_height;
            scale_factor = 8'h80;  // 0.5
            
            width_out = (test_width * 8'h80) >> 8;
            height_out = (test_height * 8'h80) >> 8;
            
            $display("Dimensiones salida esperadas: %0dx%0d", width_out, height_out);
            
            start_processing(1); // SIMD
            wait_for_completion();
            
            simd_cycles = cycle_count;
            
            // Mostrar resultado
            dump_output_image(width_out, height_out);
            
            $display("TEST %0d COMPLETADO", test_num);
        end
    endtask

    //========================================================
    // Test 3: Imagen mediana secuencial
    //========================================================
    task test_medium_sequential();
        integer test_width, test_height;
        integer width_out, height_out;
        begin
            test_num = test_num + 1;
            $display("");
            $display("========================================");
            $display("TEST %0d: Imagen 16x16 Secuencial", test_num);
            $display("========================================");
            
            test_width = 16;
            test_height = 16;
            
            reset_system();
            load_test_image(test_width, test_height);
            
            img_width_in = test_width;
            img_height_in = test_height;
            scale_factor = 8'h80;  // 0.5
            
            width_out = (test_width * 8'h80) >> 8;
            height_out = (test_height * 8'h80) >> 8;
            
            $display("Dimensiones salida esperadas: %0dx%0d", width_out, height_out);
            
            start_processing(0); // Secuencial
            wait_for_completion();
            
            seq_cycles = cycle_count;
            
            $display("TEST %0d COMPLETADO", test_num);
        end
    endtask

    //========================================================
    // Test 4: Imagen mediana SIMD
    //========================================================
    task test_medium_simd();
        integer test_width, test_height;
        integer width_out, height_out;
        begin
            test_num = test_num + 1;
            $display("");
            $display("========================================");
            $display("TEST %0d: Imagen 16x16 SIMD", test_num);
            $display("========================================");
            
            test_width = 16;
            test_height = 16;
            
            reset_system();
            load_test_image(test_width, test_height);
            
            img_width_in = test_width;
            img_height_in = test_height;
            scale_factor = 8'h80;  // 0.5
            
            width_out = (test_width * 8'h80) >> 8;
            height_out = (test_height * 8'h80) >> 8;
            
            $display("Dimensiones salida esperadas: %0dx%0d", width_out, height_out);
            
            start_processing(1); // SIMD
            wait_for_completion();
            
            simd_cycles = cycle_count;
            
            $display("TEST %0d COMPLETADO", test_num);
        end
    endtask

    //========================================================
    // Test 5: Comparacion de rendimiento
    //========================================================
    task test_performance_comparison();
        integer test_width, test_height;
        begin
            test_num = test_num + 1;
            $display("");
            $display("========================================");
            $display("TEST %0d: Comparacion de Rendimiento 16x16", test_num);
            $display("========================================");
            
            test_width = 16;
            test_height = 16;
            
            // Secuencial
            $display("");
            $display("--- MODO SECUENCIAL ---");
            reset_system();
            load_test_image(test_width, test_height);
            img_width_in = test_width;
            img_height_in = test_height;
            scale_factor = 8'h80; // 0.7 -> 0.5 8'h80
            start_processing(0);
            wait_for_completion();
            seq_cycles = cycle_count;
            
            // SIMD
            $display("");
            $display("--- MODO SIMD ---");
            reset_system();
            load_test_image(test_width, test_height);
            img_width_in = test_width;
            img_height_in = test_height;
            scale_factor = 8'h80; // 0.7
            start_processing(1);
            wait_for_completion();
            simd_cycles = cycle_count;
            
            // Comparacion
            $display("");
            $display("========================================");
            $display("RESULTADOS DE COMPARACION");
            $display("========================================");
            $display("Ciclos secuencial: %0d", seq_cycles);
            $display("Ciclos SIMD:       %0d", simd_cycles);
            
            if (simd_cycles > 0) begin
                speedup = real'(seq_cycles) / real'(simd_cycles);
                $display("Speedup:           %.2fx", speedup);
                $display("Eficiencia:        %.1f%%", (speedup / SIMD_WIDTH) * 100.0);
                
                if (speedup >= 1.5) begin
                    $display("RESULTADO: PASS (speedup >= 1.5x)");
                end else if (speedup >= 1.0) begin
                    $display("RESULTADO: MARGINAL (speedup >= 1.0x)");
                end else begin
                    $display("RESULTADO: FALLO (speedup < 1.0x)");
                end
            end
            
            $display("========================================");
            $display("");
            
            $display("TEST %0d COMPLETADO", test_num);
        end
    endtask

    //========================================================
    // Secuencia principal de tests
    //========================================================
    initial begin
        $display("");
        $display("====================================================");
        $display("INICIO DE TESTBENCH DSA DOWNSCALING");
        $display("====================================================");
        
        test_num = 0;
        
        // Ejecutar tests
        test_small_sequential();
        test_small_simd();
        test_medium_sequential();
        test_medium_simd();
        test_performance_comparison();
        
        // Resumen final
        $display("");
        $display("====================================================");
        $display("RESUMEN FINAL");
        $display("====================================================");
        $display("Tests ejecutados: %0d", test_num);
        $display("====================================================");
        $display("FIN DE TESTBENCH");
        $display("====================================================");
        
        $finish;
    end

    //========================================================
    // Timeout de seguridad
    //========================================================
    initial begin
        #100000000; // 100ms
        $display("ERROR: Timeout global del testbench");
        $finish;
    end

    //========================================================
    // Generación de waveforms
    //========================================================
    initial begin
        $dumpfile("dsa_top_tb.vcd");
        $dumpvars(0, dsa_top_tb);
    end

endmodule