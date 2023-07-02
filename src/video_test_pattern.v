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
                          input wire [63:0] data,
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

   reg [63:0]   data_r;

   wire      	stripex = (px == xstart) ||
                (px == xend) || (px[7:0] == 8'h00);
   wire      	stripey = (py == ystart) ||
                (py == yend) || (py[7:0] == 8'h00);
   wire [7:0]   stripe = (stripex || stripey) ? 8'hff : 8'h0;

   reg [10:0]   xoff;
   /* Data area is 64 bits made from 8 pixels each in X
    * (i.e. 512px wide), black/white dots, with a coloured
    * key below it.
    */
   wire 	disp_data = (xoff < 512) && (py >= 320) &&
                (py < (320+64));
   wire [5:0]   disp_bit = xoff[8:3];
   wire	[1:0]	disp_value = (py < (320+32)) ?
                (data_r[disp_bit] ? 2'b01 : 2'b00) :
                xoff[3] ? 2'b11 : 2'b10;
   wire [7:0]   disp_col   = disp_value == 2'b00 ? {2'h0, px[5:0]} :
                disp_value == 2'b01 ? 8'hff :
                disp_value == 2'b10 ? 8'h40 : 8'h80;

   always @(posedge pclk) begin
      data_r    <= data;
      xoff      <= px - xstart;

      tc_r1 	<= disp_data ? disp_col : (px[7:0] | stripe);
      tc_g1 	<= disp_data ? disp_col : (py[7:0] | stripe);
      tc_b1 	<= disp_data ? disp_col : ((px[8:1] ^ py[8:1]) | stripe);

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
