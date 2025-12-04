`timescale 1ns/1ps

module dsa_simd_tb;

    parameter N = 4; // Cantidad de lanes

    // Señales
    logic clk;
    logic rst;
    logic start;
    logic [7:0]  p00 [0:N-1];
    logic [7:0]  p01 [0:N-1];
    logic [7:0]  p10 [0:N-1];
    logic [7:0]  p11 [0:N-1];
    logic [15:0] a  [0:N-1];
    logic [15:0] b  [0:N-1];
    logic [7:0]  pixel_out [0:N-1];
    logic done;

    integer i;

    // Instancia datapath SIMD
    dsa_datapath_simd #(.N(N)) uut (
        .clk(clk),
        .rst(rst),
        .start(start),
        .p00(p00), .p01(p01), .p10(p10), .p11(p11),
        .a(a), .b(b),
        .pixel_out(pixel_out),
        .done(done)
    );

    // Reloj
    always #5 clk = ~clk;

    initial begin
        $display("===============================================");
        $display("        TESTBENCH SIMD INTERPOLACIÓN          ");
        $display("===============================================");

        clk = 0;
        rst = 1;
        start = 0;
        #20 rst = 0;

        // ===== CASO 1 =====
        $display("\n=== CASO 1 ===");

        for (i=0; i<N; i=i+1) begin
            p00[i] = 8'd100;
            p01[i] = 8'd120;
            p10[i] = 8'd140;
            p11[i] = 8'd160;
            a[i] = 16'd128; // 0.5 Q8.8
            b[i] = 16'd128; // 0.5 Q8.8
        end

        start = 1; #10 start = 0;
        wait(done); #2;

        for (i=0; i<N; i=i+1)
            $display("Lane %0d = %0d (esperado ~130)", i, pixel_out[i]);

        // ===== CASO 2 =====
        $display("\n=== CASO 2 ===");

        for (i=0; i<N; i=i+1) begin
            p00[i] = 8'd50;
            p01[i] = 8'd150;
            p10[i] = 8'd100;
            p11[i] = 8'd200;
            a[i] = 16'd64;  // 0.25 Q8.8
            b[i] = 16'd192; // 0.75 Q8.8
        end

        start = 1; #10 start = 0;
        wait(done); #2;

        for (i=0; i<N; i=i+1)
            $display("Lane %0d = %0d", i, pixel_out[i]);

        $display("\n---- TEST COMPLETADO CORRECTAMENTE ----");
        $stop;
    end

endmodule