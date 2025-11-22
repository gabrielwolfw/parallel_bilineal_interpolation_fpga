//============================================================
// dsa_control_fsm_simd.sv
// FSM de control para procesamiento SIMD
// N píxeles por iteración
//============================================================

module dsa_control_fsm_simd #(
    parameter IMG_WIDTH_MAX  = 512,
    parameter IMG_HEIGHT_MAX = 512,
    parameter SIMD_WIDTH     = 4
)(
    input  logic        clk,
    input  logic        rst,
    
    // Control desde top
    input  logic        enable,
    input  logic [15:0] img_width_out,
    input  logic [15:0] img_height_out,
    
    // Señales desde/hacia fetch y datapath
    output logic        fetch_req,
    input  logic        fetch_done,
    output logic        dp_start,
    input  logic        dp_done,
    output logic        write_enable,
    output logic [3:0]  write_index,      // Índice del píxel SIMD a escribir
    
    // Coordenadas actuales (base del grupo SIMD)
    output logic [15:0] current_x,
    output logic [15:0] current_y,
    
    // Estado
    output logic        busy,
    output logic        ready
);

    //========================================================
    // Estados
    //========================================================
    typedef enum logic [3:0] {
        ST_IDLE          = 4'd0,
        ST_INIT          = 4'd1,
        ST_REQUEST_FETCH = 4'd2,
        ST_WAIT_FETCH    = 4'd3,
        ST_INTERPOLATE   = 4'd4,
        ST_WRITE_SIMD    = 4'd5,  // Escribe N píxeles secuencialmente
        ST_NEXT_GROUP    = 4'd6,
        ST_DONE          = 4'd7
    } state_t;
    
    state_t state, next_state;
    
    //========================================================
    // Registros
    //========================================================
    logic [15:0] x_reg, y_reg;
    logic [3:0]  write_counter;       // Contador para escrituras SIMD
    logic [31:0] total_pixels;
    logic [31:0] pixels_processed;
    
    //========================================================
    // Cálculo
    //========================================================
    always_comb begin
        total_pixels = img_width_out * img_height_out;
    end
    
    //========================================================
    // FSM Secuencial
    //========================================================
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= ST_IDLE;
            x_reg <= 16'd0;
            y_reg <= 16'd0;
            write_counter <= 4'd0;
            pixels_processed <= 32'd0;
        end else begin
            state <= next_state;
            
            case (state)
                ST_IDLE: begin
                    if (enable) begin
                        x_reg <= 16'd0;
                        y_reg <= 16'd0;
                        write_counter <= 4'd0;
                        pixels_processed <= 32'd0;
                    end
                end
                
                ST_WRITE_SIMD: begin
                    // Incrementar contador de escritura
                    if (write_counter < SIMD_WIDTH - 1)
                        write_counter <= write_counter + 4'd1;
                    else
                        write_counter <= 4'd0;
                end
                
                ST_NEXT_GROUP: begin
                    // Actualizar píxeles procesados
                    pixels_processed <= pixels_processed + SIMD_WIDTH;
                    
                    // Avanzar coordenadas por grupo SIMD
                    if (x_reg + SIMD_WIDTH < img_width_out) begin
                        x_reg <= x_reg + SIMD_WIDTH;
                    end else begin
                        x_reg <= 16'd0;
                        y_reg <= y_reg + 16'd1;
                    end
                end
            endcase
        end
    end
    
    //========================================================
    // FSM Combinacional
    //========================================================
    always_comb begin
        next_state = state;
        fetch_req = 1'b0;
        dp_start = 1'b0;
        write_enable = 1'b0;
        
        case (state)
            ST_IDLE: begin
                if (enable)
                    next_state = ST_INIT;
            end
            
            ST_INIT: begin
                next_state = ST_REQUEST_FETCH;
            end
            
            ST_REQUEST_FETCH: begin
                fetch_req = 1'b1;
                next_state = ST_WAIT_FETCH;
            end
            
            ST_WAIT_FETCH: begin
                if (fetch_done)
                    next_state = ST_INTERPOLATE;
            end
            
            ST_INTERPOLATE: begin
                dp_start = 1'b1;
                if (dp_done)
                    next_state = ST_WRITE_SIMD;
            end
            
            ST_WRITE_SIMD: begin
                write_enable = 1'b1;
                
                // Escribir SIMD_WIDTH píxeles secuencialmente
                if (write_counter >= SIMD_WIDTH - 1)
                    next_state = ST_NEXT_GROUP;
                // else: permanecer en este estado
            end
            
            ST_NEXT_GROUP: begin
                if (pixels_processed + SIMD_WIDTH >= total_pixels)
                    next_state = ST_DONE;
                else
                    next_state = ST_REQUEST_FETCH;
            end
            
            ST_DONE: begin
                if (!enable)
                    next_state = ST_IDLE;
            end
            
            default: next_state = ST_IDLE;
        endcase
    end
    
    //========================================================
    // Salidas
    //========================================================
    assign current_x = x_reg;
    assign current_y = y_reg;
    assign write_index = write_counter;
    assign busy = (state != ST_IDLE) && (state != ST_DONE);
    assign ready = (state == ST_DONE);

endmodule