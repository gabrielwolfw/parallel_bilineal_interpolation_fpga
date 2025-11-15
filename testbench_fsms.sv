// testbench_fsms.sv
// Testbench unitario para dsa_control_fsm
// Prueba el ciclo de procesamiento secuencial y transición de estados.

`timescale 1ns/1ps

module testbench_fsms;

    // Parámetros
    localparam IMG_WIDTH  = 8;
    localparam IMG_HEIGHT = 8;
    localparam TOTAL_PIXELS = IMG_WIDTH * IMG_HEIGHT;

    // Señales del DUT
    logic clk;
    logic rst;
    logic start;
    logic done_pixel;
    logic [15:0] total_pixels;

    logic busy;
    logic ready;
    logic next_pixel;
    logic [15:0] pixel_index;

    // Instancia del DUT
    dsa_control_fsm #(
        .IMG_WIDTH(IMG_WIDTH),
        .IMG_HEIGHT(IMG_HEIGHT)
    ) dut (
        .clk(clk),
        .rst(rst),
        .start(start),
        .done_pixel(done_pixel),
        .total_pixels(total_pixels),
        .busy(busy),
        .ready(ready),
        .next_pixel(next_pixel),
        .pixel_index(pixel_index)
    );

    // Generador de reloj
    initial clk = 0;
    always #5 clk = ~clk; // 100MHz

    // Estímulos
    initial begin
        // Inicialización
        rst = 1;
        start = 0;
        done_pixel = 0;
        total_pixels = TOTAL_PIXELS;

        #20;
        rst = 0;

        // Espera en IDLE
        #10;

        // Inicia procesamiento
        start = 1;
        #10;
        start = 0; // Pulso corto

        // Simula procesamiento de píxeles
        repeat (TOTAL_PIXELS) begin
            #10;
            done_pixel = 1;
            #10;
            done_pixel = 0;
        end

        // Esperar finalización
        #20;

        // Prueba reinicio automático tras S_DONE
        start = 1;
        #10;
        start = 0;

        repeat (TOTAL_PIXELS) begin
            #10;
            done_pixel = 1;
            #10;
            done_pixel = 0;
        end

        #20;

        $display("Testbench FSM finalizado.");
        $stop;
    end

    // Monitoreo
    initial begin
        $display("Tiempo\tstate\tbusy\tready\tnext_pixel\tpixel_index");
        $monitor("%0t\t%b\t%b\t%b\t%b\t%d",
            $time, dut.state, busy, ready, next_pixel, pixel_index);
    end

endmodule