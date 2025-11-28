//============================================================
// jtag_avalon_adapter.sv
// Convierte interfaz Avalon-MM del JTAG UART a streaming
// Nota: read_n y write_n son active-low
//============================================================

module jtag_avalon_adapter (
    input  logic        clk,
    input  logic        rst,
    
    // Avalon-MM (hacia JTAG UART IP)
    output logic        av_chipselect,
    output logic        av_address,
    output logic        av_read_n,      // Active low
    output logic        av_write_n,     // Active low
    input  logic [31:0] av_readdata,
    output logic [31:0] av_writedata,
    input  logic        av_waitrequest,
    
    // Streaming (hacia dsa_jtag_interface)
    output logic [7:0]  rx_data,
    output logic        rx_valid,
    input  logic        rx_ready,
    input  logic [7:0]  tx_data,
    input  logic        tx_valid,
    output logic        tx_ready
);

    typedef enum logic [2:0] {
        ST_IDLE,
        ST_CHECK_RX,
        ST_CHECK_TX,
        ST_WRITE_TX,
        ST_WAIT
    } state_t;
    
    state_t state;
    
    logic [7:0]  rx_data_reg;
    logic        rx_valid_reg;
    logic        tx_pending;
    logic [7:0]  tx_data_reg;
    
    assign rx_data = rx_data_reg;
    assign rx_valid = rx_valid_reg;
    assign tx_ready = ! tx_pending && (state == ST_IDLE);
    assign av_chipselect = 1'b1;  // Siempre seleccionado
    
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= ST_IDLE;
            av_address <= 1'b0;
            av_read_n <= 1'b1;   // Inactivo (high)
            av_write_n <= 1'b1;  // Inactivo (high)
            av_writedata <= 32'd0;
            rx_data_reg <= 8'd0;
            rx_valid_reg <= 1'b0;
            tx_pending <= 1'b0;
            tx_data_reg <= 8'd0;
        end else begin
            // Limpiar valid después de que se consuma
            if (rx_valid_reg && rx_ready)
                rx_valid_reg <= 1'b0;
            
            case (state)
                ST_IDLE: begin
                    av_read_n <= 1'b1;
                    av_write_n <= 1'b1;
                    
                    // Capturar dato TX si hay
                    if (tx_valid && !tx_pending) begin
                        tx_pending <= 1'b1;
                        tx_data_reg <= tx_data;
                    end
                    
                    // Prioridad: verificar RX
                    if (rx_ready && !rx_valid_reg) begin
                        av_address <= 1'b0;  // Data register
                        av_read_n <= 1'b0;   // Activar lectura
                        state <= ST_CHECK_RX;
                    end
                    // Luego TX
                    else if (tx_pending) begin
                        av_address <= 1'b1;  // Control register
                        av_read_n <= 1'b0;   // Leer para verificar espacio
                        state <= ST_CHECK_TX;
                    end
                end
                
                ST_CHECK_RX: begin
                    if (! av_waitrequest) begin
                        av_read_n <= 1'b1;
                        
                        // Bit 15 = RVALID
                        if (av_readdata[15]) begin
                            rx_data_reg <= av_readdata[7:0];
                            rx_valid_reg <= 1'b1;
                        end
                        
                        state <= ST_IDLE;
                    end
                end
                
                ST_CHECK_TX: begin
                    if (!av_waitrequest) begin
                        av_read_n <= 1'b1;
                        
                        // [31:16] = WSPACE (espacio disponible)
                        if (av_readdata[31:16] > 0) begin
                            state <= ST_WRITE_TX;
                        end else begin
                            state <= ST_IDLE;
                        end
                    end
                end
                
                ST_WRITE_TX: begin
                    av_address <= 1'b0;  // Data register
                    av_write_n <= 1'b0;  // Activar escritura
                    av_writedata <= {24'd0, tx_data_reg};
                    state <= ST_WAIT;
                end
                
                ST_WAIT: begin
                    if (!av_waitrequest) begin
                        av_write_n <= 1'b1;
                        tx_pending <= 1'b0;
                        state <= ST_IDLE;
                    end
                end
                
                default: state <= ST_IDLE;
            endcase
        end
    end

endmodule