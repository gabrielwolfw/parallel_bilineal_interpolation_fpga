//============================================================
// dsa_jtag_interface. sv
// Interfaz JTAG para comunicación con PC
// Basado en JTAG UART de Intel/Altera
//============================================================

module dsa_jtag_interface #(
    parameter ADDR_WIDTH = 18,
    parameter DATA_WIDTH = 8
)(
    input  logic        clk,
    input  logic        rst,
    
    // Interfaz con dsa_top
    output logic        dsa_start,
    output logic        dsa_mode_simd,
    output logic [15:0] dsa_img_width,
    output logic [15:0] dsa_img_height,
    output logic [7:0]  dsa_scale_factor,
    input  logic        dsa_busy,
    input  logic        dsa_ready,
    input  logic [15:0] dsa_progress,
    input  logic [31:0] dsa_flops_count,
    input  logic [31:0] dsa_mem_reads,
    input  logic [31:0] dsa_mem_writes,
    
    // Interfaz con memoria externa
    output logic                    mem_write_en,
    output logic                    mem_read_en,
    output logic [ADDR_WIDTH-1:0]   mem_addr,
    output logic [DATA_WIDTH-1:0]   mem_data_out,
    input  logic [DATA_WIDTH-1:0]   mem_data_in,
    
    // JTAG UART signals
    input  logic [7:0]  jtag_rx_data,
    input  logic        jtag_rx_valid,
    output logic        jtag_rx_ready,
    output logic [7:0]  jtag_tx_data,
    output logic        jtag_tx_valid,
    input  logic        jtag_tx_ready
);

    //========================================================
    // Comandos del protocolo
    //========================================================
    localparam [7:0] CMD_NOP           = 8'h00;
    localparam [7:0] CMD_SET_WIDTH     = 8'h01;
    localparam [7:0] CMD_SET_HEIGHT    = 8'h02;
    localparam [7:0] CMD_SET_SCALE     = 8'h03;
    localparam [7:0] CMD_SET_MODE      = 8'h04;
    localparam [7:0] CMD_START         = 8'h05;
    localparam [7:0] CMD_GET_STATUS    = 8'h06;
    localparam [7:0] CMD_GET_PROGRESS  = 8'h07;
    localparam [7:0] CMD_GET_METRICS   = 8'h08;
    localparam [7:0] CMD_WRITE_MEM     = 8'h10;
    localparam [7:0] CMD_READ_MEM      = 8'h11;
    localparam [7:0] CMD_SET_ADDR      = 8'h12;
    localparam [7:0] CMD_WRITE_BURST   = 8'h13;
    localparam [7:0] CMD_READ_BURST    = 8'h14;
    
    // Respuestas
    localparam [7:0] RSP_OK            = 8'hA0;
    localparam [7:0] RSP_ERROR         = 8'hE0;
    localparam [7:0] RSP_BUSY          = 8'hB0;
    localparam [7:0] RSP_READY         = 8'hD0;  // Corregido: era 8'hR0
    
    //========================================================
    // Estados de la FSM
    //========================================================
    typedef enum logic [3:0] {
        ST_IDLE,
        ST_RECV_CMD,
        ST_RECV_DATA_1,
        ST_RECV_DATA_2,
        ST_RECV_DATA_3,
        ST_EXECUTE,
        ST_SEND_RESPONSE,
        ST_SEND_DATA,
        ST_BURST_WRITE,
        ST_BURST_READ,
        ST_WAIT_MEM
    } state_t;
    
    state_t state;
    
    //========================================================
    // Registros internos
    //========================================================
    logic [7:0]  cmd_reg;
    logic [7:0]  data_reg_0, data_reg_1, data_reg_2, data_reg_3;
    logic [31:0] burst_count;
    logic [31:0] burst_remaining;
    
    // Registros de configuración
    logic [15:0] img_width_reg;
    logic [15:0] img_height_reg;
    logic [7:0]  scale_factor_reg;
    logic        mode_simd_reg;
    logic [ADDR_WIDTH-1:0] addr_reg;
    
    // Buffer de respuesta
    logic [7:0]  response_buffer_0, response_buffer_1, response_buffer_2, response_buffer_3;
    logic [7:0]  response_buffer_4, response_buffer_5, response_buffer_6, response_buffer_7;
    logic [7:0]  response_buffer_8, response_buffer_9, response_buffer_10, response_buffer_11;
    logic [7:0]  response_buffer_12;
    logic [3:0]  response_len;
    logic [3:0]  response_idx;
    
    //========================================================
    // Asignaciones de salida
    //========================================================
    assign dsa_img_width = img_width_reg;
    assign dsa_img_height = img_height_reg;
    assign dsa_scale_factor = scale_factor_reg;
    assign dsa_mode_simd = mode_simd_reg;
    assign mem_addr = addr_reg;
    
    //========================================================
    // Función para obtener byte del response buffer
    //========================================================
    function logic [7:0] get_response_byte(input logic [3:0] idx);
        case (idx)
            4'd0:  get_response_byte = response_buffer_0;
            4'd1:  get_response_byte = response_buffer_1;
            4'd2:  get_response_byte = response_buffer_2;
            4'd3:  get_response_byte = response_buffer_3;
            4'd4:  get_response_byte = response_buffer_4;
            4'd5:  get_response_byte = response_buffer_5;
            4'd6:  get_response_byte = response_buffer_6;
            4'd7:  get_response_byte = response_buffer_7;
            4'd8:  get_response_byte = response_buffer_8;
            4'd9:  get_response_byte = response_buffer_9;
            4'd10: get_response_byte = response_buffer_10;
            4'd11: get_response_byte = response_buffer_11;
            4'd12: get_response_byte = response_buffer_12;
            default: get_response_byte = 8'h00;
        endcase
    endfunction
    
    //========================================================
    // FSM Principal
    //========================================================
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= ST_IDLE;
            cmd_reg <= 8'h00;
            burst_remaining <= 32'd0;
            
            img_width_reg <= 16'd512;
            img_height_reg <= 16'd512;
            scale_factor_reg <= 8'h80;
            mode_simd_reg <= 1'b0;
            addr_reg <= '0;
            
            dsa_start <= 1'b0;
            mem_write_en <= 1'b0;
            mem_read_en <= 1'b0;
            mem_data_out <= 8'd0;
            
            jtag_rx_ready <= 1'b1;
            jtag_tx_valid <= 1'b0;
            jtag_tx_data <= 8'd0;
            
            response_len <= 4'd0;
            response_idx <= 4'd0;
            
            data_reg_0 <= 8'd0;
            data_reg_1 <= 8'd0;
            data_reg_2 <= 8'd0;
            data_reg_3 <= 8'd0;
            
            response_buffer_0 <= 8'd0;
            response_buffer_1 <= 8'd0;
            response_buffer_2 <= 8'd0;
            response_buffer_3 <= 8'd0;
            response_buffer_4 <= 8'd0;
            response_buffer_5 <= 8'd0;
            response_buffer_6 <= 8'd0;
            response_buffer_7 <= 8'd0;
            response_buffer_8 <= 8'd0;
            response_buffer_9 <= 8'd0;
            response_buffer_10 <= 8'd0;
            response_buffer_11 <= 8'd0;
            response_buffer_12 <= 8'd0;
            
        end else begin
            // Defaults
            dsa_start <= 1'b0;
            mem_write_en <= 1'b0;
            mem_read_en <= 1'b0;
            
            case (state)
                //============================================
                ST_IDLE: begin
                    jtag_rx_ready <= 1'b1;
                    jtag_tx_valid <= 1'b0;
                    
                    if (jtag_rx_valid) begin
                        cmd_reg <= jtag_rx_data;
                        jtag_rx_ready <= 1'b0;
                        state <= ST_RECV_CMD;
                    end
                end
                
                //============================================
                ST_RECV_CMD: begin
                    case (cmd_reg)
                        CMD_SET_WIDTH,
                        CMD_SET_HEIGHT,
                        CMD_SET_SCALE,
                        CMD_SET_MODE,
                        CMD_SET_ADDR,
                        CMD_WRITE_MEM,
                        CMD_WRITE_BURST,
                        CMD_READ_BURST: begin
                            state <= ST_RECV_DATA_1;
                            jtag_rx_ready <= 1'b1;
                        end
                        
                        default: begin
                            state <= ST_EXECUTE;
                        end
                    endcase
                end
                
                //============================================
                ST_RECV_DATA_1: begin
                    if (jtag_rx_valid) begin
                        data_reg_0 <= jtag_rx_data;
                        
                        case (cmd_reg)
                            CMD_SET_WIDTH,
                            CMD_SET_HEIGHT,
                            CMD_SET_ADDR,
                            CMD_WRITE_BURST,
                            CMD_READ_BURST: begin
                                state <= ST_RECV_DATA_2;
                            end
                            
                            default: begin
                                state <= ST_EXECUTE;
                                jtag_rx_ready <= 1'b0;
                            end
                        endcase
                    end
                end
                
                //============================================
                ST_RECV_DATA_2: begin
                    if (jtag_rx_valid) begin
                        data_reg_1 <= jtag_rx_data;
                        
                        case (cmd_reg)
                            CMD_SET_ADDR: begin
                                state <= ST_RECV_DATA_3;
                            end
                            
                            CMD_WRITE_BURST,
                            CMD_READ_BURST: begin
                                burst_count <= {16'd0, data_reg_0, jtag_rx_data};
                                burst_remaining <= {16'd0, data_reg_0, jtag_rx_data};
                                
                                if (cmd_reg == CMD_WRITE_BURST) begin
                                    state <= ST_BURST_WRITE;
                                    jtag_rx_ready <= 1'b1;
                                end else begin
                                    state <= ST_BURST_READ;
                                    jtag_rx_ready <= 1'b0;
                                end
                            end
                            
                            default: begin
                                state <= ST_EXECUTE;
                                jtag_rx_ready <= 1'b0;
                            end
                        endcase
                    end
                end
                
                //============================================
                ST_RECV_DATA_3: begin
                    if (jtag_rx_valid) begin
                        data_reg_2 <= jtag_rx_data;
                        state <= ST_EXECUTE;
                        jtag_rx_ready <= 1'b0;
                    end
                end
                
                //============================================
                ST_EXECUTE: begin
                    response_idx <= 4'd0;
                    
                    case (cmd_reg)
                        CMD_NOP: begin
                            response_buffer_0 <= RSP_OK;
                            response_len <= 4'd1;
                        end
                        
                        CMD_SET_WIDTH: begin
                            img_width_reg <= {data_reg_0, data_reg_1};
                            response_buffer_0 <= RSP_OK;
                            response_len <= 4'd1;
                        end
                        
                        CMD_SET_HEIGHT: begin
                            img_height_reg <= {data_reg_0, data_reg_1};
                            response_buffer_0 <= RSP_OK;
                            response_len <= 4'd1;
                        end
                        
                        CMD_SET_SCALE: begin
                            scale_factor_reg <= data_reg_0;
                            response_buffer_0 <= RSP_OK;
                            response_len <= 4'd1;
                        end
                        
                        CMD_SET_MODE: begin
                            mode_simd_reg <= data_reg_0[0];
                            response_buffer_0 <= RSP_OK;
                            response_len <= 4'd1;
                        end
                        
                        CMD_START: begin
                            if (! dsa_busy) begin
                                dsa_start <= 1'b1;
                                response_buffer_0 <= RSP_OK;
                            end else begin
                                response_buffer_0 <= RSP_BUSY;
                            end
                            response_len <= 4'd1;
                        end
                        
                        CMD_GET_STATUS: begin
                            response_buffer_0 <= RSP_OK;
                            response_buffer_1 <= {6'd0, dsa_ready, dsa_busy};
                            response_len <= 4'd2;
                        end
                        
                        CMD_GET_PROGRESS: begin
                            response_buffer_0 <= RSP_OK;
                            response_buffer_1 <= dsa_progress[15:8];
                            response_buffer_2 <= dsa_progress[7:0];
                            response_len <= 4'd3;
                        end
                        
                        CMD_GET_METRICS: begin
                            response_buffer_0 <= RSP_OK;
                            response_buffer_1 <= dsa_flops_count[31:24];
                            response_buffer_2 <= dsa_flops_count[23:16];
                            response_buffer_3 <= dsa_flops_count[15:8];
                            response_buffer_4 <= dsa_flops_count[7:0];
                            response_buffer_5 <= dsa_mem_reads[31:24];
                            response_buffer_6 <= dsa_mem_reads[23:16];
                            response_buffer_7 <= dsa_mem_reads[15:8];
                            response_buffer_8 <= dsa_mem_reads[7:0];
                            response_buffer_9  <= dsa_mem_writes[31:24];
                            response_buffer_10 <= dsa_mem_writes[23:16];
                            response_buffer_11 <= dsa_mem_writes[15:8];
                            response_buffer_12 <= dsa_mem_writes[7:0];
                            response_len <= 4'd13;
                        end
                        
                        CMD_SET_ADDR: begin
                            addr_reg <= {data_reg_0[ADDR_WIDTH-17:0], data_reg_1, data_reg_2};
                            response_buffer_0 <= RSP_OK;
                            response_len <= 4'd1;
                        end
                        
                        CMD_WRITE_MEM: begin
                            mem_write_en <= 1'b1;
                            mem_data_out <= data_reg_0;
                            addr_reg <= addr_reg + 1;
                            response_buffer_0 <= RSP_OK;
                            response_len <= 4'd1;
                        end
                        
                        CMD_READ_MEM: begin
                            mem_read_en <= 1'b1;
                            state <= ST_WAIT_MEM;
                        end
                        
                        default: begin
                            response_buffer_0 <= RSP_ERROR;
                            response_len <= 4'd1;
                        end
                    endcase
                    
                    if (cmd_reg != CMD_READ_MEM)
                        state <= ST_SEND_RESPONSE;
                end
                
                //============================================
                ST_WAIT_MEM: begin
                    response_buffer_0 <= RSP_OK;
                    response_buffer_1 <= mem_data_in;
                    response_len <= 4'd2;
                    addr_reg <= addr_reg + 1;
                    state <= ST_SEND_RESPONSE;
                end
                
                //============================================
                ST_SEND_RESPONSE: begin
                    if (response_idx < response_len) begin
                        if (jtag_tx_ready || ! jtag_tx_valid) begin
                            jtag_tx_data <= get_response_byte(response_idx);
                            jtag_tx_valid <= 1'b1;
                            response_idx <= response_idx + 1;
                        end
                    end else begin
                        jtag_tx_valid <= 1'b0;
                        state <= ST_IDLE;
                    end
                end
                
                //============================================
                ST_BURST_WRITE: begin
                    if (burst_remaining > 0) begin
                        if (jtag_rx_valid) begin
                            mem_write_en <= 1'b1;
                            mem_data_out <= jtag_rx_data;
                            addr_reg <= addr_reg + 1;
                            burst_remaining <= burst_remaining - 1;
                        end
                    end else begin
                        response_buffer_0 <= RSP_OK;
                        response_len <= 4'd1;
                        state <= ST_SEND_RESPONSE;
                        jtag_rx_ready <= 1'b0;
                    end
                end
                
                //============================================
                ST_BURST_READ: begin
                    if (burst_remaining > 0) begin
                        if (jtag_tx_ready || !jtag_tx_valid) begin
                            mem_read_en <= 1'b1;
                            jtag_tx_data <= mem_data_in;
                            jtag_tx_valid <= 1'b1;
                            addr_reg <= addr_reg + 1;
                            burst_remaining <= burst_remaining - 1;
                        end
                    end else begin
                        jtag_tx_valid <= 1'b0;
                        state <= ST_IDLE;
                    end
                end
                
                default: state <= ST_IDLE;
                
            endcase
        end
    end

endmodule