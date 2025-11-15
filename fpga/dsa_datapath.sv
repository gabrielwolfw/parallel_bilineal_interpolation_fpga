//============================================================
// dsa_datapath.sv
// Datapath secuencial para interpolación bilineal (1 píxel/ciclo)
// Formato Q8.8 (16 bits total)
//============================================================

module dsa_datapath (
    input  logic        clk,
    input  logic        rst,
    input  logic        start,
    input  logic [7:0]  p00, p01, p10, p11,   // píxeles vecinos (8 bits)
    input  logic [15:0] a, b,                 // coeficientes fraccionarios Q8.8
    output logic [7:0]  pixel_out,            // píxel interpolado (8 bits)
    output logic        done
);

    // Señales internas (Q8.8 -> 16 bits)
    logic [15:0] one_fixed;
    logic [31:0] w00, w01, w10, w11;
    logic [31:0] interp_sum;

    assign one_fixed = 16'h0100; // 1.0 en Q8.8

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            done      <= 0;
            pixel_out <= 0;
        end else if (start) begin
            // Pesos: (1−a)(1−b), a(1−b), (1−a)b, ab
            w00 = ((one_fixed - a) * (one_fixed - b)) >> 8;
            w10 = (a * (one_fixed - b)) >> 8;
            w01 = ((one_fixed - a) * b) >> 8;
            w11 = (a * b) >> 8;

				// Suma ponderada: salida en Q8.8
            interp_sum = (p00*w00 + p10*w10 + p01*w01 + p11*w11) >> 8;

            // Truncar y saturar
            if (interp_sum[23:8] > 255)
                pixel_out <= 8'd255;
            else
                pixel_out <= interp_sum[15:8];

            // Saturación y truncamiento a 8 bits
            pixel_out <= (interp_sum > 255) ? 8'd255 : interp_sum[7:0];
            done      <= 1;
        end else begin
            done <= 0;
        end
    end

endmodule
