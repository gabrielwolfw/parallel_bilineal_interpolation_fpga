module bin2bcd_decoder(clk, reset_n, decode, bin_in, bcd_out);

parameter MAX_VALUE = 9999;

parameter N = 16;
parameter M = 16;

input  clk, reset_n, decode;
input  [N-1:0] bin_in;
output logic [M-1:0] bcd_out;

logic  [N-1:0] tmp;
logic  [M-1:0] offset;
logic  [M-1:0] count_10000;
logic  [M-1:0] count_1000;
logic  [M-1:0] count_100;
logic  [2:0] state;
logic  [2:0] nxt_state;



localparam [2:0] INIT           = 3'b000;
localparam [2:0] WAIT           = 3'b001;
localparam [2:0] SUBSTRACT_1000 = 3'b010;
localparam [2:0] SUBSTRACT_100  = 3'b011;
localparam [2:0] SUBSTRACT_10   = 3'b100;
localparam [2:0] DONE           = 3'b101;


always_ff @(posedge clk or negedge reset_n) begin
	if(~reset_n) begin
		state <= INIT;
	end
	else begin
		state <= nxt_state;
	end
end


always_ff @(posedge clk or negedge reset_n) begin
	if(~reset_n) begin
		tmp         <= '0;
		offset      <= '0;
		bcd_out     <= '0;
		count_10000 <= 16'd10000;
		count_1000  <= 10'd1000;
		count_100   <= 7'd100;
	end
	else begin
	
	   case(state)
			INIT: begin
				tmp      <= '0;
				offset   <= '0;
				bcd_out  <= '0;
			end
			
			WAIT: begin
				if(decode) begin
					tmp         <= bin_in;
					offset      <= bin_in;					
					count_10000 <= 16'd10000;
					count_1000  <= 10'd1000;
					count_100   <= 7'd100;
				end
			end
			
			SUBSTRACT_1000: begin
				if(tmp>=count_10000) begin
					tmp           <= tmp - 10'd1000;
					offset        <= offset + 16'd3096;
				end
					count_10000   <= count_10000 - 10'd1000;
			end
			
			SUBSTRACT_100: begin
				if(tmp>=count_1000) begin
					tmp           <= tmp - 10'd100;
					offset        <= offset + 16'd156;
				end
				count_1000    <= count_1000 - 10'd100;	
			end
			
			SUBSTRACT_10: begin
				if(tmp>=count_100) begin
					tmp           <= tmp - 10'd10;
					offset        <= offset + 16'd6;
				end
				count_100    <= count_100 - 10'd10;	
			end
			
			DONE: begin
				bcd_out  <= offset;
			end
		
		endcase
	end
end

always_comb begin
	case(state)
		
		INIT: begin
			nxt_state <= WAIT;
		end
		
		WAIT: begin
			if(decode) nxt_state <= SUBSTRACT_1000;
			else nxt_state <= WAIT;
		end
		
		SUBSTRACT_1000: begin
			
			if(count_10000 > count_1000)
				nxt_state <= SUBSTRACT_1000;
			else	
				nxt_state <= SUBSTRACT_100;
		end
		
		SUBSTRACT_100: begin
			
			if(count_1000 > count_100)
				nxt_state <= SUBSTRACT_100;
			else	
				nxt_state <= SUBSTRACT_10;
		end
		
		SUBSTRACT_10: begin
			
			if(count_100 > 4'd10)
				nxt_state <= SUBSTRACT_10;
			else	
				nxt_state <= DONE;
		end		
		
		DONE: begin
			nxt_state <= WAIT;
		end
		
		default : begin
			nxt_state <= INIT;
		end
		
	endcase
end

endmodule : bin2bcd_decoder
