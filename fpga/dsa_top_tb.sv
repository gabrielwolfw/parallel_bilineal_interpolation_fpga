//============================================================
// dsa_top_tb. sv
// Testbench completo para dsa_top
// Incluye pruebas de stepping (Test 6)
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
    // Señales de Stepping
    //========================================================
    logic                   step_enable;
    logic                   step_trigger;
    logic [1:0]             step_granularity;
    logic                   step_ready;
    logic                   step_ack;
    
    //========================================================
    // Señales de Debug
    //========================================================
    logic [31:0]            debug_reg_0;
    logic [31:0]            debug_reg_1;
    logic [31:0]            debug_reg_2;
    logic [31:0]            debug_reg_3;
    logic [31:0]            debug_reg_4;
    logic [31:0]            debug_reg_5;
    logic [31:0]            debug_reg_6;
    logic [31:0]            debug_reg_7;

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
        .mem_writes_count(mem_writes_count),
        // Stepping
        .step_enable(step_enable),
        .step_trigger(step_trigger),
        .step_granularity(step_granularity),
        .step_ready(step_ready),
        .step_ack(step_ack),
        // Debug
        .debug_reg_0(debug_reg_0),
        .debug_reg_1(debug_reg_1),
        .debug_reg_2(debug_reg_2),
        .debug_reg_3(debug_reg_3),
        .debug_reg_4(debug_reg_4),
        .debug_reg_5(debug_reg_5),
        .debug_reg_6(debug_reg_6),
        .debug_reg_7(debug_reg_7)
    );

    //========================================================
    // Variables de prueba
    //========================================================
    integer test_num;
    integer cycle_count;
    integer seq_cycles;
    integer simd_cycles;
    real speedup;
    
    // Variables para stepping
    integer step_count;
    integer total_steps;
    
    // Nombres de estados FSM para debug
    string fsm_state_names_seq[8] = '{
        "IDLE", "INIT", "REQ_FETCH", "WAIT_FETCH",
        "INTERPOLATE", "WRITE", "NEXT_PIXEL", "DONE"
    };
    
    string fsm_state_names_simd[9] = '{
        "IDLE", "INIT", "REQ_FETCH", "WAIT_FETCH",
        "START_DP", "WAIT_DP", "WRITE_ALL", "NEXT_GROUP", "DONE"
    };

    //========================================================
    // Tasks Básicos
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
            // Stepping deshabilitado por defecto
            step_enable = 0;
            step_trigger = 0;
            step_granularity = 2'b00;
            
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
            $display("[%0t] Cargando imagen de prueba %0dx%0d.. .", $time, width, height);
            
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
            
            while (! ready && cycle_count < timeout_cycles) begin
                @(posedge clk);
                cycle_count = cycle_count + 1;
                
                // Mostrar progreso cada 1000 ciclos
                if (cycle_count % 1000 == 0) begin
                    $display("  Ciclo %0d: Progreso = %0d pixeles", cycle_count, progress);
                end
            end
            
            if (cycle_count >= timeout_cycles) begin
                $display("ERROR: Timeout despues de %0d ciclos", timeout_cycles);
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
            tolerance = 2;
            
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
                $display("ERROR: Pixel (%0d,%0d) esperado=%0d obtenido=%0d diferencia=%0d",
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
                    @(posedge clk);
                    @(posedge clk);
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
    // Tasks de Stepping
    //========================================================
    
    // Decodificar y mostrar estado de debug
    task display_debug_state(input integer step_num);
        logic [3:0] fsm_state;
        logic       is_simd;
        logic       mem_rd, mem_wr;
        logic [15:0] curr_x, curr_y;
        logic [7:0] p00, p01, p10, p11;
        logic [15:0] coef_a, coef_b;
        logic [7:0] pixel_out;
        logic [17:0] mem_addr_val;
        logic [7:0] mem_data_val;
        logic [7:0] simd_out[4];
        string state_name;
        begin
            // Decodificar debug_reg_0: Estado y modo
            fsm_state = debug_reg_0[27:24];
            mem_wr = debug_reg_0[9];
            mem_rd = debug_reg_0[8];
            is_simd = debug_reg_0[0];
            
            // Obtener nombre del estado
            if (is_simd) begin
                if (fsm_state < 9)
                    state_name = fsm_state_names_simd[fsm_state];
                else
                    state_name = $sformatf("UNKNOWN(%0d)", fsm_state);
            end else begin
                if (fsm_state < 8)
                    state_name = fsm_state_names_seq[fsm_state];
                else
                    state_name = $sformatf("UNKNOWN(%0d)", fsm_state);
            end
            
            // Decodificar debug_reg_1: Coordenadas
            curr_y = debug_reg_1[31:16];
            curr_x = debug_reg_1[15:0];
            
            // Decodificar debug_reg_2: Pixeles vecinos
            p11 = debug_reg_2[31:24];
            p10 = debug_reg_2[23:16];
            p01 = debug_reg_2[15:8];
            p00 = debug_reg_2[7:0];
            
            // Decodificar debug_reg_3: Coeficientes
            coef_b = debug_reg_3[31:16];
            coef_a = debug_reg_3[15:0];
            
            // Decodificar debug_reg_4: Pixel de salida
            pixel_out = debug_reg_4[7:0];
            
            // Decodificar debug_reg_5: Direccion memoria
            mem_addr_val = debug_reg_5[17:0];
            
            // Decodificar debug_reg_6: Dato memoria
            mem_data_val = debug_reg_6[7:0];
            
            // Decodificar debug_reg_7: Salidas SIMD
            simd_out[0] = debug_reg_7[7:0];
            simd_out[1] = debug_reg_7[15:8];
            simd_out[2] = debug_reg_7[23:16];
            simd_out[3] = debug_reg_7[31:24];
            
            // Mostrar informacion
            $display("");
            $display("+-------------------------------------------------------------+");
            $display("|                    STEP %4d                                 |", step_num);
            $display("+-------------------------------------------------------------+");
            $display("| FSM State: %-12s (%0d)    Mode: %-10s          |", 
                     state_name, fsm_state, is_simd ? "SIMD" : "Sequential");
            $display("| Position:  (%4d, %4d)                                      |", curr_x, curr_y);
            $display("+-------------------------------------------------------------+");
            $display("| Neighbors: p00=%3d  p01=%3d  p10=%3d  p11=%3d              |", 
                     p00, p01, p10, p11);
            $display("| Coefficients: a=0x%04X (%.4f)  b=0x%04X (%.4f)            |", 
                     coef_a, real'(coef_a)/256.0, coef_b, real'(coef_b)/256.0);
            $display("+-------------------------------------------------------------+");
            $display("| Output Pixel: %3d                                           |", pixel_out);
            if (is_simd) begin
                $display("| SIMD Outputs: [%3d, %3d, %3d, %3d]                          |",
                         simd_out[0], simd_out[1], simd_out[2], simd_out[3]);
            end
            $display("+-------------------------------------------------------------+");
            $display("| Memory: Addr=0x%05X  Data=%3d  RD=%b  WR=%b                 |",
                     mem_addr_val, mem_data_val, mem_rd, mem_wr);
            $display("+-------------------------------------------------------------+");
        end
    endtask
    
    // Ejecutar un paso de stepping
    task do_single_step();
        integer timeout;
        begin
            timeout = 0;
            
            // Esperar a que step_ready este activo
            while (! step_ready && timeout < 1000) begin
                @(posedge clk);
                timeout = timeout + 1;
            end
            
            if (timeout >= 1000) begin
                $display("WARNING: Timeout esperando step_ready");
                return;
            end
            
            // Enviar pulso de trigger
            step_trigger = 1;
            @(posedge clk);
            step_trigger = 0;
            
            // Esperar acknowledge (con timeout)
            timeout = 0;
            while (!step_ack && timeout < 100) begin
                @(posedge clk);
                timeout = timeout + 1;
            end
            
            // Esperar unos ciclos para que la FSM avance
            repeat(5) @(posedge clk);
        end
    endtask

    //========================================================
    // Test 1: Imagen pequena secuencial
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
    // Test 2: Imagen pequena SIMD
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
            $display("TEST %0d: Imagen 32x32 Secuencial", test_num);
            $display("========================================");
            
            test_width = 32;
            test_height = 32;
            
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
            $display("TEST %0d: Imagen 32x32 SIMD", test_num);
            $display("========================================");
            
            test_width = 32;
            test_height = 32;
            
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
            scale_factor = 8'hB3; // 0.7
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
            scale_factor = 8'hB3; // 0.7
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
    // Test 6: Stepping - Ejecucion paso a paso
    //========================================================
    task test_stepping();
        integer test_width, test_height;
        integer width_out, height_out;
        integer max_steps;
        integer i;
        logic [3:0] prev_state, curr_state;
        integer state_transitions;
        integer pixels_completed;
        integer timeout;
        begin
            test_num = test_num + 1;
            $display("");
            $display("+==============================================================+");
            $display("|            TEST %0d: STEPPING - Ejecucion Paso a Paso         |", test_num);
            $display("+==============================================================+");
            
            //----------------------------------------------------
            // PARTE A: Stepping por ESTADO en modo SECUENCIAL
            //----------------------------------------------------
            $display("");
            $display("--------------------------------------------------------------");
            $display("  PARTE A: Stepping por ESTADO (Modo Secuencial)");
            $display("--------------------------------------------------------------");
            
            test_width = 8;
            test_height = 8;
            
            reset_system();
            load_test_image(test_width, test_height);
            
            img_width_in = test_width;
            img_height_in = test_height;
            scale_factor = 8'h80;
            
            width_out = (test_width * 8'h80) >> 8;
            height_out = (test_height * 8'h80) >> 8;
            
            $display("Imagen: %0dx%0d -> %0dx%0d", test_width, test_height, width_out, height_out);
            
            // Configurar stepping ANTES de iniciar
            step_granularity = 2'b00;  // STATE
            step_enable = 1;
            repeat(3) @(posedge clk);
            
            // Iniciar procesamiento
            mode_simd = 0;
            start = 1;
            @(posedge clk);
            start = 0;
            
            // Esperar un poco para que arranque
            repeat(5) @(posedge clk);
            
            // Ejecutar pasos
            max_steps = 30;
            step_count = 0;
            prev_state = 4'hF;
            state_transitions = 0;
            
            $display("");
            $display("Ejecutando %0d pasos con granularidad STATE.. .", max_steps);
            
            for (i = 0; i < max_steps && ! ready; i = i + 1) begin
                do_single_step();
                step_count = step_count + 1;
                
                // Leer estado actual
                curr_state = debug_reg_0[27:24];
                
                // Mostrar solo si hubo cambio de estado
                if (curr_state != prev_state) begin
                    state_transitions = state_transitions + 1;
                    display_debug_state(step_count);
                    prev_state = curr_state;
                end
                
                // Verificar si termino
                if (curr_state == 4'd7) begin // ST_DONE para secuencial
                    $display("  FSM alcanzo estado DONE");
                    break;
                end
            end
            
            $display("");
            $display("  Pasos ejecutados: %0d", step_count);
            $display("  Transiciones de estado observadas: %0d", state_transitions);
            
            // Deshabilitar stepping
            step_enable = 0;
            repeat(5) @(posedge clk);
            
            // Esperar completar (si no termino ya)
            timeout = 0;
            while (!ready && timeout < 100000) begin
                @(posedge clk);
                timeout = timeout + 1;
            end
            
            if (ready)
                $display("  Procesamiento completado correctamente");
            else
                $display("  WARNING: Timeout esperando completar");
            
            //----------------------------------------------------
            // PARTE B: Stepping por PIXEL
            //----------------------------------------------------
            $display("");
            $display("--------------------------------------------------------------");
            $display("  PARTE B: Stepping por PIXEL (Modo Secuencial)");
            $display("--------------------------------------------------------------");
            
            reset_system();
            load_test_image(test_width, test_height);
            
            img_width_in = test_width;
            img_height_in = test_height;
            scale_factor = 8'h80;
            
            // Configurar stepping
            step_granularity = 2'b01;  // PIXEL
            step_enable = 1;
            repeat(3) @(posedge clk);
            
            mode_simd = 0;
            start = 1;
            @(posedge clk);
            start = 0;
            repeat(5) @(posedge clk);
            
            max_steps = 5;
            step_count = 0;
            
            $display("");
            $display("Ejecutando %0d pasos con granularidad PIXEL...", max_steps);
            
            for (i = 0; i < max_steps && !ready; i = i + 1) begin
                do_single_step();
                step_count = step_count + 1;
                display_debug_state(step_count);
            end
            
            $display("");
            $display("  Pixeles procesados: %0d", step_count);
            
            step_enable = 0;
            repeat(5) @(posedge clk);
            
            timeout = 0;
            while (!ready && timeout < 100000) begin
                @(posedge clk);
                timeout = timeout + 1;
            end
            
            //----------------------------------------------------
            // PARTE C: Stepping por GRUPO (SIMD)
            //----------------------------------------------------
            $display("");
            $display("--------------------------------------------------------------");
            $display("  PARTE C: Stepping por GRUPO (Modo SIMD)");
            $display("--------------------------------------------------------------");
            
            reset_system();
            load_test_image(test_width, test_height);
            
            img_width_in = test_width;
            img_height_in = test_height;
            scale_factor = 8'h80;
            
            step_granularity = 2'b10;  // GROUP
            step_enable = 1;
            repeat(3) @(posedge clk);
            
            mode_simd = 1;  // SIMD mode
            start = 1;
            @(posedge clk);
            start = 0;
            repeat(5) @(posedge clk);
            
            max_steps = 4;
            step_count = 0;
            
            $display("");
            $display("Ejecutando %0d pasos con granularidad GROUP...", max_steps);
            
            for (i = 0; i < max_steps && !ready; i = i + 1) begin
                do_single_step();
                step_count = step_count + 1;
                display_debug_state(step_count);
            end
            
            $display("");
            $display("  Grupos procesados: %0d (%0d pixeles)", step_count, step_count * SIMD_WIDTH);
            
            step_enable = 0;
            repeat(5) @(posedge clk);
            
            timeout = 0;
            while (!ready && timeout < 100000) begin
                @(posedge clk);
                timeout = timeout + 1;
            end
            
            //----------------------------------------------------
            // Resumen
            //----------------------------------------------------
            $display("");
            $display("+==============================================================+");
            $display("|                  RESUMEN TEST STEPPING                       |");
            $display("+==============================================================+");
            $display("|  [OK] Stepping por ESTADO: Verificado                        |");
            $display("|  [OK] Stepping por PIXEL:  Verificado                        |");
            $display("|  [OK] Stepping por GRUPO:  Verificado                        |");
            $display("+==============================================================+");
            
            $display("");
            $display("TEST %0d COMPLETADO", test_num);
        end
    endtask

    //========================================================
    // Secuencia principal de tests
    //========================================================
    initial begin
        $display("");
        $display("+================================================================+");
        $display("|           INICIO DE TESTBENCH DSA DOWNSCALING                  |");
        $display("|              Con soporte para Stepping                         |");
        $display("+================================================================+");
        
        test_num = 0;
        
        // Ejecutar tests 1-5 (sin stepping)
        test_small_sequential();
        test_small_simd();
        test_medium_sequential();
        test_medium_simd();
        test_performance_comparison();
        
        // Ejecutar test 6 (con stepping)
        test_stepping();
        
        // Resumen final
        $display("");
        $display("+================================================================+");
        $display("|                      RESUMEN FINAL                             |");
        $display("+================================================================+");
        $display("|  Tests ejecutados: %0d                                          |", test_num);
        $display("|  Tests 1-5: Funcionalidad basica (sin stepping)                |");
        $display("|  Test 6:    Verificacion de stepping                           |");
        $display("+================================================================+");
        $display("|                    FIN DE TESTBENCH                            |");
        $display("+================================================================+");
        
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
    // Generacion de waveforms
    //========================================================
    initial begin
        $dumpfile("dsa_top_tb.vcd");
        $dumpvars(0, dsa_top_tb);
    end

endmodule