module bcd2seven_seg(bcd_in, seven_seg_out);
typedef enum logic[6:0]
{
   ZERO_SEVEN_SEG    = 7'b1_0_0_0_0_0_0,
   ONE_SEVEN_SEG     = 7'b1_1_1_1_0_0_1,
   TWO_SEVEN_SEG     = 7'b0_1_0_0_1_0_0,
   THREE_SEVEN_SEG   = 7'b0_1_1_0_0_0_0,
   FOUR_SEVEN_SEG    = 7'b0_0_1_1_0_0_1,
   FIVE_SEVEN_SEG    = 7'b0_0_1_0_0_1_0,
   SIX_SEVEN_SEG     = 7'b0_0_0_0_0_1_0,
   SEVEN_SEVEN_SEG   = 7'b1_1_1_1_0_0_0,
   EIGHT_SEVEN_SEG   = 7'b0_0_0_0_0_0_0,
   NINE_SEVEN_SEG    = 7'b0_0_1_0_0_0_0,
   ERROR_SEVEN_SEG   = 7'b0_0_0_0_1_1_0

} seven_seg_value_t;

input [3:0] bcd_in;
output [6:0] seven_seg_out;
logic  [6:0] seven_seg;

always_comb begin

    case(bcd_in)
        
        4'h0: begin
            seven_seg = ZERO_SEVEN_SEG;
        end

        4'h1: begin
            seven_seg = ONE_SEVEN_SEG;
        end

        4'h2: begin
            seven_seg = TWO_SEVEN_SEG;
        end

        4'h3: begin
            seven_seg = THREE_SEVEN_SEG;
        end

        4'h4: begin
            seven_seg = FOUR_SEVEN_SEG;
        end

        4'h5: begin
            seven_seg = FIVE_SEVEN_SEG;
        end

        4'h6: begin
            seven_seg = SIX_SEVEN_SEG;
        end

        4'h7: begin
            seven_seg = SEVEN_SEVEN_SEG;
        end

        4'h8: begin
            seven_seg = EIGHT_SEVEN_SEG;
        end

        4'h9: begin
            seven_seg = NINE_SEVEN_SEG;
        end

        default : begin
            seven_seg = ERROR_SEVEN_SEG;
        end

    endcase
end

assign seven_seg_out = seven_seg;
endmodule
