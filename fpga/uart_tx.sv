//============================================================
// uart_tx.sv
// Transmisor UART simple
//============================================================

module uart_tx #(
    parameter CLK_FREQ = 50_000_000,
    parameter BAUD_RATE = 115200
)(
    input  logic       clk,
    input  logic       rst,
    output logic       tx,
    input  logic [7:0] data_in,
    input  logic       valid,
    output logic       ready
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
    logic [7:0] tx_byte;
    
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= IDLE;
            clk_count <= 0;
            bit_index <= 0;
            tx_byte <= 0;
            tx <= 1'b1;
            ready <= 1'b1;
        end else begin
            case (state)
                IDLE: begin
                    tx <= 1'b1;
                    clk_count <= 0;
                    bit_index <= 0;
                    ready <= 1'b1;
                    
                    if (valid) begin
                        tx_byte <= data_in;
                        state <= START_BIT;
                        ready <= 1'b0;
                    end
                end
                
                START_BIT: begin
                    tx <= 1'b0;
                    
                    if (clk_count < CLKS_PER_BIT-1) begin
                        clk_count <= clk_count + 1;
                    end else begin
                        clk_count <= 0;
                        state <= DATA_BITS;
                    end
                end
                
                DATA_BITS: begin
                    tx <= tx_byte[bit_index];
                    
                    if (clk_count < CLKS_PER_BIT-1) begin
                        clk_count <= clk_count + 1;
                    end else begin
                        clk_count <= 0;
                        
                        if (bit_index < 7) begin
                            bit_index <= bit_index + 1;
                        end else begin
                            bit_index <= 0;
                            state <= STOP_BIT;
                        end
                    end
                end
                
                STOP_BIT: begin
                    tx <= 1'b1;
                    
                    if (clk_count < CLKS_PER_BIT-1) begin
                        clk_count <= clk_count + 1;
                    end else begin
                        clk_count <= 0;
                        state <= IDLE;
                    end
                end
                
                default: state <= IDLE;
            endcase
        end
    end

endmodule