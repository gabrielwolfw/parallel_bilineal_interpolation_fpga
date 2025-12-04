//============================================================
// dsa_pixel_fetch_simd_opt.sv - VERSIÓN OPTIMIZADA
// Cálculo paralelo de coordenadas + pipeline mejorado
//============================================================

module dsa_pixel_fetch_simd #(
    parameter ADDR_WIDTH = 18,
    parameter SIMD_WIDTH = 4
)(
    input  logic                    clk,
    input  logic                    rst,
    input  logic                    req_valid,
    input  logic [15:0]             base_x,
    input  logic [15:0]             base_y,
    input  logic [7:0]              scale_factor,
    input  logic [ADDR_WIDTH-1:0]   img_base_addr,
    input  logic [15:0]             img_width,
    input  logic [15:0]             img_height,
    output logic                    mem_read_en,
    output logic [ADDR_WIDTH-1:0]   mem_addr,
    input  logic [7:0]              mem_data,
    output logic                    fetch_valid,
    output logic [7:0]              p00 [0:SIMD_WIDTH-1],
    output logic [7:0]              p01 [0:SIMD_WIDTH-1],
    output logic [7:0]              p10 [0:SIMD_WIDTH-1],
    output logic [7:0]              p11 [0:SIMD_WIDTH-1],
    output logic [15:0]             a   [0:SIMD_WIDTH-1],
    output logic [15:0]             b   [0:SIMD_WIDTH-1],
    output logic                    busy
);

    //========================================================
    // Estados - REDUCIDOS
    //========================================================
    typedef enum logic [2:0] {
        ST_IDLE         = 3'd0,
        ST_CALC_ALL     = 3'd1,   // Calcular TODO en 1 ciclo
        ST_FETCH        = 3'd2,
        ST_DONE         = 3'd3
    } state_t;
    state_t state, next_state;

    //========================================================
    // Contadores
    //========================================================
    logic [4:0] fetch_cnt;
    logic [4:0] capture_cnt;
    
    logic [4:0] pending_idx_pipe [0:1];
    logic       pending_valid_pipe [0:1];

    //========================================================
    // Registros para coordenadas - TODOS CALCULADOS EN PARALELO
    //========================================================
    logic [15:0] src_x_int [0:SIMD_WIDTH-1];
    logic [15:0] src_y_int [0:SIMD_WIDTH-1];
    logic [15:0] frac_x    [0:SIMD_WIDTH-1];
    logic [15:0] frac_y    [0:SIMD_WIDTH-1];
    
    //========================================================
    // Configuración capturada
    //========================================================
    logic [15:0] base_x_r, base_y_r;
    logic [15:0] img_width_r;
    logic [ADDR_WIDTH-1:0] img_base_addr_r;
    logic [7:0] scale_factor_r;

    //========================================================
    // Escala inversa pre-calculada
    //========================================================
    logic [31:0] inv_scale;
    assign inv_scale = (scale_factor_r != 8'd0) ? 
                       (32'd65536 / {24'd0, scale_factor_r}) : 32'd256;

    //========================================================
    // CÁLCULO PARALELO DE COORDENADAS (combinacional)
    //========================================================
    logic [31:0] temp_x [0:SIMD_WIDTH-1];
    logic [31:0] temp_y;
    
    always_comb begin
        temp_y = {16'd0, base_y_r} * inv_scale;
        for (int i = 0; i < SIMD_WIDTH; i++) begin
            temp_x[i] = ({16'd0, base_x_r} + i) * inv_scale;
        end
    end

    //========================================================
    // Índices para fetch
    //========================================================
    wire [1:0] fetch_pixel    = fetch_cnt[3:2];
    wire [1:0] fetch_neighbor = fetch_cnt[1:0];

    //========================================================
    // Variables para direcciones
    //========================================================
    logic [ADDR_WIDTH-1:0] row_addr, col_addr;

    //========================================================
    // FSM
    //========================================================
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= ST_IDLE;
        end else begin
            state <= next_state;
        end
    end

    always_comb begin
        next_state = state;
        case (state)
            ST_IDLE:     if (req_valid) next_state = ST_CALC_ALL;
            ST_CALC_ALL: next_state = ST_FETCH;  // Solo 1 ciclo! 
            ST_FETCH:    if (capture_cnt >= 16) next_state = ST_DONE;
            ST_DONE:     next_state = ST_IDLE;
        endcase
    end

    //========================================================
    // Lógica Principal
    //========================================================
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            fetch_cnt <= '0;
            capture_cnt <= '0;
            mem_read_en <= 1'b0;
            mem_addr <= '0;
            
            base_x_r <= '0;
            base_y_r <= '0;
            img_width_r <= 16'd512;
            img_base_addr_r <= '0;
            scale_factor_r <= 8'h80;
            
            pending_idx_pipe[0] <= '0;
            pending_idx_pipe[1] <= '0;
            pending_valid_pipe[0] <= 1'b0;
            pending_valid_pipe[1] <= 1'b0;
            
            for (int i = 0; i < SIMD_WIDTH; i++) begin
                src_x_int[i] <= '0;
                src_y_int[i] <= '0;
                frac_x[i] <= '0;
                frac_y[i] <= '0;
                p00[i] <= 8'd0;
                p01[i] <= 8'd0;
                p10[i] <= 8'd0;
                p11[i] <= 8'd0;
                a[i] <= 16'd0;
                b[i] <= 16'd0;
            end
        end else begin
            
            // Pipeline de índices
            pending_idx_pipe[1] <= pending_idx_pipe[0];
            pending_valid_pipe[1] <= pending_valid_pipe[0];
            pending_idx_pipe[0] <= fetch_cnt;
            pending_valid_pipe[0] <= (state == ST_FETCH) && (fetch_cnt < 16);
            
            case (state)
                //============================================
                ST_IDLE: begin
                    if (req_valid) begin
                        base_x_r <= base_x;
                        base_y_r <= base_y;
                        img_width_r <= img_width;
                        img_base_addr_r <= img_base_addr;
                        scale_factor_r <= scale_factor;
                        
                        fetch_cnt <= '0;
                        capture_cnt <= '0;
                        mem_read_en <= 1'b0;
                        
                        pending_valid_pipe[0] <= 1'b0;
                        pending_valid_pipe[1] <= 1'b0;
                        
                        for (int i = 0; i < SIMD_WIDTH; i++) begin
                            p00[i] <= 8'd0;
                            p01[i] <= 8'd0;
                            p10[i] <= 8'd0;
                            p11[i] <= 8'd0;
                        end
                    end
                end
                
                //============================================
                // CÁLCULO PARALELO - TODO EN 1 CICLO
                //============================================
                ST_CALC_ALL: begin
                    for (int i = 0; i < SIMD_WIDTH; i++) begin
                        src_x_int[i] <= temp_x[i][23:8];
                        src_y_int[i] <= temp_y[23:8];
                        frac_x[i] <= {temp_x[i][7:0], 8'd0};
                        frac_y[i] <= {temp_y[7:0], 8'd0};
                    end
                end
                
                //============================================
                ST_FETCH: begin
                    // Captura desde pipeline
                    if (pending_valid_pipe[1]) begin
                        automatic logic [1:0] cap_pixel = pending_idx_pipe[1][3:2];
                        automatic logic [1:0] cap_neighbor = pending_idx_pipe[1][1:0];
                        
                        case (cap_neighbor)
                            2'd0: p00[cap_pixel] <= mem_data;
                            2'd1: p01[cap_pixel] <= mem_data;
                            2'd2: p10[cap_pixel] <= mem_data;
                            2'd3: begin
                                p11[cap_pixel] <= mem_data;
                                a[cap_pixel] <= {8'd0, frac_x[cap_pixel][15:8]};
                                b[cap_pixel] <= {8'd0, frac_y[cap_pixel][15:8]};
                            end
                        endcase
                        capture_cnt <= capture_cnt + 1;
                    end
                    
                    // Solicitar datos
                    if (fetch_cnt < 16) begin
                        mem_read_en <= 1'b1;
                        
                        if (fetch_neighbor[1] == 1'b0)
                            row_addr = img_base_addr_r + ({16'd0, src_y_int[fetch_pixel]} * {16'd0, img_width_r});
                        else
                            row_addr = img_base_addr_r + ({16'd0, src_y_int[fetch_pixel] + 16'd1} * {16'd0, img_width_r});
                        
                        if (fetch_neighbor[0] == 1'b0)
                            col_addr = row_addr + {2'd0, src_x_int[fetch_pixel]};
                        else
                            col_addr = row_addr + {2'd0, src_x_int[fetch_pixel]} + 1;
                        
                        mem_addr <= col_addr[ADDR_WIDTH-1:0];
                        fetch_cnt <= fetch_cnt + 1;
                    end else begin
                        mem_read_en <= 1'b0;
                    end
                end
                
                //============================================
                ST_DONE: begin
                    mem_read_en <= 1'b0;
                    fetch_cnt <= '0;
                    capture_cnt <= '0;
                    pending_valid_pipe[0] <= 1'b0;
                    pending_valid_pipe[1] <= 1'b0;
                end
            endcase
        end
    end

    //========================================================
    // Salidas
    //========================================================
    assign fetch_valid = (state == ST_DONE);
    assign busy = (state != ST_IDLE);

endmodule