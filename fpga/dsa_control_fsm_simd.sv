//============================================================
// dsa_control_fsm_simd_opt.sv
// FSM SIMD optimizada - escritura paralela en 1 ciclo
//============================================================

module dsa_control_fsm_simd #(
    parameter IMG_WIDTH_MAX  = 512,
    parameter IMG_HEIGHT_MAX = 512,
    parameter SIMD_WIDTH     = 4
)(
    input  logic        clk,
    input  logic        rst,
    
    input  logic        enable,
    input  logic [15:0] img_width_out,
    input  logic [15:0] img_height_out,
    
    output logic        fetch_req,
    input  logic        fetch_done,
    output logic        dp_start,
    input  logic        dp_done,
    output logic        simd_write_en,      // Escritura paralela
    
    output logic [15:0] current_x,
    output logic [15:0] current_y,
    
    output logic        busy,
    output logic        ready
);

    //========================================================
    // Estados - OPTIMIZADOS
    //========================================================
    typedef enum logic [3:0] {
        ST_IDLE          = 4'd0,
        ST_INIT          = 4'd1,
        ST_REQUEST_FETCH = 4'd2,
        ST_WAIT_FETCH    = 4'd3,
        ST_START_DP      = 4'd4,
        ST_WAIT_DP       = 4'd5,
        ST_WRITE_ALL     = 4'd6,   // Escritura de 4 píxeles en 1 ciclo
        ST_NEXT_GROUP    = 4'd7,
        ST_DONE          = 4'd8
    } state_t;
    
    state_t state, next_state;
    
    logic [15:0] x_reg, y_reg;
    logic [31:0] total_pixels;
    logic [31:0] pixels_processed;
    
    always_comb begin
        total_pixels = {16'd0, img_width_out} * {16'd0, img_height_out};
    end
    
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= ST_IDLE;
            x_reg <= 16'd0;
            y_reg <= 16'd0;
            pixels_processed <= 32'd0;
        end else begin
            state <= next_state;
            
            case (state)
                ST_IDLE: begin
                    if (enable) begin
                        x_reg <= 16'd0;
                        y_reg <= 16'd0;
                        pixels_processed <= 32'd0;
                    end
                end
                
                ST_NEXT_GROUP: begin
                    pixels_processed <= pixels_processed + SIMD_WIDTH;
                    
                    if (x_reg + SIMD_WIDTH < img_width_out) begin
                        x_reg <= x_reg + SIMD_WIDTH;
                    end else begin
                        x_reg <= 16'd0;
                        y_reg <= y_reg + 16'd1;
                    end
                end
                
                default: ;
            endcase
        end
    end
    
    always_comb begin
        next_state = state;
        fetch_req = 1'b0;
        dp_start = 1'b0;
        simd_write_en = 1'b0;
        
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
                    next_state = ST_START_DP;
            end
            
            ST_START_DP: begin
                dp_start = 1'b1;
                next_state = ST_WAIT_DP;
            end
            
            ST_WAIT_DP: begin
                if (dp_done)
                    next_state = ST_WRITE_ALL;
            end
            
            ST_WRITE_ALL: begin
                simd_write_en = 1'b1;   // Escribir 4 píxeles en 1 ciclo
                next_state = ST_NEXT_GROUP;
            end
            
            ST_NEXT_GROUP: begin
                if (pixels_processed + SIMD_WIDTH >= total_pixels)
                    next_state = ST_DONE;
                else
                    next_state = ST_REQUEST_FETCH;
            end
            
            ST_DONE: begin
                if (! enable)
                    next_state = ST_IDLE;
            end
            
            default: next_state = ST_IDLE;
        endcase
    end
    
    assign current_x = x_reg;
    assign current_y = y_reg;
    assign busy = (state != ST_IDLE) && (state != ST_DONE);
    assign ready = (state == ST_DONE);

endmodule