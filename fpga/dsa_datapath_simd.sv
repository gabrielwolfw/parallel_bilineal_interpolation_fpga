//============================================================
// dsa_datapath_simd.sv
// Datapath SIMD para interpolación bilineal (N píxeles/ciclo)
// Formato Q8.8 (16 bits total)
//============================================================

module dsa_datapath_simd #(parameter N = 4)(
    input  logic        clk,
    input  logic        rst,
    input  logic        start,
    input  logic [7:0]  p00 [0:N-1],
    input  logic [7:0]  p01 [0:N-1],
    input  logic [7:0]  p10 [0:N-1],
    input  logic [7:0]  p11 [0:N-1],
    input  logic [15:0] a  [0:N-1],
    input  logic [15:0] b  [0:N-1],
    output logic [7:0]  pixel_out [0:N-1],
    output logic        done
);

    logic [15:0] one_fixed;
    logic [31:0] w00 [0:N-1], w01 [0:N-1], w10 [0:N-1], w11 [0:N-1];
    logic [31:0] interp_sum [0:N-1];

    assign one_fixed = 16'h0100; // 1.0 en Q8.8

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            done <= 0;
            for (int i=0; i<N; i=i+1)
                pixel_out[i] <= 0;
        end else if (start) begin
            for (int i=0; i<N; i=i+1) begin
                // Pesos Q8.8
                w00[i] = ((one_fixed - a[i]) * (one_fixed - b[i])) >> 8;
                w10[i] = (a[i] * (one_fixed - b[i])) >> 8;
                w01[i] = ((one_fixed - a[i]) * b[i]) >> 8;
                w11[i] = (a[i] * b[i]) >> 8;

                // Suma ponderada Q8.8
                interp_sum[i] = (p00[i]*w00[i] + p10[i]*w10[i] + p01[i]*w01[i] + p11[i]*w11[i]) >> 8;

                // Saturación a 8 bits
                pixel_out[i] <= (interp_sum[i] > 255) ? 8'd255 : interp_sum[i][7:0];
            end
            done <= 1;
        end else begin
            done <= 0;
        end
    end

endmodule