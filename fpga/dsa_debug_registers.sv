//============================================================
// dsa_debug_registers.sv
// Registros de debug para observación durante stepping
// CORREGIDO: Captura en tiempo real + captura en step_ack
//============================================================

module dsa_debug_registers #(
    parameter ADDR_WIDTH = 18,
    parameter SIMD_WIDTH = 4
)(
    input  logic        clk,
    input  logic        rst,
    
    //========================================================
    // Captura de señales (desde dsa_top y submódulos)
    //========================================================
    input  logic [3:0]  fsm_state_seq,
    input  logic [3:0]  fsm_state_simd,
    input  logic        mode_simd,
    
    input  logic [15:0] current_x,
    input  logic [15:0] current_y,
    
    input  logic [7:0]  seq_p00,
    input  logic [7:0]  seq_p01,
    input  logic [7:0]  seq_p10,
    input  logic [7:0]  seq_p11,
    
    input  logic [15:0] coef_a,
    input  logic [15:0] coef_b,
    
    input  logic [7:0]  pixel_out_seq,
    input  logic [7:0]  pixel_out_simd [0:SIMD_WIDTH-1],
    
    input  logic [ADDR_WIDTH-1:0] mem_addr,
    input  logic [7:0]  mem_data,
    input  logic        mem_read_en,
    input  logic        mem_write_en,
    
    input  logic        capture_enable,
    input  logic        step_ack,
    
    //========================================================
    // Salidas hacia JTAG (registros observables)
    //========================================================
    output logic [31:0] debug_reg_0,
    output logic [31:0] debug_reg_1,
    output logic [31:0] debug_reg_2,
    output logic [31:0] debug_reg_3,
    output logic [31:0] debug_reg_4,
    output logic [31:0] debug_reg_5,
    output logic [31:0] debug_reg_6,
    output logic [31:0] debug_reg_7
);

    //========================================================
    // Señales en tiempo real (sin registrar)
    //========================================================
    logic [3:0]  live_fsm_state;
    
    assign live_fsm_state = mode_simd ? fsm_state_simd : fsm_state_seq;

    //========================================================
    // Registros de captura (para cuando step_ack)
    //========================================================
    logic [3:0]  cap_fsm_state;
    logic        cap_mode_simd;
    logic [15:0] cap_x, cap_y;
    logic [7:0]  cap_p00, cap_p01, cap_p10, cap_p11;
    logic [15:0] cap_a, cap_b;
    logic [7:0]  cap_pixel_out;
    logic [7:0]  cap_simd_out [0:SIMD_WIDTH-1];
    logic [ADDR_WIDTH-1:0] cap_mem_addr;
    logic [7:0]  cap_mem_data;
    logic        cap_mem_rd, cap_mem_wr;
    
    //========================================================
    // Lógica de captura - capturar cuando step_ack O continuamente si no hay stepping
    //========================================================
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            cap_fsm_state <= 4'd0;
            cap_mode_simd <= 1'b0;
            cap_x <= 16'd0;
            cap_y <= 16'd0;
            cap_p00 <= 8'd0;
            cap_p01 <= 8'd0;
            cap_p10 <= 8'd0;
            cap_p11 <= 8'd0;
            cap_a <= 16'd0;
            cap_b <= 16'd0;
            cap_pixel_out <= 8'd0;
            cap_mem_addr <= '0;
            cap_mem_data <= 8'd0;
            cap_mem_rd <= 1'b0;
            cap_mem_wr <= 1'b0;
            for (int i = 0; i < SIMD_WIDTH; i++)
                cap_simd_out[i] <= 8'd0;
        end else if (step_ack || ! capture_enable) begin
            // Capturar cuando hay step_ack O cuando stepping está deshabilitado
            cap_fsm_state <= live_fsm_state;
            cap_mode_simd <= mode_simd;
            cap_x <= current_x;
            cap_y <= current_y;
            cap_p00 <= seq_p00;
            cap_p01 <= seq_p01;
            cap_p10 <= seq_p10;
            cap_p11 <= seq_p11;
            cap_a <= coef_a;
            cap_b <= coef_b;
            cap_pixel_out <= pixel_out_seq;
            cap_mem_addr <= mem_addr;
            cap_mem_data <= mem_data;
            cap_mem_rd <= mem_read_en;
            cap_mem_wr <= mem_write_en;
            for (int i = 0; i < SIMD_WIDTH; i++)
                cap_simd_out[i] <= pixel_out_simd[i];
        end
    end
    
    //========================================================
    // Empaquetado de registros de debug
    // NOTA: Usar valores en TIEMPO REAL para FSM state cuando stepping activo
    //========================================================
    
    // Reg 0: Estado FSM en tiempo real para mejor observabilidad
    assign debug_reg_0 = {
        4'd0,                           // [31:28] reserved
        live_fsm_state,                 // [27:24] FSM state (TIEMPO REAL)
        8'd0,                           // [23:16] reserved
        6'd0, cap_mem_wr, cap_mem_rd,   // [15:8] status flags
        7'd0, mode_simd                 // [7:0] mode (TIEMPO REAL)
    };
    
    // Reg 1: Coordenadas (tiempo real)
    assign debug_reg_1 = {current_y, current_x};
    
    // Reg 2: Píxeles vecinos (capturados)
    assign debug_reg_2 = {cap_p11, cap_p10, cap_p01, cap_p00};
    
    // Reg 3: Coeficientes (capturados)
    assign debug_reg_3 = {cap_b, cap_a};
    
    // Reg 4: Pixel de salida (capturado)
    assign debug_reg_4 = {24'd0, cap_pixel_out};
    
    // Reg 5: Dirección memoria (capturada)
    assign debug_reg_5 = {{(32-ADDR_WIDTH){1'b0}}, cap_mem_addr};
    
    // Reg 6: Dato memoria (capturado)
    assign debug_reg_6 = {24'd0, cap_mem_data};
    
    // Reg 7: SIMD outputs (capturados)
    assign debug_reg_7 = {cap_simd_out[3], cap_simd_out[2], 
                          cap_simd_out[1], cap_simd_out[0]};

endmodule