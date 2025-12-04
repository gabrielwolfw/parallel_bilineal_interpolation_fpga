//============================================================
// dsa_datapath.sv
// Datapath secuencial para interpolación bilineal (1 píxel/ciclo)
// Formato Q8.8 (16 bits total)
// CORREGIDO: Sin doble asignación
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

    //========================================================
    // Señales internas
    //========================================================
    logic [15:0] one_fixed;
    logic [23:0] w00, w01, w10, w11;  // Pesos en Q8.8
    logic [31:0] interp_sum;          // Suma ponderada
    logic [15:0] result_q8_8;         // Resultado en Q8.8

    assign one_fixed = 16'h0100; // 1.0 en Q8.8 (256 en decimal)

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            done      <= 1'b0;
            pixel_out <= 8'd0;
        end else if (start) begin
            //========================================================
            // PASO 1: Calcular pesos bilineales en Q8.8
            // w00 = (1-a)(1-b)
            // w01 = (1-a)b
            // w10 = a(1-b)
            // w11 = ab
            //========================================================
            w00 = ((one_fixed - a) * (one_fixed - b)) >> 8;
            w10 = (a * (one_fixed - b)) >> 8;
            w01 = ((one_fixed - a) * b) >> 8;
            w11 = (a * b) >> 8;

            //========================================================
            // PASO 2: Suma ponderada
            // Cada término: píxel(8 bits) × peso(16 bits Q8.8) = 24 bits
            // Suma de 4 términos puede llegar a 26 bits
            //========================================================
            interp_sum = (p00 * w00) + (p01 * w01) + (p10 * w10) + (p11 * w11);
            
            //========================================================
            // PASO 3: Convertir de Q16.8 a Q8.8 (shift right 8)
            //========================================================
            // Después del shift:
            // - Bits [15:8]: parte entera (el resultado que queremos)
            // - Bits [7:0]: parte fraccionaria (descartamos)
            result_q8_8 = interp_sum[23:8];
            
            //========================================================
            // PASO 4: Saturar a 8 bits [0, 255]
            //========================================================
            if (result_q8_8 > 16'd255) begin
                pixel_out <= 8'd255;
            end else begin
                pixel_out <= result_q8_8[7:0];
            end
            
            done <= 1'b1;
        end else begin
            done <= 1'b0;
        end
    end

endmodule