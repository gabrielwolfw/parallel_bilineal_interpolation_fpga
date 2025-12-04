//=====================================================================
// dsa_simd_registers.sv
// Registros SIMD para buffering de pixeles
//=====================================================================

module dsa_simd_registers #(
    parameter N = 4
)(
    input  logic clk,
    input  logic rst,
    input  logic load_en,

    input  logic [7:0] in_p00 [0:N-1],
    input  logic [7:0] in_p01 [0:N-1],
    input  logic [7:0] in_p10 [0:N-1],
    input  logic [7:0] in_p11 [0:N-1],

    output logic [7:0] out_p00 [0:N-1],
    output logic [7:0] out_p01 [0:N-1],
    output logic [7:0] out_p10 [0:N-1],
    output logic [7:0] out_p11 [0:N-1]
);

    integer i;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            for (i = 0; i < N; i++) begin
                out_p00[i] <= 0;
                out_p01[i] <= 0;
                out_p10[i] <= 0;
                out_p11[i] <= 0;
            end
        end

        else if (load_en) begin
            for (i = 0; i < N; i++) begin
                out_p00[i] <= in_p00[i];
                out_p01[i] <= in_p01[i];
                out_p10[i] <= in_p10[i];
                out_p11[i] <= in_p11[i];
            end
        end
    end

endmodule