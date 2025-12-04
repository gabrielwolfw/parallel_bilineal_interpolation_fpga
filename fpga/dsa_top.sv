//============================================================
// dsa_top.sv - VERSIÓN CON STEPPING CORREGIDO
//============================================================

module dsa_top #(
    parameter ADDR_WIDTH = 18,
    parameter IMG_WIDTH  = 512,
    parameter IMG_HEIGHT = 512,
    parameter SIMD_WIDTH = 4,
    parameter MEM_SIZE   = 262144
)(
    input  logic                   clk,
    input  logic                   rst,
    input  logic                   start,
    input  logic                   mode_simd,
    input  logic [15:0]            img_width_in,
    input  logic [15:0]            img_height_in,
    input  logic [7:0]             scale_factor,
    input  logic                   ext_mem_write_en,
    input  logic                   ext_mem_read_en,
    input  logic [ADDR_WIDTH-1:0]  ext_mem_addr,
    input  logic [7:0]             ext_mem_data_in,
    output logic [7:0]             ext_mem_data_out,
    output logic                   busy,
    output logic                   ready,
    output logic [15:0]            progress,
    output logic [31:0]            flops_count,
    output logic [31:0]            mem_reads_count,
    output logic [31:0]            mem_writes_count,
    
    // Stepping
    input  logic                   step_enable,
    input  logic                   step_trigger,
    input  logic [1:0]             step_granularity,
    output logic                   step_ready,
    output logic                   step_ack,
    
    // Debug registers
    output logic [31:0]            debug_reg_0,
    output logic [31:0]            debug_reg_1,
    output logic [31:0]            debug_reg_2,
    output logic [31:0]            debug_reg_3,
    output logic [31:0]            debug_reg_4,
    output logic [31:0]            debug_reg_5,
    output logic [31:0]            debug_reg_6,
    output logic [31:0]            debug_reg_7
);

    //========================================================
    // Señales de stepping
    //========================================================
    logic        fsm_hold;
    logic        pixel_complete_seq;
    logic        pixel_complete_simd;
    logic        pixel_complete;
    logic        group_complete;
    
    //========================================================
    // Estados FSM para debug - CORREGIDO: una sola declaración
    //========================================================
    logic [3:0]  fsm_state_seq_out;    // Salida de FSM secuencial
    logic [3:0]  fsm_state_simd_out;   // Salida de FSM SIMD

    //========================================================
    // Cálculo de dimensiones de salida
    //========================================================
    logic [15:0] img_width_out;
    logic [15:0] img_height_out;
    
    assign img_width_out = (({16'd0, img_width_in} * {24'd0, scale_factor}) >> 8);
    assign img_height_out = (({16'd0, img_height_in} * {24'd0, scale_factor}) >> 8);
    
    //========================================================
    // Señales de control FSM secuencial
    //========================================================
    logic        seq_enable;
    logic        seq_fetch_req;
    logic        seq_fetch_done;
    logic        seq_dp_start;
    logic        seq_dp_done;
    logic        seq_write_enable;
    logic [15:0] seq_current_x;
    logic [15:0] seq_current_y;
    logic        seq_busy;
    logic        seq_ready;
    
    //========================================================
    // Señales de control FSM SIMD
    //========================================================
    logic        simd_enable;
    logic        simd_fetch_req;
    logic        simd_fetch_done;
    logic        simd_dp_start;
    logic        simd_dp_done;
    logic        simd_write_enable;
    logic        simd_parallel_write;
    logic [15:0] simd_current_x;
    logic [15:0] simd_current_y;
    logic        simd_busy;
    logic        simd_ready;
    
    assign simd_parallel_write = mode_simd && simd_write_enable;
    
    // Detectar píxel/grupo completado para stepping
    assign pixel_complete_seq = seq_write_enable;
    assign pixel_complete_simd = simd_write_enable;
    assign pixel_complete = mode_simd ?  pixel_complete_simd : pixel_complete_seq;
    assign group_complete = simd_write_enable;
    
    //========================================================
    // Multiplexor de señales activas según modo
    //========================================================
    logic        active_fetch_req;
    logic        active_dp_start;
    logic        active_write_enable;
    logic [15:0] active_x;
    logic [15:0] active_y;
    
    assign active_fetch_req = mode_simd ?  simd_fetch_req : seq_fetch_req;
    assign active_dp_start = mode_simd ? simd_dp_start : seq_dp_start;
    assign active_write_enable = mode_simd ? simd_write_enable : seq_write_enable;
    assign active_x = mode_simd ? simd_current_x : seq_current_x;
    assign active_y = mode_simd ? simd_current_y : seq_current_y;
    
    //========================================================
    // Control de habilitación de FSMs (con soporte stepping)
    //========================================================
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            seq_enable <= 1'b0;
            simd_enable <= 1'b0;
        end else if (fsm_hold) begin
            // Cuando está en hold, mantener estado actual
            // No hacer nada - mantener enables
        end else if (start) begin
            seq_enable <= ~mode_simd;
            simd_enable <= mode_simd;
        end else if (seq_ready || simd_ready) begin
            seq_enable <= 1'b0;
            simd_enable <= 1'b0;
        end
    end
    
    //========================================================
    // Señales de fetch
    //========================================================
    logic        fetch_mem_read_en;
    logic [ADDR_WIDTH-1:0] fetch_mem_addr;
    
    logic        seq_fetch_valid;
    logic [7:0]  seq_p00, seq_p01, seq_p10, seq_p11;
    logic [15:0] seq_a, seq_b;
    logic        seq_fetch_busy;
    
    logic [15:0] seq_src_x_int;
    logic [15:0] seq_src_y_int;
    logic [15:0] seq_frac_x;
    logic [15:0] seq_frac_y;
    
    // Señales SIMD
    logic        simd_fetch_valid;
    logic [7:0]  simd_p00_0, simd_p00_1, simd_p00_2, simd_p00_3;
    logic [7:0]  simd_p01_0, simd_p01_1, simd_p01_2, simd_p01_3;
    logic [7:0]  simd_p10_0, simd_p10_1, simd_p10_2, simd_p10_3;
    logic [7:0]  simd_p11_0, simd_p11_1, simd_p11_2, simd_p11_3;
    logic [15:0] simd_a_0, simd_a_1, simd_a_2, simd_a_3;
    logic [15:0] simd_b_0, simd_b_1, simd_b_2, simd_b_3;
    logic        simd_fetch_busy;
    
    assign seq_fetch_done = seq_fetch_valid;
    assign simd_fetch_done = simd_fetch_valid;
    
    //========================================================
    // CÁLCULO DE COORDENADAS FUENTE PARA Q8. 8
    //========================================================
    logic [31:0] inv_scale_q8_8;
    assign inv_scale_q8_8 = (scale_factor != 8'd0) ? 
                            (32'd65536 / {24'd0, scale_factor}) : 
                            32'd256;
    
    logic [31:0] src_x_full, src_y_full;
    assign src_x_full = active_x * inv_scale_q8_8;
    assign src_y_full = active_y * inv_scale_q8_8;
    
    assign seq_src_x_int = src_x_full[23:8];
    assign seq_src_y_int = src_y_full[23:8];
    assign seq_frac_x = {src_x_full[7:0], 8'd0};
    assign seq_frac_y = {src_y_full[7:0], 8'd0};
    
    //========================================================
    // Datapath secuencial
    //========================================================
    logic [7:0]  dp_seq_pixel_out;
    logic        dp_seq_done;
    
    //========================================================
    // Datapath SIMD
    //========================================================
    logic [7:0]  dp_simd_p00 [0:SIMD_WIDTH-1];
    logic [7:0]  dp_simd_p01 [0:SIMD_WIDTH-1];
    logic [7:0]  dp_simd_p10 [0:SIMD_WIDTH-1];
    logic [7:0]  dp_simd_p11 [0:SIMD_WIDTH-1];
    logic [15:0] dp_simd_a   [0:SIMD_WIDTH-1];
    logic [15:0] dp_simd_b   [0:SIMD_WIDTH-1];
    logic [7:0]  dp_simd_pixel_out [0:SIMD_WIDTH-1];
    logic        dp_simd_done;
    
    assign dp_simd_p00[0] = simd_p00_0;
    assign dp_simd_p00[1] = simd_p00_1;
    assign dp_simd_p00[2] = simd_p00_2;
    assign dp_simd_p00[3] = simd_p00_3;
    assign dp_simd_p01[0] = simd_p01_0;
    assign dp_simd_p01[1] = simd_p01_1;
    assign dp_simd_p01[2] = simd_p01_2;
    assign dp_simd_p01[3] = simd_p01_3;
    assign dp_simd_p10[0] = simd_p10_0;
    assign dp_simd_p10[1] = simd_p10_1;
    assign dp_simd_p10[2] = simd_p10_2;
    assign dp_simd_p10[3] = simd_p10_3;
    assign dp_simd_p11[0] = simd_p11_0;
    assign dp_simd_p11[1] = simd_p11_1;
    assign dp_simd_p11[2] = simd_p11_2;
    assign dp_simd_p11[3] = simd_p11_3;
    assign dp_simd_a[0] = simd_a_0;
    assign dp_simd_a[1] = simd_a_1;
    assign dp_simd_a[2] = simd_a_2;
    assign dp_simd_a[3] = simd_a_3;
    assign dp_simd_b[0] = simd_b_0;
    assign dp_simd_b[1] = simd_b_1;
    assign dp_simd_b[2] = simd_b_2;
    assign dp_simd_b[3] = simd_b_3;
    
    assign seq_dp_done = dp_seq_done;
    
    //========================================================
    // REGISTROS DE ALINEACIÓN SIMD
    //========================================================
    logic [7:0]  dp_simd_pixel_latched [0:SIMD_WIDTH-1];
    logic        dp_simd_done_latched;
    
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            dp_simd_done_latched <= 1'b0;
            for (int i = 0; i < SIMD_WIDTH; i++) begin
                dp_simd_pixel_latched[i] <= 8'd0;
            end
        end else begin
            dp_simd_done_latched <= dp_simd_done;
            
            if (dp_simd_done) begin
                for (int i = 0; i < SIMD_WIDTH; i++) begin
                    dp_simd_pixel_latched[i] <= dp_simd_pixel_out[i];
                end
            end
        end
    end
    
    assign simd_dp_done = dp_simd_done_latched;
    
    //========================================================
    // Escritura a memoria de salida
    //========================================================
    logic                   int_mem_write_en;
    logic [ADDR_WIDTH-1:0]  int_mem_addr;
    logic [7:0]             int_mem_data_in;
    logic [7:0]             mem_data_out;
    
    logic [31:0] write_base_addr_full;
    logic [ADDR_WIDTH-1:0] write_base_addr;
    
    assign write_base_addr_full = (MEM_SIZE/2) + ({16'd0, active_y} * {16'd0, img_width_out}) + {16'd0, active_x};
    assign write_base_addr = write_base_addr_full[ADDR_WIDTH-1:0];
    
    assign int_mem_write_en = seq_write_enable && ! mode_simd;
    assign int_mem_addr = write_base_addr;
    assign int_mem_data_in = dp_seq_pixel_out;
    
    //========================================================
    // Performance counters
    //========================================================
    logic dp_start_prev;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            flops_count <= 32'd0;
            mem_reads_count <= 32'd0;
            mem_writes_count <= 32'd0;
            dp_start_prev <= 1'b0;
        end else begin
            dp_start_prev <= active_dp_start;
            
            if (active_dp_start && ! dp_start_prev) begin
                flops_count <= flops_count + (mode_simd ? (SIMD_WIDTH * 32'd8) : 32'd8);
            end
            
            if (fetch_mem_read_en || ext_mem_read_en)
                mem_reads_count <= mem_reads_count + 32'd1;
            
            if (simd_parallel_write)
                mem_writes_count <= mem_writes_count + 32'd4;
            else if (int_mem_write_en || ext_mem_write_en)
                mem_writes_count <= mem_writes_count + 32'd1;
        end
    end
    
    //========================================================
    // Señales de estado
    //========================================================
    logic [31:0] progress_full;
    
    assign busy = mode_simd ? simd_busy : seq_busy;
    assign ready = mode_simd ? simd_ready : seq_ready;
    
    assign progress_full = ({16'd0, active_y} * {16'd0, img_width_out}) + {16'd0, active_x};
    assign progress = progress_full[15:0];
    
    //========================================================
    // MULTIPLEXOR DE MEMORIA
    //========================================================
    logic                   final_mem_read_en;
    logic                   final_mem_write_en;
    logic [ADDR_WIDTH-1:0]  final_mem_addr;
    logic [7:0]             final_mem_data_in;
    
    logic external_access;
    assign external_access = ext_mem_write_en || ext_mem_read_en;
    
    always_comb begin
        if (external_access) begin
            final_mem_read_en  = ext_mem_read_en;
            final_mem_write_en = ext_mem_write_en;
            final_mem_addr     = ext_mem_addr;
            final_mem_data_in  = ext_mem_data_in;
        end else if (int_mem_write_en) begin
            final_mem_read_en  = 1'b0;
            final_mem_write_en = 1'b1;
            final_mem_addr     = int_mem_addr;
            final_mem_data_in  = int_mem_data_in;
        end else if (fetch_mem_read_en) begin
            final_mem_read_en  = 1'b1;
            final_mem_write_en = 1'b0;
            final_mem_addr     = fetch_mem_addr;
            final_mem_data_in  = 8'd0;
        end else begin
            final_mem_read_en  = 1'b0;
            final_mem_write_en = 1'b0;
            final_mem_addr     = '0;
            final_mem_data_in  = 8'd0;
        end
    end
    
    //========================================================
    // INSTANCIA: Step Controller
    //========================================================
    dsa_step_controller step_ctrl (
        .clk              (clk),
        .rst              (rst),
        .step_enable      (step_enable),
        .step_trigger     (step_trigger),
        . step_granularity (step_granularity),
        . fsm_state_seq    (fsm_state_seq_out),   // ← Conectar salida de FSM seq
        .fsm_state_simd   (fsm_state_simd_out),  // ← Conectar salida de FSM simd
        .mode_simd        (mode_simd),
        .pixel_complete   (pixel_complete),
        . group_complete   (group_complete),
        .fsm_hold         (fsm_hold),            // ← Salida hacia FSMs
        .step_ack         (step_ack),
        .step_ready       (step_ready)
    );
    
    //========================================================
    // INSTANCIA: Debug Registers
    //========================================================
    dsa_debug_registers #(
        . ADDR_WIDTH (ADDR_WIDTH),
        . SIMD_WIDTH (SIMD_WIDTH)
    ) debug_regs (
        .clk            (clk),
        .rst            (rst),
        . fsm_state_seq  (fsm_state_seq_out),   // ← Usar misma señal
        .fsm_state_simd (fsm_state_simd_out),  // ← Usar misma señal
        . mode_simd      (mode_simd),
        .current_x      (active_x),
        .current_y      (active_y),
        .seq_p00        (seq_p00),
        .seq_p01        (seq_p01),
        .seq_p10        (seq_p10),
        . seq_p11        (seq_p11),
        .coef_a         (seq_a),
        .coef_b         (seq_b),
        . pixel_out_seq  (dp_seq_pixel_out),
        .pixel_out_simd (dp_simd_pixel_out),
        .mem_addr       (final_mem_addr),
        .mem_data       (mem_data_out),
        .mem_read_en    (final_mem_read_en),
        .mem_write_en   (final_mem_write_en),
        .capture_enable (step_enable),
        . step_ack       (step_ack),
        .debug_reg_0    (debug_reg_0),
        . debug_reg_1    (debug_reg_1),
        .debug_reg_2    (debug_reg_2),
        .debug_reg_3    (debug_reg_3),
        .debug_reg_4    (debug_reg_4),
        .debug_reg_5    (debug_reg_5),
        . debug_reg_6    (debug_reg_6),
        .debug_reg_7    (debug_reg_7)
    );
    
    //========================================================
    // INSTANCIA: FSM Secuencial - CORREGIDO con coma
    //========================================================
    dsa_control_fsm_sequential #(
        .IMG_WIDTH_MAX  (IMG_WIDTH),
        .IMG_HEIGHT_MAX (IMG_HEIGHT)
    ) fsm_seq (
        .clk            (clk),
        .rst            (rst),
        .enable         (seq_enable),
        .hold           (fsm_hold),              // ← Entrada de hold
        .img_width_out  (img_width_out),
        .img_height_out (img_height_out),
        .fetch_req      (seq_fetch_req),
        .fetch_done     (seq_fetch_done),
        . dp_start       (seq_dp_start),
        .dp_done        (seq_dp_done),
        .write_enable   (seq_write_enable),
        .current_x      (seq_current_x),
        .current_y      (seq_current_y),
        .busy           (seq_busy),
        .ready          (seq_ready),
        .state_out      (fsm_state_seq_out)      // ← CORREGIDO: con coma antes
    );
    
    //========================================================
    // INSTANCIA: FSM SIMD - CORREGIDO con coma
    //========================================================
    dsa_control_fsm_simd #(
        .IMG_WIDTH_MAX  (IMG_WIDTH),
        .IMG_HEIGHT_MAX (IMG_HEIGHT),
        .SIMD_WIDTH     (SIMD_WIDTH)
    ) fsm_simd (
        .clk            (clk),
        .rst            (rst),
        .enable         (simd_enable),
        .hold           (fsm_hold),              // ← Entrada de hold
        . img_width_out  (img_width_out),
        .img_height_out (img_height_out),
        .fetch_req      (simd_fetch_req),
        .fetch_done     (simd_fetch_done),
        .dp_start       (simd_dp_start),
        .dp_done        (simd_dp_done),
        .simd_write_en  (simd_write_enable),
        .current_x      (simd_current_x),
        .current_y      (simd_current_y),
        .busy           (simd_busy),
        . ready          (simd_ready),
        .state_out      (fsm_state_simd_out)     // ← CORREGIDO: con coma antes
    );
    
    //========================================================
    // INSTANCIA: Fetch Unificado
    //========================================================
    dsa_pixel_fetch_unified #(
        . ADDR_WIDTH (ADDR_WIDTH),
        . SIMD_WIDTH (SIMD_WIDTH)
    ) fetch_unit (
        .clk             (clk),
        .rst             (rst),
        . mode_simd       (mode_simd),
        .req_valid       (active_fetch_req),
        .img_width       (img_width_in),
        .img_height      (img_height_in),
        .seq_src_x_int   (seq_src_x_int),
        .seq_src_y_int   (seq_src_y_int),
        .seq_frac_x      (seq_frac_x),
        . seq_frac_y      (seq_frac_y),
        .simd_base_x     (active_x),
        .simd_base_y     (active_y),
        .scale_factor    (scale_factor),
        .img_base_addr   ('0),
        . mem_read_en     (fetch_mem_read_en),
        . mem_addr        (fetch_mem_addr),
        .mem_data        (mem_data_out),
        .seq_fetch_valid (seq_fetch_valid),
        . seq_p00         (seq_p00),
        .seq_p01         (seq_p01),
        .seq_p10         (seq_p10),
        .seq_p11         (seq_p11),
        .seq_a           (seq_a),
        .seq_b           (seq_b),
        . seq_busy        (seq_fetch_busy),
        .simd_fetch_valid(simd_fetch_valid),
        . simd_p00_0      (simd_p00_0),
        . simd_p00_1      (simd_p00_1),
        . simd_p00_2      (simd_p00_2),
        . simd_p00_3      (simd_p00_3),
        . simd_p01_0      (simd_p01_0),
        . simd_p01_1      (simd_p01_1),
        . simd_p01_2      (simd_p01_2),
        . simd_p01_3      (simd_p01_3),
        . simd_p10_0      (simd_p10_0),
        .simd_p10_1      (simd_p10_1),
        .simd_p10_2      (simd_p10_2),
        .simd_p10_3      (simd_p10_3),
        .simd_p11_0      (simd_p11_0),
        .simd_p11_1      (simd_p11_1),
        .simd_p11_2      (simd_p11_2),
        .simd_p11_3      (simd_p11_3),
        .simd_a_0        (simd_a_0),
        .simd_a_1        (simd_a_1),
        .simd_a_2        (simd_a_2),
        . simd_a_3        (simd_a_3),
        .simd_b_0        (simd_b_0),
        .simd_b_1        (simd_b_1),
        .simd_b_2        (simd_b_2),
        .simd_b_3        (simd_b_3),
        . simd_busy       (simd_fetch_busy)
    );
    
    //========================================================
    // INSTANCIA: Memoria Bankeada
    //========================================================
    dsa_mem_banked #(
        .MEM_SIZE   (MEM_SIZE),
        . ADDR_WIDTH (ADDR_WIDTH)
    ) mem_inst (
        .clk            (clk),
        .read_en        (final_mem_read_en),
        . read_addr      (final_mem_addr),
        .read_data      (mem_data_out),
        .write_en       (final_mem_write_en && !simd_parallel_write),
        .write_addr     (final_mem_addr),
        .write_data     (final_mem_data_in),
        . simd_write_en  (simd_parallel_write),
        .simd_base_addr (write_base_addr),
        .simd_data_0    (dp_simd_pixel_latched[0]),
        . simd_data_1    (dp_simd_pixel_latched[1]),
        .simd_data_2    (dp_simd_pixel_latched[2]),
        .simd_data_3    (dp_simd_pixel_latched[3])
    );
    
    assign ext_mem_data_out = mem_data_out;
    
    //========================================================
    // INSTANCIA: Datapath Secuencial
    //========================================================
    dsa_datapath dp_seq_inst (
        . clk       (clk),
        .rst       (rst),
        . start     (active_dp_start && !mode_simd),
        .p00       (seq_p00),
        .p01       (seq_p01),
        .p10       (seq_p10),
        .p11       (seq_p11),
        .a         (seq_a),
        .b         (seq_b),
        .pixel_out (dp_seq_pixel_out),
        .done      (dp_seq_done)
    );
    
    //========================================================
    // INSTANCIA: Datapath SIMD
    //========================================================
    dsa_datapath_simd #(
        .N (SIMD_WIDTH)
    ) dp_simd_inst (
        .clk       (clk),
        .rst       (rst),
        .start     (active_dp_start && mode_simd),
        .p00       (dp_simd_p00),
        .p01       (dp_simd_p01),
        .p10       (dp_simd_p10),
        .p11       (dp_simd_p11),
        .a         (dp_simd_a),
        .b         (dp_simd_b),
        .pixel_out (dp_simd_pixel_out),
        . done      (dp_simd_done)
    );

endmodule