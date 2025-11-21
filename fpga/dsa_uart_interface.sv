//============================================================
// dsa_uart_interface.sv
// Interfaz UART simplificada para comunicación con PC
// Alternativa más simple que JTAG
//============================================================

module dsa_uart_interface #(
    parameter CLK_FREQ = 50_000_000,
    parameter BAUD_RATE = 115200,
    parameter MEM_SIZE = 262144
)(
    input  logic        clk,
    input  logic        rst,
    
    // UART físico
    input  logic        uart_rx,
    output logic        uart_tx,
    
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
    input  logic [31:0] dsa_mem_writes_count
);

    //=================================================================
    // UART RX/TX básico
    //=================================================================
    
    logic       rx_valid;
    logic [7:0] rx_data;
    logic       tx_ready;
    logic       tx_valid;
    logic [7:0] tx_data;
    
    uart_rx #(
        .CLK_FREQ(CLK_FREQ),
        .BAUD_RATE(BAUD_RATE)
    ) uart_rx_inst (
        .clk(clk),
        .rst(rst),
        .rx(uart_rx),
        .data_out(rx_data),
        .valid(rx_valid)
    );
    
    uart_tx #(
        .CLK_FREQ(CLK_FREQ),
        .BAUD_RATE(BAUD_RATE)
    ) uart_tx_inst (
        .clk(clk),
        .rst(rst),
        .tx(uart_tx),
        .data_in(tx_data),
        .valid(tx_valid),
        .ready(tx_ready)
    );
    
    //=================================================================
    // Protocolo de comandos
    //=================================================================
    
    // Comandos de 1 byte
    localparam CMD_WRITE_CONFIG  = 8'h01;
    localparam CMD_WRITE_MEM     = 8'h02;
    localparam CMD_READ_MEM      = 8'h03;
    localparam CMD_START         = 8'h04;
    localparam CMD_STATUS        = 8'h05;
    localparam CMD_COUNTERS      = 8'h06;
    localparam CMD_SET_ADDR      = 8'h07;
    localparam CMD_RESET         = 8'h08;
    localparam CMD_ACK           = 8'hAA;
    localparam CMD_NAK           = 8'hFF;
    
    //=================================================================
    // FSM de procesamiento de comandos
    //=================================================================
    
    typedef enum logic [3:0] {
        ST_IDLE,
        ST_CMD,
        ST_PAYLOAD_0,
        ST_PAYLOAD_1,
        ST_PAYLOAD_2,
        ST_PAYLOAD_3,
        ST_EXECUTE,
        ST_SEND_ACK,
        ST_SEND_DATA_0,
        ST_SEND_DATA_1,
        ST_SEND_DATA_2,
        ST_SEND_DATA_3
    } uart_state_t;
    
    uart_state_t state, next_state;
    
    logic [7:0]  cmd_reg;
    logic [31:0] payload_reg;
    logic [1:0]  payload_counter;
    logic [1:0]  response_counter;
    logic [31:0] response_data;
    
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= ST_IDLE;
            cmd_reg <= 8'h0;
            payload_reg <= 32'h0;
            payload_counter <= 2'h0;
            response_counter <= 2'h0;
        end else begin
            state <= next_state;
            
            if (state == ST_CMD && rx_valid) begin
                cmd_reg <= rx_data;
            end
            
            if (state == ST_PAYLOAD_0 && rx_valid) begin
                payload_reg[7:0] <= rx_data;
                payload_counter <= 2'h1;
            end else if (state == ST_PAYLOAD_1 && rx_valid) begin
                payload_reg[15:8] <= rx_data;
                payload_counter <= 2'h2;
            end else if (state == ST_PAYLOAD_2 && rx_valid) begin
                payload_reg[23:16] <= rx_data;
                payload_counter <= 2'h3;
            end else if (state == ST_PAYLOAD_3 && rx_valid) begin
                payload_reg[31:24] <= rx_data;
                payload_counter <= 2'h0;
            end
            
            if (state == ST_SEND_DATA_0 && tx_ready) begin
                response_counter <= 2'h1;
            end else if (state == ST_SEND_DATA_1 && tx_ready) begin
                response_counter <= 2'h2;
            end else if (state == ST_SEND_DATA_2 && tx_ready) begin
                response_counter <= 2'h3;
            end else if (state == ST_SEND_DATA_3 && tx_ready) begin
                response_counter <= 2'h0;
            end
        end
    end
    
    //=================================================================
    // Lógica de transición de estados
    //=================================================================
    
    always_comb begin
        next_state = state;
        
        case (state)
            ST_IDLE: begin
                if (rx_valid)
                    next_state = ST_CMD;
            end
            
            ST_CMD: begin
                if (rx_valid) begin
                    case (rx_data)
                        CMD_WRITE_CONFIG,
                        CMD_WRITE_MEM,
                        CMD_SET_ADDR:
                            next_state = ST_PAYLOAD_0;
                        CMD_START,
                        CMD_READ_MEM,
                        CMD_STATUS,
                        CMD_COUNTERS,
                        CMD_RESET:
                            next_state = ST_EXECUTE;
                        default:
                            next_state = ST_IDLE;
                    endcase
                end
            end
            
            ST_PAYLOAD_0: begin
                if (rx_valid)
                    next_state = ST_PAYLOAD_1;
            end
            
            ST_PAYLOAD_1: begin
                if (rx_valid)
                    next_state = ST_PAYLOAD_2;
            end
            
            ST_PAYLOAD_2: begin
                if (rx_valid)
                    next_state = ST_PAYLOAD_3;
            end
            
            ST_PAYLOAD_3: begin
                if (rx_valid)
                    next_state = ST_EXECUTE;
            end
            
            ST_EXECUTE: begin
                next_state = ST_SEND_ACK;
            end
            
            ST_SEND_ACK: begin
                if (tx_ready) begin
                    if (cmd_reg == CMD_STATUS || cmd_reg == CMD_COUNTERS || cmd_reg == CMD_READ_MEM)
                        next_state = ST_SEND_DATA_0;
                    else
                        next_state = ST_IDLE;
                end
            end
            
            ST_SEND_DATA_0: begin
                if (tx_ready)
                    next_state = ST_SEND_DATA_1;
            end
            
            ST_SEND_DATA_1: begin
                if (tx_ready)
                    next_state = ST_SEND_DATA_2;
            end
            
            ST_SEND_DATA_2: begin
                if (tx_ready)
                    next_state = ST_SEND_DATA_3;
            end
            
            ST_SEND_DATA_3: begin
                if (tx_ready)
                    next_state = ST_IDLE;
            end
            
            default: next_state = ST_IDLE;
        endcase
    end
    
    //=================================================================
    // Lógica de ejecución de comandos
    //=================================================================
    
    logic [17:0] mem_addr_reg;
    logic [9:0]  img_width_reg;
    logic [9:0]  img_height_reg;
    logic [7:0]  scale_factor_reg;
    logic        mode_simd_reg;
    
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
            response_data <= 32'h0;
        end else begin
            dsa_start <= 1'b0;
            dsa_mem_write_en <= 1'b0;
            dsa_mem_read_en <= 1'b0;
            
            if (state == ST_EXECUTE) begin
                case (cmd_reg)
                    CMD_WRITE_CONFIG: begin
                        img_width_reg <= payload_reg[31:22];
                        img_height_reg <= payload_reg[21:12];
                        scale_factor_reg <= payload_reg[11:4];
                        mode_simd_reg <= payload_reg[0];
                    end
                    
                    CMD_SET_ADDR: begin
                        mem_addr_reg <= payload_reg[17:0];
                    end
                    
                    CMD_WRITE_MEM: begin
                        dsa_mem_write_en <= 1'b1;
                    end
                    
                    CMD_READ_MEM: begin
                        dsa_mem_read_en <= 1'b1;
                        response_data <= {24'h0, dsa_mem_data_out};
                    end
                    
                    CMD_START: begin
                        dsa_start <= 1'b1;
                    end
                    
                    CMD_STATUS: begin
                        response_data <= {
                            16'h0,
                            dsa_progress,
                            5'h0,
                            dsa_error,
                            dsa_ready,
                            dsa_busy
                        };
                    end
                    
                    CMD_COUNTERS: begin
                        response_data <= dsa_flops_count;
                    end
                    
                    default: begin
                    end
                endcase
            end
        end
    end
    
    //=================================================================
    // Lógica de transmisión
    //=================================================================
    
    always_comb begin
        tx_valid = 1'b0;
        tx_data = 8'h0;
        
        case (state)
            ST_SEND_ACK: begin
                tx_valid = 1'b1;
                tx_data = CMD_ACK;
            end
            
            ST_SEND_DATA_0: begin
                tx_valid = 1'b1;
                tx_data = response_data[7:0];
            end
            
            ST_SEND_DATA_1: begin
                tx_valid = 1'b1;
                tx_data = response_data[15:8];
            end
            
            ST_SEND_DATA_2: begin
                tx_valid = 1'b1;
                tx_data = response_data[23:16];
            end
            
            ST_SEND_DATA_3: begin
                tx_valid = 1'b1;
                tx_data = response_data[31:24];
            end
            
            default: begin
                tx_valid = 1'b0;
            end
        endcase
    end
    
    //=================================================================
    // Asignaciones de salida
    //=================================================================
    
    assign dsa_img_width_in = img_width_reg;
    assign dsa_img_height_in = img_height_reg;
    assign dsa_scale_factor = scale_factor_reg;
    assign dsa_mode_simd = mode_simd_reg;
    assign dsa_mem_addr = mem_addr_reg;
    assign dsa_mem_data_in = payload_reg[7:0];

endmodule