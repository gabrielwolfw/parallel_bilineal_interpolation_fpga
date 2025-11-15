// dsa_control_fsm.sv
// FSM de control para procesamiento secuencial de interpolación bilineal
// Proyecto DSA Downscaling Imagen - Avance 3
// FPGA: Cyclone V (DE1-SoC MTL2)

module dsa_control_fsm #(
    parameter IMG_WIDTH  = 512,
    parameter IMG_HEIGHT = 512
)(
    input  logic       clk,
    input  logic       rst,
    input  logic       start,         // Señal para iniciar procesamiento
    input  logic       done_pixel,    // Señal del datapath: procesamiento píxel terminado
    input  logic [15:0] total_pixels, // Total de píxeles a procesar

    // Salidas de control
    output logic       busy,          // Estado ocupado
    output logic       ready,         // Estado listo
    output logic       next_pixel,    // Señal para datapath: procesar próximo píxel
    output logic [15:0] pixel_index   // Índice actual del píxel
);

    typedef enum logic [2:0] {
        S_IDLE,      // Espera inicio
        S_LOAD,      // Preparación parámetros
        S_PROCESS,   // Procesando píxel
        S_DONE       // Procesamiento terminado
    } state_t;

    state_t state, next_state;
    logic [15:0] pixel_counter;

    // Lógica secuencial de estado y contador de píxel
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state         <= S_IDLE;
            pixel_counter <= 0;
        end else begin
            state         <= next_state;
            if (state == S_LOAD)
                pixel_counter <= 0;
            else if ((state == S_PROCESS) && done_pixel)
                pixel_counter <= pixel_counter + 1;
        end
    end

    // Lógica de transición de estados
    always_comb begin
        next_state = state;
        case (state)
            S_IDLE: begin
                if (start)
                    next_state = S_LOAD;
            end
            S_LOAD: begin
                next_state = S_PROCESS;
            end
            S_PROCESS: begin
                if (done_pixel) begin
                    if (pixel_counter + 1 < total_pixels)
                        next_state = S_PROCESS;
                    else
                        next_state = S_DONE;
                end
            end
            S_DONE: begin
                next_state = S_IDLE; // Espera nuevo start
            end
            default: next_state = S_IDLE;
        endcase
    end

    // Señales de salida
    assign busy       = (state == S_PROCESS);
    assign ready      = (state == S_DONE);
    assign next_pixel = (state == S_PROCESS) && done_pixel;
    assign pixel_index= pixel_counter;

endmodule