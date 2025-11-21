//============================================================
// dsa_jtag_interface.sv
// Interfaz JTAG UART para comunicación con PC
// Basado en principios de Virtual JTAG de Altera/Intel
//============================================================

module dsa_jtag_interface #(
    parameter MEM_SIZE = 262144,
    parameter DATA_WIDTH = 8
)(
    input  logic        clk,
    input  logic        rst,
    
    // Interfaz hacia dsa_top
    output logic        dsa_start,
    output logic        dsa_mode_simd,
    output logic [9:0]  dsa_img_width_in,
    output logic [9:0]  dsa_img_height_in,
    output logic [7:0]  dsa_scale_factor,
    output logic        dsa_mem_write_en,
    output logic        dsa_mem_read_en,
    output logic [17:0] dsa_mem_addr,
    output logic [7:0]  dsa_mem_data_in,
    input  logic [7:0]  dsa_mem_data_out,
    input  logic        dsa_busy,
    input  logic        dsa_ready,
    input  logic        dsa_error,
    input  logic [15:0] dsa_progress,
    input  logic [31:0] dsa_flops_count,
    input  logic [31:0] dsa_mem_reads_count,
    input  logic [31:0] dsa_mem_writes_count,
    
    // Stepping control
    output logic        step_enable,
    output logic        step_trigger
);

    //=================================================================
    // Virtual JTAG señales
    //=================================================================
    
    logic        tck;           // JTAG clock
    logic        tdi;           // JTAG data in
    logic        tdo;           // JTAG data out
    logic [3:0]  ir_in;         // Instruction register
    logic        virtual_state_cdr;
    logic        virtual_state_sdr;
    logic        virtual_state_udr;
    
    //=================================================================
    // Registros de comando y datos
    //=================================================================
    
    // Códigos de instrucción (IR)
    localparam IR_WRITE_CONFIG   = 4'h0;  // Escribir configuración
    localparam IR_WRITE_MEM      = 4'h1;  // Escribir memoria
    localparam IR_READ_MEM       = 4'h2;  // Leer memoria
    localparam IR_START_PROCESS  = 4'h3;  // Iniciar procesamiento
    localparam IR_READ_STATUS    = 4'h4;  // Leer estado
    localparam IR_READ_COUNTERS  = 4'h5;  // Leer performance counters
    localparam IR_WRITE_ADDR     = 4'h6;  // Establecer dirección
    localparam IR_STEP_ENABLE    = 4'h7;  // Habilitar stepping
    localparam IR_STEP_NEXT      = 4'h8;  // Ejecutar un paso
    localparam IR_RESET_DSA      = 4'h9;  // Reset del DSA
    localparam IR_BURST_WRITE    = 4'hA;  // Escritura en ráfaga
    localparam IR_BURST_READ     = 4'hB;  // Lectura en ráfaga
    
    // Shift registers para datos
    logic [31:0] dr_shift_reg;
    logic [31:0] dr_capture_reg;
    
    // Registros internos
    logic [17:0] mem_addr_reg;
    logic [9:0]  img_width_reg;
    logic [9:0]  img_height_reg;
    logic [7:0]  scale_factor_reg;
    logic        mode_simd_reg;
    logic        stepping_enabled;
    logic [15:0] burst_counter;
    logic [15:0] burst_length;
    
    //=================================================================
    // Instancia de Virtual JTAG
    //=================================================================
    
    sld_virtual_jtag #(
        .sld_auto_instance_index("YES"),
        .sld_instance_index(0),
        .sld_ir_width(4)
    ) virtual_jtag_inst (
        .tck(tck),
        .tdi(tdi),
        .tdo(tdo),
        .ir_in(ir_in),
        .virtual_state_cdr(virtual_state_cdr),
        .virtual_state_sdr(virtual_state_sdr),
        .virtual_state_udr(virtual_state_udr)
    );
    
    //=================================================================
    // Máquina de estados para procesamiento de comandos
    //=================================================================
    
    typedef enum logic [3:0] {
        ST_IDLE,
        ST_CAPTURE,
        ST_SHIFT,
        ST_UPDATE,
        ST_EXECUTE,
        ST_BURST_WRITE,
        ST_BURST_READ
    } jtag_state_t;
    
    jtag_state_t jtag_state, jtag_next_state;
    
    always_ff @(posedge tck or posedge rst) begin
        if (rst) begin
            jtag_state <= ST_IDLE;
        end else begin
            jtag_state <= jtag_next_state;
        end
    end
    
    //=================================================================
    // Lógica de captura de datos (Capture-DR)
    //=================================================================
    
    always_ff @(posedge tck or posedge rst) begin
        if (rst) begin
            dr_capture_reg <= 32'h0;
        end else if (virtual_state_cdr) begin
            case (ir_in)
                IR_READ_STATUS: begin
                    dr_capture_reg <= {
                        16'h0,
                        dsa_progress,
                        5'h0,
                        dsa_error,
                        dsa_ready,
                        dsa_busy
                    };
                end
                
                IR_READ_MEM: begin
                    dr_capture_reg <= {24'h0, dsa_mem_data_out};
                end
                
                IR_READ_COUNTERS: begin
                    dr_capture_reg <= dsa_flops_count;
                end
                
                default: begin
                    dr_capture_reg <= 32'h0;
                end
            endcase
        end
    end
    
    //=================================================================
    // Lógica de desplazamiento (Shift-DR)
    //=================================================================
    
    always_ff @(posedge tck or posedge rst) begin
        if (rst) begin
            dr_shift_reg <= 32'h0;
        end else if (virtual_state_cdr) begin
            dr_shift_reg <= dr_capture_reg;
        end else if (virtual_state_sdr) begin
            dr_shift_reg <= {tdi, dr_shift_reg[31:1]};
        end
    end
    
    assign tdo = dr_shift_reg[0];
    
    //=================================================================
    // Lógica de actualización (Update-DR)
    //=================================================================
    
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            dsa_start <= 1'b0;
            dsa_mem_write_en <= 1'b0;
            dsa_mem_read_en <= 1'b0;
            mem_addr_reg <= 18'h0;
            img_width_reg <= 10'h0;
            img_height_reg <= 10'h0;
            scale_factor_reg <= 8'h80;
            mode_simd_reg <= 1'b0;
            stepping_enabled <= 1'b0;
            step_trigger <= 1'b0;
            burst_counter <= 16'h0;
            burst_length <= 16'h0;
        end else begin
            // Pulsos de un ciclo
            dsa_start <= 1'b0;
            dsa_mem_write_en <= 1'b0;
            dsa_mem_read_en <= 1'b0;
            step_trigger <= 1'b0;
            
            // Sincronización desde dominio JTAG
            if (virtual_state_udr) begin
                case (ir_in)
                    IR_WRITE_CONFIG: begin
                        // [31:22] - img_width
                        // [21:12] - img_height
                        // [11:4]  - scale_factor
                        // [0]     - mode_simd
                        img_width_reg <= dr_shift_reg[31:22];
                        img_height_reg <= dr_shift_reg[21:12];
                        scale_factor_reg <= dr_shift_reg[11:4];
                        mode_simd_reg <= dr_shift_reg[0];
                    end
                    
                    IR_WRITE_ADDR: begin
                        mem_addr_reg <= dr_shift_reg[17:0];
                    end
                    
                    IR_WRITE_MEM: begin
                        dsa_mem_write_en <= 1'b1;
                    end
                    
                    IR_READ_MEM: begin
                        dsa_mem_read_en <= 1'b1;
                    end
                    
                    IR_START_PROCESS: begin
                        if (!stepping_enabled)
                            dsa_start <= 1'b1;
                    end
                    
                    IR_STEP_ENABLE: begin
                        stepping_enabled <= dr_shift_reg[0];
                    end
                    
                    IR_STEP_NEXT: begin
                        if (stepping_enabled)
                            step_trigger <= 1'b1;
                    end
                    
                    IR_BURST_WRITE: begin
                        burst_length <= dr_shift_reg[31:16];
                        burst_counter <= 16'h0;
                    end
                    
                    default: begin
                    end
                endcase
            end
            
            // Manejo de escritura en ráfaga
            if (burst_counter < burst_length && jtag_state == ST_BURST_WRITE) begin
                dsa_mem_write_en <= 1'b1;
                mem_addr_reg <= mem_addr_reg + 1;
                burst_counter <= burst_counter + 1;
            end
        end
    end
    
    //=================================================================
    // Asignaciones de salida
    //=================================================================
    
    assign dsa_img_width_in = img_width_reg;
    assign dsa_img_height_in = img_height_reg;
    assign dsa_scale_factor = scale_factor_reg;
    assign dsa_mode_simd = mode_simd_reg;
    assign dsa_mem_addr = mem_addr_reg;
    assign dsa_mem_data_in = dr_shift_reg[7:0];
    assign step_enable = stepping_enabled;

endmodule