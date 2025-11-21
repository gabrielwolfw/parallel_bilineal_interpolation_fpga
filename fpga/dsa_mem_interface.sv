//============================================================
// dsa_mem_interface.sv
// Interfaz simple de memoria interna (M10K/BRAM simulada)
// Soporta lectura y escritura byte a byte
//============================================================

module dsa_mem_interface #(
    parameter MEM_SIZE = 262144  // 512x512 = 262,144 bytes
)(
    input  logic        clk,
    input  logic        read_en,
    input  logic        write_en,
    input  logic [17:0] addr,       // direccion (18 bits para 262K posiciones)
    input  logic [7:0]  data_in,
    output logic [7:0]  data_out
);

    // Memoria interna simulada
    logic [7:0] mem [0:MEM_SIZE-1];

    always_ff @(posedge clk) begin
        if (read_en)
            data_out <= mem[addr];

        if (write_en)
            mem[addr] <= data_in;
    end

    // Inicialización opcional (para simulación)
    initial begin
        integer i;
        for (i = 0; i < MEM_SIZE; i = i + 1)
            mem[i] = 8'd0;
    end

endmodule