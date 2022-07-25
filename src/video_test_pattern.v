/* Generate a simple video test image
 *
 * Outputs are delayed by 4 cycles (relative to flops of input signals)
 *
 * Copyright 2021-2022 Matt Evans
 *
 * Permission is hereby granted, free of charge, to any person
 * obtaining a copy of this software and associated documentation files
 * (the "Software"), to deal in the Software without restriction,
 * including without limitation the rights to use, copy, modify, merge,
 * publish, distribute, sublicense, and/or sell copies of the Software,
 * and to permit persons to whom the Software is furnished to do so,
 * subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be
 * included in all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
 * EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
 * MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
 * NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS
 * BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN
 * ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
 * CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */

module video_test_pattern(input wire pclk,
                          input wire [10:0] px,
                          input wire [10:0] py,
                          input wire [10:0] xstart,
                          input wire [10:0] xend,
                          input wire [10:0] ystart,
                          input wire [10:0] yend,

                          output reg [7:0]  r,
                          output reg [7:0]  g,
                          output reg [7:0]  b
                          );

   reg [7:0] 	tc_r1;
   reg [7:0]    tc_g1;
   reg [7:0]    tc_b1;
   reg [7:0]    tc_r2;
   reg [7:0]    tc_g2;
   reg [7:0]    tc_b2;
   reg [7:0]    tc_r3;
   reg [7:0]    tc_g3;
   reg [7:0]    tc_b3;

   wire      	stripex = (px == xstart) ||
                (px == xend) || (px[7:0] == 8'h00);
   wire      	stripey = (py == ystart) ||
                (py == yend) || (py[7:0] == 8'h00);
   wire [7:0]   stripe = (stripex || stripey) ? 8'hff : 8'h0;

   always @(posedge pclk) begin
      tc_r1 	<= px[7:0] | stripe;
      tc_g1 	<= py[7:0] | stripe;
      tc_b1 	<= (px[8:1] ^ py[8:1]) | stripe;

      tc_r2 	<= tc_r1;
      tc_g2 	<= tc_g1;
      tc_b2 	<= tc_b1;

      tc_r3 	<= tc_r2;
      tc_g3 	<= tc_g2;
      tc_b3 	<= tc_b2;

      r 	<= tc_r3;
      g 	<= tc_g3;
      b 	<= tc_b3;
   end
endmodule // video_test_pattern
