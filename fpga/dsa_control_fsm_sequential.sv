//============================================================
// dsa_control_fsm_sequential.sv
// FSM de control para procesamiento secuencial
// 1 píxel por iteración
//============================================================

module dsa_control_fsm_sequential #(
    parameter IMG_WIDTH_MAX  = 512,
    parameter IMG_HEIGHT_MAX = 512
)(
    input  logic        clk,
    input  logic        rst,
    
    // Control desde top
    input  logic        enable,           // Activar este FSM
	 input  logic        hold,             // Pausar FSM
    input  logic [15:0] img_width_out,    // Ancho de imagen salida
    input  logic [15:0] img_height_out,   // Alto de imagen salida
    
    // Señales desde/hacia fetch y datapath
    output logic        fetch_req,        // Solicitar fetch
    input  logic        fetch_done,       // Fetch completado
    output logic        dp_start,         // Iniciar datapath
    input  logic        dp_done,          // Datapath completó
    output logic        write_enable,     // Habilitar escritura
    
    // Coordenadas actuales
    output logic [15:0] current_x,
    output logic [15:0] current_y,
    
    // Estado
    output logic        busy,
    output logic        ready,
	 output logic [3:0]  state_out          // Estado para debug
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
        ST_WRITE         = 4'd5,
        ST_NEXT_PIXEL    = 4'd6,
        ST_DONE          = 4'd7
    } state_t;
    
    state_t state, next_state;
    
    //========================================================
    // Registros
    //========================================================
    logic [15:0] x_reg, y_reg;
    logic [31:0] total_pixels;
    logic [31:0] pixels_processed;
    
    //========================================================
    // Cálculo de total de píxeles
    //========================================================
    always_comb begin
        total_pixels = {16'd0, img_width_out} * {16'd0, img_height_out};
    end
    
    //========================================================
    // FSM Secuencial
    //========================================================
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= ST_IDLE;
            x_reg <= 16'd0;
            y_reg <= 16'd0;
            pixels_processed <= 32'd0;
        end else if (! hold) begin
            state <= next_state;
            
            case (state)
                ST_IDLE: begin
                    if (enable) begin
                        x_reg <= 16'd0;
                        y_reg <= 16'd0;
                        pixels_processed <= 32'd0;
                    end
                end
                
                ST_NEXT_PIXEL: begin
                    pixels_processed <= pixels_processed + 32'd1;
                    
                    // Avanzar coordenadas
                    if (x_reg + 16'd1 < img_width_out) begin
                        x_reg <= x_reg + 16'd1;
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
                    next_state = ST_WRITE;
            end
            
            ST_WRITE: begin
                write_enable = 1'b1;
                next_state = ST_NEXT_PIXEL;
            end
            
            ST_NEXT_PIXEL: begin
                if (pixels_processed + 1 >= total_pixels)
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
    assign busy = (state != ST_IDLE) && (state != ST_DONE);
    assign ready = (state == ST_DONE);
	 assign state_out = state;

endmodule