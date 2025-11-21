url=
//============================================================
// uart_rx.sv
// Receptor UART simple
//============================================================

module uart_rx #(
    parameter CLK_FREQ = 50_000_000,
    parameter BAUD_RATE = 115200
)(
    input  logic       clk,
    input  logic       rst,
    input  logic       rx,
    output logic [7:0] data_out,
    output logic       valid
);

    localparam CLKS_PER_BIT = CLK_FREQ / BAUD_RATE;
    
    typedef enum logic [2:0] {
        IDLE,
        START_BIT,
        DATA_BITS,
        STOP_BIT
    } state_t;
    
    state_t state;
    logic [$clog2(CLKS_PER_BIT)-1:0] clk_count;
    logic [2:0] bit_index;
    logic [7:0] rx_byte;
    logic       rx_sync_1, rx_sync_2;
    
    // Sincronización de entrada
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            rx_sync_1 <= 1'b1;
            rx_sync_2 <= 1'b1;
        end else begin
            rx_sync_1 <= rx;
            rx_sync_2 <= rx_sync_1;
        end
    end
    
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= IDLE;
            clk_count <= 0;
            bit_index <= 0;
            rx_byte <= 0;
            valid <= 0;
        end else begin
            valid <= 0;
            
            case (state)
                IDLE: begin
                    clk_count <= 0;
                    bit_index <= 0;
                    if (rx_sync_2 == 0) begin
                        state <= START_BIT;
                    end
                end
                
                START_BIT: begin
                    if (clk_count == (CLKS_PER_BIT-1)/2) begin
                        if (rx_sync_2 == 0) begin
                            clk_count <= 0;
                            state <= DATA_BITS;
                        end else begin
                            state <= IDLE;
                        end
                    end else begin
                        clk_count <= clk_count + 1;
                    end
                end
                
                DATA_BITS: begin
                    if (clk_count < CLKS_PER_BIT-1) begin
                        clk_count <= clk_count + 1;
                    end else begin
                        clk_count <= 0;
                        rx_byte[bit_index] <= rx_sync_2;
                        
                        if (bit_index < 7) begin
                            bit_index <= bit_index + 1;
                        end else begin
                            bit_index <= 0;
                            state <= STOP_BIT;
                        end
                    end
                end
                
                STOP_BIT: begin
                    if (clk_count < CLKS_PER_BIT-1) begin
                        clk_count <= clk_count + 1;
                    end else begin
                        clk_count <= 0;
                        valid <= 1;
                        data_out <= rx_byte;
                        state <= IDLE;
                    end
                end
                
                default: state <= IDLE;
            endcase
        end
    end

endmodule