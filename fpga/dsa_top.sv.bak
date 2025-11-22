//============================================================
// dsa_top.sv
// Módulo Top para DSA Downscaling con Interpolación Bilineal
// Soporta modo secuencial y SIMD
//============================================================

module dsa_top #(
    parameter IMG_WIDTH_MAX  = 512,
    parameter IMG_HEIGHT_MAX = 512,
    parameter MEM_SIZE       = 262144,
    parameter SIMD_WIDTH     = 4
)(
    input  logic        clk,
    input  logic        rst,
    
    // Interfaz de control desde host (JTAG/UART)
    input  logic        start,
    input  logic        mode_simd,           // 0: secuencial, 1: SIMD
    input  logic [9:0]  img_width_in,        // Ancho imagen entrada
    input  logic [9:0]  img_height_in,       // Alto imagen entrada
    input  logic [7:0]  scale_factor,        // Factor escala Q8.8 (ej: 0x80 = 0.5)
    
    // Interfaz de memoria (carga/descarga imágenes)
    input  logic        mem_write_en,
    input  logic        mem_read_en,
    input  logic [17:0] mem_addr,
    input  logic [7:0]  mem_data_in,
    output logic [7:0]  mem_data_out,
    
    // Registros de estado
    output logic        busy,
    output logic        ready,
    output logic        error,
    output logic [15:0] progress,            // Píxeles procesados
    
    // Performance counters
    output logic [31:0] flops_count,
    output logic [31:0] mem_reads_count,
    output logic [31:0] mem_writes_count
);

    //=================================================================
    // Señales internas
    //=================================================================
    
    // Dimensiones imagen salida
    logic [9:0]  img_width_out;
    logic [9:0]  img_height_out;
    logic [15:0] total_pixels_out;
    
    // Control FSM
    logic        fsm_start;
    logic        fsm_busy;
    logic        fsm_ready;
    logic        fsm_next_pixel;
    logic [15:0] fsm_pixel_index;
    
    // Datapath secuencial
    logic        dp_seq_start;
    logic [7:0]  dp_seq_p00, dp_seq_p01, dp_seq_p10, dp_seq_p11;
    logic [15:0] dp_seq_a, dp_seq_b;
    logic [7:0]  dp_seq_pixel_out;
    logic        dp_seq_done;
    
    // Datapath SIMD
    logic        dp_simd_start;
    logic [7:0]  dp_simd_p00 [0:SIMD_WIDTH-1];
    logic [7:0]  dp_simd_p01 [0:SIMD_WIDTH-1];
    logic [7:0]  dp_simd_p10 [0:SIMD_WIDTH-1];
    logic [7:0]  dp_simd_p11 [0:SIMD_WIDTH-1];
    logic [15:0] dp_simd_a   [0:SIMD_WIDTH-1];
    logic [15:0] dp_simd_b   [0:SIMD_WIDTH-1];
    logic [7:0]  dp_simd_pixel_out [0:SIMD_WIDTH-1];
    logic        dp_simd_done;
    
    // SIMD registers
    logic        simd_reg_load_en;
    logic [7:0]  simd_reg_out_p00 [0:SIMD_WIDTH-1];
    logic [7:0]  simd_reg_out_p01 [0:SIMD_WIDTH-1];
    logic [7:0]  simd_reg_out_p10 [0:SIMD_WIDTH-1];
    logic [7:0]  simd_reg_out_p11 [0:SIMD_WIDTH-1];
    
    // Memoria interna
    logic        mem_int_read_en;
    logic        mem_int_write_en;
    logic [17:0] mem_int_addr;
    logic [7:0]  mem_int_data_in;
    logic [7:0]  mem_int_data_out;
    
    // Coordenadas actuales en imagen de salida
    logic [9:0]  out_x, out_y;
    
    // Coordenadas mapeadas en imagen de entrada (Q8.8)
    logic [25:0] src_x_fixed, src_y_fixed;  // 10 bits entero + 16 bits fracción
    logic [9:0]  src_x_int, src_y_int;
    logic [15:0] frac_x, frac_y;            // Parte fraccionaria Q8.8
    
    // Estado interno de procesamiento
    typedef enum logic [3:0] {
        ST_IDLE,
        ST_CALC_PARAMS,
        ST_FETCH_PIXELS,
        ST_INTERPOLATE,
        ST_WRITE_RESULT,
        ST_NEXT,
        ST_DONE,
        ST_ERROR
    } proc_state_t;
    
    proc_state_t proc_state, proc_next_state;
    
    //=================================================================
    // Cálculo de dimensiones de salida
    //=================================================================
    
    always_comb begin
        // scale_factor en Q8.8: 0x80 = 0.5, 0xFF = ~1.0
        img_width_out  = (img_width_in * scale_factor) >> 8;
        img_height_out = (img_height_in * scale_factor) >> 8;
        total_pixels_out = img_width_out * img_height_out;
    end
    
    //=================================================================
    // Máquina de estados de procesamiento
    //=================================================================
    
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            proc_state <= ST_IDLE;
            out_x <= 0;
            out_y <= 0;
        end else begin
            proc_state <= proc_next_state;
            
            if (proc_state == ST_CALC_PARAMS && proc_next_state == ST_FETCH_PIXELS) begin
                // Mantener coordenadas
            end else if (proc_state == ST_WRITE_RESULT && proc_next_state == ST_NEXT) begin
                // Avanzar coordenadas
                if (out_x + (mode_simd ? SIMD_WIDTH : 1) < img_width_out) begin
                    out_x <= out_x + (mode_simd ? SIMD_WIDTH : 1);
                end else begin
                    out_x <= 0;
                    out_y <= out_y + 1;
                end
            end else if (proc_state == ST_IDLE && start) begin
                out_x <= 0;
                out_y <= 0;
            end
        end
    end
    
    always_comb begin
        proc_next_state = proc_state;
        
        case (proc_state)
            ST_IDLE: begin
                if (start)
                    proc_next_state = ST_CALC_PARAMS;
            end
            
            ST_CALC_PARAMS: begin
                proc_next_state = ST_FETCH_PIXELS;
            end
            
            ST_FETCH_PIXELS: begin
                proc_next_state = ST_INTERPOLATE;
            end
            
            ST_INTERPOLATE: begin
                if (mode_simd && dp_simd_done)
                    proc_next_state = ST_WRITE_RESULT;
                else if (!mode_simd && dp_seq_done)
                    proc_next_state = ST_WRITE_RESULT;
            end
            
            ST_WRITE_RESULT: begin
                proc_next_state = ST_NEXT;
            end
            
            ST_NEXT: begin
                if (out_y >= img_height_out)
                    proc_next_state = ST_DONE;
                else
                    proc_next_state = ST_CALC_PARAMS;
            end
            
            ST_DONE: begin
                proc_next_state = ST_IDLE;
            end
            
            default: proc_next_state = ST_IDLE;
        endcase
    end
    
    //=================================================================
    // Cálculo de coordenadas en imagen fuente
    //=================================================================
    
    logic [25:0] inv_scale_fixed;  // 1/scale_factor en Q8.8
    
    always_comb begin
        // Aproximación: inv_scale = 256*256 / scale_factor
        if (scale_factor != 0)
            inv_scale_fixed = (26'd65536 / scale_factor);
        else
            inv_scale_fixed = 26'd65536;
        
        // Mapeo: src = dst * (1/scale)
        src_x_fixed = out_x * inv_scale_fixed;
        src_y_fixed = out_y * inv_scale_fixed;
        
        // Separar parte entera y fraccionaria
        src_x_int = src_x_fixed[25:16];
        src_y_int = src_y_fixed[25:16];
        frac_x    = src_x_fixed[15:0];
        frac_y    = src_y_fixed[15:0];
    end
    
    //=================================================================
    // Lógica de fetch de píxeles vecinos
    //=================================================================
    
    logic [17:0] addr_p00, addr_p01, addr_p10, addr_p11;
    logic [3:0]  fetch_counter;
    
    always_comb begin
        // Direcciones de los 4 píxeles vecinos
        addr_p00 = src_y_int * img_width_in + src_x_int;
        addr_p01 = src_y_int * img_width_in + (src_x_int + 1);
        addr_p10 = (src_y_int + 1) * img_width_in + src_x_int;
        addr_p11 = (src_y_int + 1) * img_width_in + (src_x_int + 1);
    end
    
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            fetch_counter <= 0;
            dp_seq_p00 <= 0;
            dp_seq_p01 <= 0;
            dp_seq_p10 <= 0;
            dp_seq_p11 <= 0;
        end else if (proc_state == ST_FETCH_PIXELS) begin
            case (fetch_counter)
                0: begin
                    mem_int_addr <= addr_p00;
                    mem_int_read_en <= 1;
                    fetch_counter <= 1;
                end
                1: begin
                    dp_seq_p00 <= mem_int_data_out;
                    mem_int_addr <= addr_p01;
                    fetch_counter <= 2;
                end
                2: begin
                    dp_seq_p01 <= mem_int_data_out;
                    mem_int_addr <= addr_p10;
                    fetch_counter <= 3;
                end
                3: begin
                    dp_seq_p10 <= mem_int_data_out;
                    mem_int_addr <= addr_p11;
                    fetch_counter <= 4;
                end
                4: begin
                    dp_seq_p11 <= mem_int_data_out;
                    mem_int_read_en <= 0;
                    fetch_counter <= 0;
                end
            endcase
        end else begin
            fetch_counter <= 0;
            mem_int_read_en <= 0;
        end
    end
    
    //=================================================================
    // Control de datapaths
    //=================================================================
    
    always_comb begin
        dp_seq_start = (proc_state == ST_INTERPOLATE) && !mode_simd;
        dp_simd_start = (proc_state == ST_INTERPOLATE) && mode_simd;
        
        dp_seq_a = frac_x[15:8];  // Convertir a Q8.8
        dp_seq_b = frac_y[15:8];
    end
    
    //=================================================================
    // Escritura de resultados
    //=================================================================
    
    logic [17:0] write_addr_base;
    logic [3:0]  write_counter;
    
    always_comb begin
        write_addr_base = MEM_SIZE/2 + (out_y * img_width_out + out_x);
    end
    
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            write_counter <= 0;
        end else if (proc_state == ST_WRITE_RESULT) begin
            if (!mode_simd) begin
                mem_int_addr <= write_addr_base;
                mem_int_data_in <= dp_seq_pixel_out;
                mem_int_write_en <= 1;
                write_counter <= 0;
            end else begin
                if (write_counter < SIMD_WIDTH) begin
                    mem_int_addr <= write_addr_base + write_counter;
                    mem_int_data_in <= dp_simd_pixel_out[write_counter];
                    mem_int_write_en <= 1;
                    write_counter <= write_counter + 1;
                end else begin
                    mem_int_write_en <= 0;
                    write_counter <= 0;
                end
            end
        end else begin
            mem_int_write_en <= 0;
            write_counter <= 0;
        end
    end
    
    //=================================================================
    // Performance counters
    //=================================================================
    
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            flops_count <= 0;
            mem_reads_count <= 0;
            mem_writes_count <= 0;
        end else begin
            if (proc_state == ST_INTERPOLATE) begin
                if (mode_simd)
                    flops_count <= flops_count + (SIMD_WIDTH * 8); // 8 ops por pixel
                else
                    flops_count <= flops_count + 8;
            end
            
            if (mem_int_read_en)
                mem_reads_count <= mem_reads_count + 1;
            
            if (mem_int_write_en)
                mem_writes_count <= mem_writes_count + 1;
        end
    end
    
    //=================================================================
    // Señales de estado
    //=================================================================
    
    assign busy = (proc_state != ST_IDLE) && (proc_state != ST_DONE);
    assign ready = (proc_state == ST_DONE);
    assign error = (proc_state == ST_ERROR);
    assign progress = out_y * img_width_out + out_x;
    
    //=================================================================
    // Instanciación de módulos
    //=================================================================
    
    // Memoria interna
    dsa_mem_interface #(
        .MEM_SIZE(MEM_SIZE)
    ) mem_inst (
        .clk(clk),
        .read_en(mem_read_en || mem_int_read_en),
        .write_en(mem_write_en || mem_int_write_en),
        .addr(mem_write_en || mem_read_en ? mem_addr : mem_int_addr),
        .data_in(mem_write_en ? mem_data_in : mem_int_data_in),
        .data_out(mem_data_out)
    );
    
    assign mem_int_data_out = mem_data_out;
    
    // Datapath secuencial
    dsa_datapath dp_seq (
        .clk(clk),
        .rst(rst),
        .start(dp_seq_start),
        .p00(dp_seq_p00),
        .p01(dp_seq_p01),
        .p10(dp_seq_p10),
        .p11(dp_seq_p11),
        .a(dp_seq_a),
        .b(dp_seq_b),
        .pixel_out(dp_seq_pixel_out),
        .done(dp_seq_done)
    );
    
    // Datapath SIMD
    dsa_datapath_simd #(
        .N(SIMD_WIDTH)
    ) dp_simd (
        .clk(clk),
        .rst(rst),
        .start(dp_simd_start),
        .p00(dp_simd_p00),
        .p01(dp_simd_p01),
        .p10(dp_simd_p10),
        .p11(dp_simd_p11),
        .a(dp_simd_a),
        .b(dp_simd_b),
        .pixel_out(dp_simd_pixel_out),
        .done(dp_simd_done)
    );
    
    // SIMD registers
    dsa_simd_registers #(
        .N(SIMD_WIDTH)
    ) simd_regs (
        .clk(clk),
        .rst(rst),
        .load_en(simd_reg_load_en),
        .in_p00(dp_simd_p00),
        .in_p01(dp_simd_p01),
        .in_p10(dp_simd_p10),
        .in_p11(dp_simd_p11),
        .out_p00(simd_reg_out_p00),
        .out_p01(simd_reg_out_p01),
        .out_p10(simd_reg_out_p10),
        .out_p11(simd_reg_out_p11)
    );

endmodule