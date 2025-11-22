//============================================================
// dsa_top.sv
// Top integrado con FSMs separados
//============================================================

module dsa_top #(
    parameter ADDR_WIDTH = 18,
    parameter IMG_WIDTH  = 512,
    parameter IMG_HEIGHT = 512,
    parameter SIMD_WIDTH = 4,
    parameter MEM_SIZE   = 262144
)(
    input  logic                   clk,
    input  logic                   rst,
    input  logic                   start,
    input  logic                   mode_simd,
    input  logic [15:0]            img_width_in,
    input  logic [15:0]            img_height_in,
    input  logic [7:0]             scale_factor,
    input  logic                   ext_mem_write_en,
    input  logic                   ext_mem_read_en,
    input  logic [ADDR_WIDTH-1:0]  ext_mem_addr,
    input  logic [7:0]             ext_mem_data_in,
    output logic [7:0]             ext_mem_data_out,
    output logic                   busy,
    output logic                   ready,
    output logic [15:0]            progress,
    output logic [31:0]            flops_count,
    output logic [31:0]            mem_reads_count,
    output logic [31:0]            mem_writes_count
);

    logic [15:0] img_width_out;
    logic [15:0] img_height_out;
    
    assign img_width_out = (img_width_in * scale_factor) >> 8;
    assign img_height_out = (img_height_in * scale_factor) >> 8;
    
    logic        seq_enable;
    logic        seq_fetch_req;
    logic        seq_fetch_done;
    logic        seq_dp_start;
    logic        seq_dp_done;
    logic        seq_write_enable;
    logic [15:0] seq_current_x;
    logic [15:0] seq_current_y;
    logic        seq_busy;
    logic        seq_ready;
    
    logic        simd_enable;
    logic        simd_fetch_req;
    logic        simd_fetch_done;
    logic        simd_dp_start;
    logic        simd_dp_done;
    logic        simd_write_enable;
    logic [3:0]  simd_write_index;
    logic [15:0] simd_current_x;
    logic [15:0] simd_current_y;
    logic        simd_busy;
    logic        simd_ready;
    
    logic        active_fetch_req;
    logic        active_dp_start;
    logic        active_write_enable;
    logic [15:0] active_x;
    logic [15:0] active_y;
    logic [3:0]  active_write_index;
    
    assign active_fetch_req = mode_simd ? simd_fetch_req : seq_fetch_req;
    assign active_dp_start = mode_simd ? simd_dp_start : seq_dp_start;
    assign active_write_enable = mode_simd ? simd_write_enable : seq_write_enable;
    assign active_x = mode_simd ? simd_current_x : seq_current_x;
    assign active_y = mode_simd ? simd_current_y : seq_current_y;
    assign active_write_index = mode_simd ? simd_write_index : 4'd0;
    
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            seq_enable <= 1'b0;
            simd_enable <= 1'b0;
        end else if (start) begin
            if (mode_simd) begin
                seq_enable <= 1'b0;
                simd_enable <= 1'b1;
            end else begin
                seq_enable <= 1'b1;
                simd_enable <= 1'b0;
            end
        end else if (seq_ready || simd_ready) begin
            seq_enable <= 1'b0;
            simd_enable <= 1'b0;
        end
    end
    
    logic        fetch_mem_read_en;
    logic [ADDR_WIDTH-1:0] fetch_mem_addr;
    
    logic        seq_fetch_valid;
    logic [7:0]  seq_p00;
    logic [7:0]  seq_p01;
    logic [7:0]  seq_p10;
    logic [7:0]  seq_p11;
    logic [15:0] seq_a;
    logic [15:0] seq_b;
    logic        seq_fetch_busy;
    logic [15:0] seq_src_x_int;
    logic [15:0] seq_src_y_int;
    logic [15:0] seq_frac_x;
    logic [15:0] seq_frac_y;
    
    logic        simd_fetch_valid;
    logic [7:0]  simd_p00_0;
    logic [7:0]  simd_p00_1;
    logic [7:0]  simd_p00_2;
    logic [7:0]  simd_p00_3;
    logic [7:0]  simd_p01_0;
    logic [7:0]  simd_p01_1;
    logic [7:0]  simd_p01_2;
    logic [7:0]  simd_p01_3;
    logic [7:0]  simd_p10_0;
    logic [7:0]  simd_p10_1;
    logic [7:0]  simd_p10_2;
    logic [7:0]  simd_p10_3;
    logic [7:0]  simd_p11_0;
    logic [7:0]  simd_p11_1;
    logic [7:0]  simd_p11_2;
    logic [7:0]  simd_p11_3;
    logic [15:0] simd_a_0;
    logic [15:0] simd_a_1;
    logic [15:0] simd_a_2;
    logic [15:0] simd_a_3;
    logic [15:0] simd_b_0;
    logic [15:0] simd_b_1;
    logic [15:0] simd_b_2;
    logic [15:0] simd_b_3;
    logic        simd_fetch_busy;
    
    assign seq_fetch_done = seq_fetch_valid;
    assign simd_fetch_done = simd_fetch_valid;
    
    logic [25:0] inv_scale;
    logic [25:0] src_x_fixed;
    logic [25:0] src_y_fixed;
    
    assign inv_scale = (scale_factor != 8'd0) ? (26'd65536 / scale_factor) : 26'd65536;
    assign src_x_fixed = active_x * inv_scale;
    assign src_y_fixed = active_y * inv_scale;
    assign seq_src_x_int = src_x_fixed[25:16];
    assign seq_src_y_int = src_y_fixed[25:16];
    assign seq_frac_x = src_x_fixed[15:0];
    assign seq_frac_y = src_y_fixed[15:0];
    
    logic [7:0]  dp_seq_pixel_out;
    logic        dp_seq_done;
    
    logic [7:0]  dp_simd_p00 [0:SIMD_WIDTH-1];
    logic [7:0]  dp_simd_p01 [0:SIMD_WIDTH-1];
    logic [7:0]  dp_simd_p10 [0:SIMD_WIDTH-1];
    logic [7:0]  dp_simd_p11 [0:SIMD_WIDTH-1];
    logic [15:0] dp_simd_a   [0:SIMD_WIDTH-1];
    logic [15:0] dp_simd_b   [0:SIMD_WIDTH-1];
    logic [7:0]  dp_simd_pixel_out [0:SIMD_WIDTH-1];
    logic        dp_simd_done;
    
    assign dp_simd_p00[0] = simd_p00_0;
    assign dp_simd_p00[1] = simd_p00_1;
    assign dp_simd_p00[2] = simd_p00_2;
    assign dp_simd_p00[3] = simd_p00_3;
    assign dp_simd_p01[0] = simd_p01_0;
    assign dp_simd_p01[1] = simd_p01_1;
    assign dp_simd_p01[2] = simd_p01_2;
    assign dp_simd_p01[3] = simd_p01_3;
    assign dp_simd_p10[0] = simd_p10_0;
    assign dp_simd_p10[1] = simd_p10_1;
    assign dp_simd_p10[2] = simd_p10_2;
    assign dp_simd_p10[3] = simd_p10_3;
    assign dp_simd_p11[0] = simd_p11_0;
    assign dp_simd_p11[1] = simd_p11_1;
    assign dp_simd_p11[2] = simd_p11_2;
    assign dp_simd_p11[3] = simd_p11_3;
    assign dp_simd_a[0] = simd_a_0;
    assign dp_simd_a[1] = simd_a_1;
    assign dp_simd_a[2] = simd_a_2;
    assign dp_simd_a[3] = simd_a_3;
    assign dp_simd_b[0] = simd_b_0;
    assign dp_simd_b[1] = simd_b_1;
    assign dp_simd_b[2] = simd_b_2;
    assign dp_simd_b[3] = simd_b_3;
    
    assign seq_dp_done = dp_seq_done;
    assign simd_dp_done = dp_simd_done;
    
    logic                   int_mem_write_en;
    logic [ADDR_WIDTH-1:0]  int_mem_addr;
    logic [7:0]             int_mem_data_in;
    logic [7:0]             mem_data_out;
    
    logic [ADDR_WIDTH-1:0] write_base_addr;
    
    assign write_base_addr = (MEM_SIZE/2) + (active_y * img_width_out + active_x);
    assign int_mem_write_en = active_write_enable;
    assign int_mem_addr = active_write_enable ? 
                          (mode_simd ? (write_base_addr + active_write_index) : write_base_addr) :
                          {ADDR_WIDTH{1'b0}};
    assign int_mem_data_in = active_write_enable ?
                             (mode_simd ? dp_simd_pixel_out[active_write_index] : dp_seq_pixel_out) :
                             8'd0;
    
	 //========================================================
	 // Performance counters - SIN LATCHES
	 //========================================================
	 always_ff @(posedge clk or posedge rst) begin
		  if (rst) begin
			   flops_count <= 32'd0;
			   mem_reads_count <= 32'd0;
			   mem_writes_count <= 32'd0;
		  end else begin
			   // FLOPS: Siempre asignar un valor
			   if (active_dp_start) begin
					 if (mode_simd)
						  flops_count <= flops_count + (SIMD_WIDTH * 32'd8);
					 else
						  flops_count <= flops_count + 32'd8;
			   end else begin
					 flops_count <= flops_count;  // Mantener valor actual
			   end
			  
			   // LECTURAS: Siempre asignar un valor
			   if (fetch_mem_read_en || ext_mem_read_en)
					 mem_reads_count <= mem_reads_count + 32'd1;
			   else
					 mem_reads_count <= mem_reads_count;  // Mantener valor actual
			  
			   // ESCRITURAS: Siempre asignar un valor
			   if (int_mem_write_en || ext_mem_write_en)
				 	 mem_writes_count <= mem_writes_count + 32'd1;
			   else
					 mem_writes_count <= mem_writes_count;  // Mantener valor actual
		  end
	 end
    
    assign busy = mode_simd ? simd_busy : seq_busy;
    assign ready = mode_simd ? simd_ready : seq_ready;
    assign progress = active_y * img_width_out + active_x;
    
    logic                   final_mem_read_en;
    logic                   final_mem_write_en;
    logic [ADDR_WIDTH-1:0]  final_mem_addr;
    logic [7:0]             final_mem_data_in;
    
    assign final_mem_read_en = (ext_mem_write_en || ext_mem_read_en) ? ext_mem_read_en :
                               (fetch_mem_read_en ? 1'b1 : 1'b0);
    assign final_mem_write_en = (ext_mem_write_en || ext_mem_read_en) ? 
                            ext_mem_write_en :
                            int_mem_write_en;
    assign final_mem_addr = (ext_mem_write_en || ext_mem_read_en) ? ext_mem_addr :
                            (fetch_mem_read_en ? fetch_mem_addr : int_mem_addr);
    assign final_mem_data_in = (ext_mem_write_en || ext_mem_read_en) ? ext_mem_data_in :
                               int_mem_data_in;
    
    dsa_control_fsm_sequential #(
        .IMG_WIDTH_MAX(IMG_WIDTH),
        .IMG_HEIGHT_MAX(IMG_HEIGHT)
    ) fsm_seq (
        .clk(clk),
        .rst(rst),
        .enable(seq_enable),
        .img_width_out(img_width_out),
        .img_height_out(img_height_out),
        .fetch_req(seq_fetch_req),
        .fetch_done(seq_fetch_done),
        .dp_start(seq_dp_start),
        .dp_done(seq_dp_done),
        .write_enable(seq_write_enable),
        .current_x(seq_current_x),
        .current_y(seq_current_y),
        .busy(seq_busy),
        .ready(seq_ready)
    );
    
    dsa_control_fsm_simd #(
        .IMG_WIDTH_MAX(IMG_WIDTH),
        .IMG_HEIGHT_MAX(IMG_HEIGHT),
        .SIMD_WIDTH(SIMD_WIDTH)
    ) fsm_simd (
        .clk(clk),
        .rst(rst),
        .enable(simd_enable),
        .img_width_out(img_width_out),
        .img_height_out(img_height_out),
        .fetch_req(simd_fetch_req),
        .fetch_done(simd_fetch_done),
        .dp_start(simd_dp_start),
        .dp_done(simd_dp_done),
        .write_enable(simd_write_enable),
        .write_index(simd_write_index),
        .current_x(simd_current_x),
        .current_y(simd_current_y),
        .busy(simd_busy),
        .ready(simd_ready)
    );
    
    dsa_pixel_fetch_unified #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .IMG_WIDTH(IMG_WIDTH),
        .SIMD_WIDTH(SIMD_WIDTH)
    ) fetch_unit (
        .clk(clk),
        .rst(rst),
        .mode_simd(mode_simd),
        .req_valid(active_fetch_req),
        .seq_src_x_int(seq_src_x_int),
        .seq_src_y_int(seq_src_y_int),
        .seq_frac_x(seq_frac_x),
        .seq_frac_y(seq_frac_y),
        .simd_base_x(active_x),
        .simd_base_y(active_y),
        .scale_factor(scale_factor),
        .img_base_addr({ADDR_WIDTH{1'b0}}),
        .mem_read_en(fetch_mem_read_en),
        .mem_addr(fetch_mem_addr),
        .mem_data(mem_data_out),
        .seq_fetch_valid(seq_fetch_valid),
        .seq_p00(seq_p00),
        .seq_p01(seq_p01),
        .seq_p10(seq_p10),
        .seq_p11(seq_p11),
        .seq_a(seq_a),
        .seq_b(seq_b),
        .seq_busy(seq_fetch_busy),
        .simd_fetch_valid(simd_fetch_valid),
        .simd_p00_0(simd_p00_0),
        .simd_p00_1(simd_p00_1),
        .simd_p00_2(simd_p00_2),
        .simd_p00_3(simd_p00_3),
        .simd_p01_0(simd_p01_0),
        .simd_p01_1(simd_p01_1),
        .simd_p01_2(simd_p01_2),
        .simd_p01_3(simd_p01_3),
        .simd_p10_0(simd_p10_0),
        .simd_p10_1(simd_p10_1),
        .simd_p10_2(simd_p10_2),
        .simd_p10_3(simd_p10_3),
        .simd_p11_0(simd_p11_0),
        .simd_p11_1(simd_p11_1),
        .simd_p11_2(simd_p11_2),
        .simd_p11_3(simd_p11_3),
        .simd_a_0(simd_a_0),
        .simd_a_1(simd_a_1),
        .simd_a_2(simd_a_2),
        .simd_a_3(simd_a_3),
        .simd_b_0(simd_b_0),
        .simd_b_1(simd_b_1),
        .simd_b_2(simd_b_2),
        .simd_b_3(simd_b_3),
        .simd_busy(simd_fetch_busy)
    );
    
    dsa_mem_interface #(
        .MEM_SIZE(MEM_SIZE)
    ) mem_inst (
        .clk(clk),
        .read_en(final_mem_read_en),
        .write_en(final_mem_write_en),
        .addr(final_mem_addr),
        .data_in(final_mem_data_in),
        .data_out(mem_data_out)
    );
    
    assign ext_mem_data_out = mem_data_out;
    
    dsa_datapath dp_seq (
        .clk(clk),
        .rst(rst),
        .start(active_dp_start && !mode_simd),
        .p00(seq_p00),
        .p01(seq_p01),
        .p10(seq_p10),
        .p11(seq_p11),
        .a(seq_a),
        .b(seq_b),
        .pixel_out(dp_seq_pixel_out),
        .done(dp_seq_done)
    );
    
    dsa_datapath_simd #(
        .N(SIMD_WIDTH)
    ) dp_simd (
        .clk(clk),
        .rst(rst),
        .start(active_dp_start && mode_simd),
        .p00(dp_simd_p00),
        .p01(dp_simd_p01),
        .p10(dp_simd_p10),
        .p11(dp_simd_p11),
        .a(dp_simd_a),
        .b(dp_simd_b),
        .pixel_out(dp_simd_pixel_out),
        .done(dp_simd_done)
    );

endmodule