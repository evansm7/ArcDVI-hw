/* Generate a simple video test image
 *
 * Outputs are delayed by 3 cycles (relative to flops of input signals)
 */

module video_test_pattern(input wire pclk,
                          input wire [10:0] px,
                          input wire [10:0] py,
                          input wire [10:0] xstart,
                          input wire [10:0] xend,
                          input wire [10:0] ystart,
                          input wire [10:0] yend,

                          output reg [7:0]  r3,
                          output reg [7:0]  g3,
                          output reg [7:0]  b3
                          );

   reg [7:0] 	tc_r1;
   reg [7:0]    tc_g1;
   reg [7:0]    tc_b1;
   reg [7:0]    tc_r2;
   reg [7:0]    tc_g2;
   reg [7:0]    tc_b2;

   wire      	stripex = (px == (ti_h_disp_start+1)) ||
                (px == (ti_h_disp_end)) || (px[7:0] == 8'h00);
   wire      	stripey = (py == (ti_v_disp_start+1)) ||
                (py == ti_v_disp_end) || (py[7:0] == 8'h00);
   wire [7:0]   stripe = (stripex || stripey) ? 8'hff : 8'h0;

   always @(posedge pclk) begin
      tc_r1 	<= px[7:0] | stripe;
      tc_g1 	<= py[7:0] | stripe;
      tc_b1 	<= (px[8:1] ^ py[8:1]) | stripe;

      tc_r2 	<= tc_r;
      tc_g2 	<= tc_g;
      tc_b2 	<= tc_b;

      r3 	<= tc_r2;
      g3 	<= tc_g2;
      b3 	<= tc_b2;
   end
endmodule // video_test_pattern
