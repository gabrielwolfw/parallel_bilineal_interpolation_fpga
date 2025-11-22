//============================================================
// dsa_mem_interface.sv (compatible Quartus)
// Interfaz simple de memoria interna (M10K/BRAM)
//============================================================

module dsa_mem_interface #(
    parameter MEM_SIZE = 262144,  // 512x512
    parameter ADDR_WIDTH = 18
)(
    input  logic                    clk,
    input  logic                    read_en,
    input  logic                    write_en,
    input  logic [ADDR_WIDTH-1:0]   addr,
    input  logic [7:0]              data_in,
    output logic [7:0]              data_out
);

    // Memoria interna
    logic [7:0] mem [0:MEM_SIZE-1];

    always_ff @(posedge clk) begin
        if (read_en) begin
            data_out <= mem[addr];
        end

        if (write_en) begin
            mem[addr] <= data_in;
        end
    end

endmodule