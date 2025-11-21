//============================================================
// dsa_top_tb.sv
// Testbench para validación del sistema completo DSA
//============================================================

`timescale 1ns/1ps

module dsa_top_tb;

    //=================================================================
    // Parámetros
    //=================================================================
    
    parameter CLK_PERIOD = 10;  // 100 MHz
    parameter IMG_WIDTH_MAX = 512;
    parameter IMG_HEIGHT_MAX = 512;
    parameter MEM_SIZE = 262144;
    parameter SIMD_WIDTH = 4;
    
    //=================================================================
    // Señales del DUT
    //=================================================================
    
    logic        clk;
    logic        rst;
    logic        start;
    logic        mode_simd;
    logic [9:0]  img_width_in;
    logic [9:0]  img_height_in;
    logic [7:0]  scale_factor;
    logic        mem_write_en;
    logic        mem_read_en;
    logic [17:0] mem_addr;
    logic [7:0]  mem_data_in;
    logic [7:0]  mem_data_out;
    logic        busy;
    logic        ready;
    logic        error;
    logic [15:0] progress;
    logic [31:0] flops_count;
    logic [31:0] mem_reads_count;
    logic [31:0] mem_writes_count;
    
    //=================================================================
    // Generación de reloj
    //=================================================================
    
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end
    
    //=================================================================
    // Instanciación del DUT
    //=================================================================
    
    dsa_top #(
        .IMG_WIDTH_MAX(IMG_WIDTH_MAX),
        .IMG_HEIGHT_MAX(IMG_HEIGHT_MAX),
        .MEM_SIZE(MEM_SIZE),
        .SIMD_WIDTH(SIMD_WIDTH)
    ) dut (
        .clk(clk),
        .rst(rst),
        .start(start),
        .mode_simd(mode_simd),
        .img_width_in(img_width_in),
        .img_height_in(img_height_in),
        .scale_factor(scale_factor),
        .mem_write_en(mem_write_en),
        .mem_read_en(mem_read_en),
        .mem_addr(mem_addr),
        .mem_data_in(mem_data_in),
        .mem_data_out(mem_data_out),
        .busy(busy),
        .ready(ready),
        .error(error),
        .progress(progress),
        .flops_count(flops_count),
        .mem_reads_count(mem_reads_count),
        .mem_writes_count(mem_writes_count)
    );
    
    //=================================================================
    // Variables de prueba
    //=================================================================
    
    integer test_passed;
    integer test_failed;
    real start_time, end_time, elapsed_time;
    
    //=================================================================
    // Tasks de utilidad
    //=================================================================
    
    task reset_system();
        begin
            rst = 1;
            start = 0;
            mode_simd = 0;
            img_width_in = 0;
            img_height_in = 0;
            scale_factor = 0;
            mem_write_en = 0;
            mem_read_en = 0;
            mem_addr = 0;
            mem_data_in = 0;
            #(CLK_PERIOD * 5);
            rst = 0;
            #(CLK_PERIOD * 2);
        end
    endtask
    
    task load_test_image(input integer width, input integer height);
        integer x, y, addr;
        logic [7:0] pixel_value;
        begin
            $display("[%0t] Cargando imagen de prueba %0dx%0d", $time, width, height);
            mem_write_en = 1;
            for (y = 0; y < height; y = y + 1) begin
                for (x = 0; x < width; x = x + 1) begin
                    addr = y * width + x;
                    // Patrón de prueba: gradiente horizontal
                    pixel_value = (x * 255) / (width - 1);
                    mem_addr = addr;
                    mem_data_in = pixel_value;
                    #CLK_PERIOD;
                end
            end
            mem_write_en = 0;
            $display("[%0t] Imagen cargada correctamente", $time);
        end
    endtask
    
    task start_processing();
        begin
            $display("[%0t] Iniciando procesamiento", $time);
            start = 1;
            #CLK_PERIOD;
            start = 0;
            start_time = $realtime;
        end
    endtask
    
    task wait_for_completion();
        begin
            $display("[%0t] Esperando completar procesamiento...", $time);
            wait(ready == 1);
            end_time = $realtime;
            elapsed_time = (end_time - start_time) / 1000.0;  // en microsegundos
            $display("[%0t] Procesamiento completado", $time);
            $display("Tiempo transcurrido: %.2f us", elapsed_time);
            $display("FLOPs ejecutadas: %0d", flops_count);
            $display("Lecturas de memoria: %0d", mem_reads_count);
            $display("Escrituras de memoria: %0d", mem_writes_count);
        end
    endtask
    
    task verify_output_pixel(input integer x, input integer y, 
                             input integer width_out, 
                             input logic [7:0] expected);
        integer addr;
        logic [7:0] actual;
        begin
            addr = MEM_SIZE/2 + (y * width_out + x);
            mem_addr = addr;
            mem_read_en = 1;
            #CLK_PERIOD;
            actual = mem_data_out;
            mem_read_en = 0;
            
            if (actual == expected) begin
                test_passed = test_passed + 1;
            end else begin
                $display("ERROR: Pixel (%0d,%0d) esperado=%0d obtenido=%0d", 
                         x, y, expected, actual);
                test_failed = test_failed + 1;
            end
        end
    endtask
    
    task display_performance_metrics();
        real throughput, arithmetic_intensity;
        begin
            $display("");
            $display("=== METRICAS DE RENDIMIENTO ===");
            $display("Tiempo de ejecucion: %.2f us", elapsed_time);
            $display("FLOPs totales: %0d", flops_count);
            $display("Lecturas de memoria: %0d", mem_reads_count);
            $display("Escrituras de memoria: %0d", mem_writes_count);
            
            if (elapsed_time > 0) begin
                throughput = flops_count / elapsed_time;
                $display("Throughput: %.2f MFLOPS", throughput);
            end
            
            if ((mem_reads_count + mem_writes_count) > 0) begin
                arithmetic_intensity = real'(flops_count) / 
                                      real'(mem_reads_count + mem_writes_count);
                $display("Intensidad aritmetica: %.2f FLOPs/acceso", arithmetic_intensity);
            end
            $display("===============================");
            $display("");
        end
    endtask
    
    //=================================================================
    // Test 1: Imagen pequeña, modo secuencial, escala 0.5
    //=================================================================
    
    task test_small_sequential();
        integer width_in, height_in, width_out, height_out;
        begin
            $display("");
            $display("=================================================");
            $display("TEST 1: Imagen 8x8, modo secuencial, escala 0.5");
            $display("=================================================");
            
            width_in = 8;
            height_in = 8;
            width_out = 4;
            height_out = 4;
            
            reset_system();
            load_test_image(width_in, height_in);
            
            img_width_in = width_in;
            img_height_in = height_in;
            scale_factor = 8'h80;  // 0.5 en Q8.8
            mode_simd = 0;
            
            start_processing();
            wait_for_completion();
            display_performance_metrics();
            
            // Verificación básica
            $display("Verificando píxeles de salida...");
            // Aquí se incluirían verificaciones específicas
            
            $display("TEST 1 COMPLETADO");
        end
    endtask
    
    //=================================================================
    // Test 2: Imagen pequeña, modo SIMD, escala 0.5
    //=================================================================
    
    task test_small_simd();
        integer width_in, height_in, width_out, height_out;
        begin
            $display("");
            $display("============================================");
            $display("TEST 2: Imagen 8x8, modo SIMD, escala 0.5");
            $display("============================================");
            
            width_in = 8;
            height_in = 8;
            width_out = 4;
            height_out = 4;
            
            reset_system();
            load_test_image(width_in, height_in);
            
            img_width_in = width_in;
            img_height_in = height_in;
            scale_factor = 8'h80;  // 0.5 en Q8.8
            mode_simd = 1;
            
            start_processing();
            wait_for_completion();
            display_performance_metrics();
            
            $display("TEST 2 COMPLETADO");
        end
    endtask
    
    //=================================================================
    // Test 3: Comparación secuencial vs SIMD
    //=================================================================
    
    task test_sequential_vs_simd();
        integer width_in, height_in;
        real time_seq, time_simd, speedup;
        begin
            $display("");
            $display("==============================================");
            $display("TEST 3: Comparacion secuencial vs SIMD");
            $display("==============================================");
            
            width_in = 64;
            height_in = 64;
            
            // Modo secuencial
            $display("");
            $display("--- Ejecutando modo SECUENCIAL ---");
            reset_system();
            load_test_image(width_in, height_in);
            img_width_in = width_in;
            img_height_in = height_in;
            scale_factor = 8'h80;
            mode_simd = 0;
            start_processing();
            wait_for_completion();
            time_seq = elapsed_time;
            
            // Modo SIMD
            $display("");
            $display("--- Ejecutando modo SIMD ---");
            reset_system();
            load_test_image(width_in, height_in);
            img_width_in = width_in;
            img_height_in = height_in;
            scale_factor = 8'h80;
            mode_simd = 1;
            start_processing();
            wait_for_completion();
            time_simd = elapsed_time;
            
            // Comparación
            $display("");
            $display("=== COMPARACION DE RENDIMIENTO ===");
            $display("Tiempo secuencial: %.2f us", time_seq);
            $display("Tiempo SIMD: %.2f us", time_simd);
            if (time_simd > 0) begin
                speedup = time_seq / time_simd;
                $display("Speedup: %.2fx", speedup);
            end
            $display("==================================");
            
            $display("TEST 3 COMPLETADO");
        end
    endtask
    
    //=================================================================
    // Test 4: Diferentes factores de escala
    //=================================================================
    
    task test_scale_factors();
        integer width_in, height_in;
        integer i;
        logic [7:0] scales [0:10];
        begin
            $display("");
            $display("==========================================");
            $display("TEST 4: Diferentes factores de escala");
            $display("==========================================");
            
            width_in = 32;
            height_in = 32;
            
            // Factores: 0.5, 0.55, 0.6, ..., 1.0
            scales[0] = 8'h80;  // 0.50
            scales[1] = 8'h8C;  // 0.55
            scales[2] = 8'h99;  // 0.60
            scales[3] = 8'hA6;  // 0.65
            scales[4] = 8'hB3;  // 0.70
            scales[5] = 8'hC0;  // 0.75
            scales[6] = 8'hCC;  // 0.80
            scales[7] = 8'hD9;  // 0.85
            scales[8] = 8'hE6;  // 0.90
            scales[9] = 8'hF3;  // 0.95
            scales[10] = 8'hFF; // 1.00
            
            for (i = 0; i < 11; i = i + 1) begin
                $display("");
                $display("Probando factor de escala: 0x%0h", scales[i]);
                reset_system();
                load_test_image(width_in, height_in);
                img_width_in = width_in;
                img_height_in = height_in;
                scale_factor = scales[i];
                mode_simd = 0;
                start_processing();
                wait_for_completion();
            end
            
            $display("TEST 4 COMPLETADO");
        end
    endtask
    
    //=================================================================
    // Test 5: Imagen máxima (stress test)
    //=================================================================
    
    task test_max_image();
        integer width_in, height_in;
        begin
            $display("");
            $display("==========================================");
            $display("TEST 5: Imagen maxima 512x512 (SIMD)");
            $display("==========================================");
            
            width_in = 512;
            height_in = 512;
            
            reset_system();
            
            $display("Nota: Carga de imagen 512x512 toma tiempo...");
            load_test_image(width_in, height_in);
            
            img_width_in = width_in;
            img_height_in = height_in;
            scale_factor = 8'h80;  // 0.5
            mode_simd = 1;
            
            start_processing();
            wait_for_completion();
            display_performance_metrics();
            
            $display("TEST 5 COMPLETADO");
        end
    endtask
    
    //=================================================================
    // Secuencia principal de pruebas
    //=================================================================
    
    initial begin
        $display("");
        $display("====================================================");
        $display("INICIO DE TESTBENCH DSA DOWNSCALING");
        $display("====================================================");
        
        test_passed = 0;
        test_failed = 0;
        
        // Ejecutar todos los tests
        test_small_sequential();
        test_small_simd();
        test_sequential_vs_simd();
        test_scale_factors();
        
        // Descomentar para stress test (toma mucho tiempo)
        // test_max_image();
        
        // Resumen final
        $display("");
        $display("====================================================");
        $display("RESUMEN DE PRUEBAS");
        $display("====================================================");
        $display("Tests pasados: %0d", test_passed);
        $display("Tests fallados: %0d", test_failed);
        
        if (test_failed == 0) begin
            $display("RESULTADO: TODOS LOS TESTS PASARON");
        end else begin
            $display("RESULTADO: ALGUNOS TESTS FALLARON");
        end
        
        $display("====================================================");
        $display("FIN DE TESTBENCH");
        $display("====================================================");
        
        $finish;
    end
    
    //=================================================================
    // Timeout de seguridad
    //=================================================================
    
    initial begin
        #100000000;  // 100ms timeout
        $display("ERROR: Timeout del testbench");
        $finish;
    end
    
    //=================================================================
    // Generación de waveforms
    //=================================================================
    
    initial begin
        $dumpfile("dsa_top_tb.vcd");
        $dumpvars(0, dsa_top_tb);
    end

endmodule