//============================================================
// testbench.sv
// Prueba funcional del modo secuencial de interpolación bilineal
//============================================================

`timescale 1ns/1ps

module dsa_interpolation_tb;

    // Señales de prueba
    logic clk;
    logic rst;
    logic start;
    logic [7:0] p00, p01, p10, p11;
    logic [15:0] a, b;
    logic [7:0] pixel_out;
    logic done;

    // Instancia del datapath
    dsa_datapath uut (
        .clk(clk),
        .rst(rst),
        .start(start),
        .p00(p00), .p01(p01), .p10(p10), .p11(p11),
        .a(a), .b(b),
        .pixel_out(pixel_out),
        .done(done)
    );

    // Generador de reloj
    always #5 clk = ~clk;

    initial begin
        $display("===============================================");
        $display("   TESTBENCH INTERPOLACIÓN BILINEAL SECUENCIAL ");
        $display("===============================================");

        // Inicialización
        clk = 0;
        rst = 1;
        start = 0;
        #20 rst = 0;

        // Caso 1: interpolación 0.5, 0.5 (promedio de 4 píxeles)
        p00 = 8'd100; 
        p01 = 8'd120;
        p10 = 8'd140; 
        p11 = 8'd160;
        a = 16'h0080; // 0.5
        b = 16'h0080; // 0.5

        $display("\nCaso 1: a=0.5, b=0.5, pixeles=[100,120,140,160]");
        start = 1; #10 start = 0;
        wait(done);
        #2;
        $display("Resultado: %d (Esperado ≈ 130)", pixel_out);

        // Caso 2: a=0.25, b=0.75
        p00 = 8'd50; 
        p01 = 8'd150;
        p10 = 8'd100; 
        p11 = 8'd200;
        a = 16'h0040; // 0.25
        b = 16'h00C0; // 0.75

        $display("\nCaso 2: a=0.25, b=0.75, pixeles=[50,150,100,200]");
        start = 1; #10 start = 0;
        wait(done);
        #2;
        $display("Resultado: %d", pixel_out);

        // Fin de simulación
        #20;
        $display("\n TEST COMPLETADO CORRECTAMENTE");
        $stop;
    end

endmodule