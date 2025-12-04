//============================================================
// dsa_step_controller.sv
// Controlador de ejecución paso a paso para debugging
// CORREGIDO: Permite arranque de FSM antes de holdear
//============================================================

module dsa_step_controller (
    input  logic        clk,
    input  logic        rst,
    
    //========================================================
    // Control desde JTAG/Host
    //========================================================
    input  logic        step_enable,
    input  logic        step_trigger,
    input  logic [1:0]  step_granularity,
    
    //========================================================
    // Interfaz con FSMs
    //========================================================
    input  logic [3:0]  fsm_state_seq,
    input  logic [3:0]  fsm_state_simd,
    input  logic        mode_simd,
    input  logic        pixel_complete,
    input  logic        group_complete,
    
    //========================================================
    // Salida de control
    //========================================================
    output logic        fsm_hold,
    output logic        step_ack,
    output logic        step_ready
);

    //========================================================
    // Granularidad de stepping
    //========================================================
    localparam GRAN_STATE = 2'd0;
    localparam GRAN_PIXEL = 2'd1;
    localparam GRAN_GROUP = 2'd2;
    
    // Estados de la FSM principal (para detectar IDLE)
    localparam FSM_IDLE = 4'd0;
    
    //========================================================
    // Estados internos del controlador de stepping
    //========================================================
    typedef enum logic [2:0] {
        ST_DISABLED,           // Stepping deshabilitado
        ST_WAIT_FSM_START,     // Esperando que FSM salga de IDLE
        ST_HOLD_WAIT_TRIGGER,  // Pausado, esperando trigger
        ST_RELEASING,          // Liberando hold
        ST_WAIT_CONDITION      // Esperando condición de parada
    } step_state_t;
    
    step_state_t state, next_state;
    
    //========================================================
    // Señales internas
    //========================================================
    logic [3:0] fsm_state_current;
    logic [3:0] fsm_state_prev;
    logic       state_changed;
    logic       step_trigger_prev;
    logic       step_trigger_edge;
    logic       pixel_complete_prev;
    logic       pixel_complete_edge;
    logic       group_complete_prev;
    logic       group_complete_edge;
    logic       fsm_is_idle;
    logic       fsm_just_started;
    
    assign fsm_state_current = mode_simd ? fsm_state_simd : fsm_state_seq;
    assign fsm_is_idle = (fsm_state_current == FSM_IDLE);
    assign state_changed = (fsm_state_current != fsm_state_prev);
    assign step_trigger_edge = step_trigger && !step_trigger_prev;
    assign pixel_complete_edge = pixel_complete && !pixel_complete_prev;
    assign group_complete_edge = group_complete && !group_complete_prev;
    
    // Detectar cuando FSM acaba de salir de IDLE
    assign fsm_just_started = (fsm_state_prev == FSM_IDLE) && (fsm_state_current != FSM_IDLE);
    
    //========================================================
    // Lógica de condición de parada según granularidad
    //========================================================
    logic stop_condition_met;
    
    always_comb begin
        case (step_granularity)
            GRAN_STATE: stop_condition_met = state_changed;
            GRAN_PIXEL: stop_condition_met = pixel_complete_edge;
            GRAN_GROUP: stop_condition_met = mode_simd ?  group_complete_edge : pixel_complete_edge;
            default:    stop_condition_met = state_changed;
        endcase
    end
    
    //========================================================
    // Registros de historial
    //========================================================
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            fsm_state_prev <= 4'd0;
            step_trigger_prev <= 1'b0;
            pixel_complete_prev <= 1'b0;
            group_complete_prev <= 1'b0;
        end else begin
            fsm_state_prev <= fsm_state_current;
            step_trigger_prev <= step_trigger;
            pixel_complete_prev <= pixel_complete;
            group_complete_prev <= group_complete;
        end
    end
    
    //========================================================
    // FSM de Stepping
    //========================================================
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= ST_DISABLED;
        end else begin
            state <= next_state;
        end
    end
    
    always_comb begin
        next_state = state;
        fsm_hold = 1'b0;
        step_ack = 1'b0;
        step_ready = 1'b0;
        
        case (state)
            //--------------------------------------------
            ST_DISABLED: begin
                // Stepping deshabilitado - no hacer hold
                fsm_hold = 1'b0;
                step_ready = 1'b0;
                
                if (step_enable) begin
                    // Si FSM está en IDLE, esperar a que arranque
                    if (fsm_is_idle)
                        next_state = ST_WAIT_FSM_START;
                    else
                        // FSM ya está corriendo, pausar inmediatamente
                        next_state = ST_HOLD_WAIT_TRIGGER;
                end
            end
            
            //--------------------------------------------
            ST_WAIT_FSM_START: begin
                // NO hacer hold - permitir que FSM arranque
                fsm_hold = 1'b0;
                step_ready = 1'b0;
                
                if (! step_enable) begin
                    next_state = ST_DISABLED;
                end else if (! fsm_is_idle) begin
                    // FSM salió de IDLE, ahora pausar
                    next_state = ST_HOLD_WAIT_TRIGGER;
                end
            end
            
            //--------------------------------------------
            ST_HOLD_WAIT_TRIGGER: begin
                // Pausar FSM y esperar trigger
                fsm_hold = 1'b1;
                step_ready = 1'b1;
                
                if (! step_enable) begin
                    next_state = ST_DISABLED;
                end else if (step_trigger_edge) begin
                    next_state = ST_RELEASING;
                end
            end
            
            //--------------------------------------------
            ST_RELEASING: begin
                // Liberar hold por un ciclo
                fsm_hold = 1'b0;
                step_ack = 1'b1;
                step_ready = 1'b0;
                next_state = ST_WAIT_CONDITION;
            end
            
            //--------------------------------------------
            ST_WAIT_CONDITION: begin
                // Mantener liberado hasta que se cumpla condición
                fsm_hold = 1'b0;
                step_ready = 1'b0;
                
                if (! step_enable) begin
                    next_state = ST_DISABLED;
                end else if (stop_condition_met) begin
                    next_state = ST_HOLD_WAIT_TRIGGER;
                end
            end
            
            //--------------------------------------------
            default: begin
                next_state = ST_DISABLED;
            end
        endcase
    end

endmodule