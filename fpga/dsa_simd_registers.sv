//=====================================================================
// dsa_simd_registers. sv
// Registros SIMD completos para buffering de píxeles
// CORREGIDO: clear_all es síncrono, solo rst es asíncrono
//=====================================================================

module dsa_simd_registers #(
    parameter N = 4
)(
    input  logic        clk,
    input  logic        rst,
    
    input  logic        load_pixels_en,
    input  logic        load_coef_en,
    input  logic        load_weights_en,
    input  logic        load_output_en,
    input  logic        clear_all,
    
    input  logic [7:0]  in_p00 [0:N-1],
    input  logic [7:0]  in_p01 [0:N-1],
    input  logic [7:0]  in_p10 [0:N-1],
    input  logic [7:0]  in_p11 [0:N-1],
    
    output logic [7:0]  out_p00 [0:N-1],
    output logic [7:0]  out_p01 [0:N-1],
    output logic [7:0]  out_p10 [0:N-1],
    output logic [7:0]  out_p11 [0:N-1],
    
    input  logic [15:0] in_coef_a [0:N-1],
    input  logic [15:0] in_coef_b [0:N-1],
    
    output logic [15:0] out_coef_a [0:N-1],
    output logic [15:0] out_coef_b [0:N-1],
    
    input  logic [23:0] in_weighted_00 [0:N-1],
    input  logic [23:0] in_weighted_01 [0:N-1],
    input  logic [23:0] in_weighted_10 [0:N-1],
    input  logic [23:0] in_weighted_11 [0:N-1],
    
    output logic [23:0] out_weighted_00 [0:N-1],
    output logic [23:0] out_weighted_01 [0:N-1],
    output logic [23:0] out_weighted_10 [0:N-1],
    output logic [23:0] out_weighted_11 [0:N-1],
    
    input  logic [7:0]  in_pixel_out [0:N-1],
    output logic [7:0]  out_pixel_out [0:N-1],
    
    output logic        pixels_valid,
    output logic        coef_valid,
    output logic        weights_valid,
    output logic        output_valid
);

    logic pixels_loaded;
    logic coef_loaded;
    logic weights_loaded;
    logic output_loaded;
    
    //=================================================================
    // REG 1-4: Píxeles de entrada
    //=================================================================
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            for (int i = 0; i < N; i = i + 1) begin
                out_p00[i] <= 8'd0;
                out_p01[i] <= 8'd0;
                out_p10[i] <= 8'd0;
                out_p11[i] <= 8'd0;
            end
            pixels_loaded <= 1'b0;
        end else if (clear_all) begin
            for (int i = 0; i < N; i = i + 1) begin
                out_p00[i] <= 8'd0;
                out_p01[i] <= 8'd0;
                out_p10[i] <= 8'd0;
                out_p11[i] <= 8'd0;
            end
            pixels_loaded <= 1'b0;
        end else if (load_pixels_en) begin
            for (int i = 0; i < N; i = i + 1) begin
                out_p00[i] <= in_p00[i];
                out_p01[i] <= in_p01[i];
                out_p10[i] <= in_p10[i];
                out_p11[i] <= in_p11[i];
            end
            pixels_loaded <= 1'b1;
        end
    end
    
    //=================================================================
    // REG 5-6: Coeficientes fraccionarios
    //=================================================================
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            for (int i = 0; i < N; i = i + 1) begin
                out_coef_a[i] <= 16'd0;
                out_coef_b[i] <= 16'd0;
            end
            coef_loaded <= 1'b0;
        end else if (clear_all) begin
            for (int i = 0; i < N; i = i + 1) begin
                out_coef_a[i] <= 16'd0;
                out_coef_b[i] <= 16'd0;
            end
            coef_loaded <= 1'b0;
        end else if (load_coef_en) begin
            for (int i = 0; i < N; i = i + 1) begin
                out_coef_a[i] <= in_coef_a[i];
                out_coef_b[i] <= in_coef_b[i];
            end
            coef_loaded <= 1'b1;
        end
    end
    
    //=================================================================
    // REG 7: Productos ponderados
    //=================================================================
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            for (int i = 0; i < N; i = i + 1) begin
                out_weighted_00[i] <= 24'd0;
                out_weighted_01[i] <= 24'd0;
                out_weighted_10[i] <= 24'd0;
                out_weighted_11[i] <= 24'd0;
            end
            weights_loaded <= 1'b0;
        end else if (clear_all) begin
            for (int i = 0; i < N; i = i + 1) begin
                out_weighted_00[i] <= 24'd0;
                out_weighted_01[i] <= 24'd0;
                out_weighted_10[i] <= 24'd0;
                out_weighted_11[i] <= 24'd0;
            end
            weights_loaded <= 1'b0;
        end else if (load_weights_en) begin
            for (int i = 0; i < N; i = i + 1) begin
                out_weighted_00[i] <= in_weighted_00[i];
                out_weighted_01[i] <= in_weighted_01[i];
                out_weighted_10[i] <= in_weighted_10[i];
                out_weighted_11[i] <= in_weighted_11[i];
            end
            weights_loaded <= 1'b1;
        end
    end
    
    //=================================================================
    // REG 8: Píxeles de salida
    //=================================================================
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            for (int i = 0; i < N; i = i + 1) begin
                out_pixel_out[i] <= 8'd0;
            end
            output_loaded <= 1'b0;
        end else if (clear_all) begin
            for (int i = 0; i < N; i = i + 1) begin
                out_pixel_out[i] <= 8'd0;
            end
            output_loaded <= 1'b0;
        end else if (load_output_en) begin
            for (int i = 0; i < N; i = i + 1) begin
                out_pixel_out[i] <= in_pixel_out[i];
            end
            output_loaded <= 1'b1;
        end
    end
    
    //=================================================================
    // Señales de validez
    //=================================================================
    assign pixels_valid = pixels_loaded;
    assign coef_valid = coef_loaded;
    assign weights_valid = weights_loaded;
    assign output_valid = output_loaded;

endmodule