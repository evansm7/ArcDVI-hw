/* ArcDVI clock generation
 *
 * Generate clocks for video and system from input crystal/VIDC clocks.
 *
 * Copyright 2021 Matt Evans
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

module clocks(input wire  sys_clk_in,
              input wire  vidc_clk_in,
              output wire pixel_clk,
              output wire sys_clk
              );


`ifndef SIM

   /* Clock input of 62.5MHz is ideal as system clock, no need for a PLL: */
   assign sys_clk = sys_clk_in;
   wire         locked;

   /* VIDC clock does want to be multiplied: */
   generate
      if (PIXEL_CLK_RATE == VIDC_CLK_IN_RATE) begin
         /* 24 in, 24 out -- PLL not really necessary! */
         SB_PLL40_CORE #(.FEEDBACK_PATH("SIMPLE"),
		         .PLLOUT_SELECT("GENCLK"),
		         .DIVR(4'b0000),
		         .DIVF(7'b0011111),
		         .DIVQ(3'b101),
		         .FILTER_RANGE(3'b010)
	                 ) vpll (
		          .REFERENCECLK(vidc_clk_in),
		          .PLLOUTCORE(pixel_clk),
		          .LOCK(locked),
		          .RESETB(1'b1),
		          .BYPASS(1'b0),
	                  );
      end else if (PIXEL_CLK_RATE == VIDC_CLK_IN_RATE * 3.25) begin
         SB_PLL40_CORE #(.FEEDBACK_PATH("SIMPLE"),
		         .PLLOUT_SELECT("GENCLK"),
		         .DIVR(4'b0000),
		         .DIVF(7'b0011001),
		         .DIVQ(3'b011),
		         .FILTER_RANGE(3'b010)
	                 ) vpll (
		          .REFERENCECLK(vidc_clk_in),
		          .PLLOUTCORE(pixel_clk),
		          .LOCK(locked),
		          .RESETB(1'b1),
		          .BYPASS(1'b0)
	                  );
      end else begin
         $error("Need PLL config for this pixel rate");
         /* FIXME: Pass parameters from build */
         /* FIXME: Dynamic reconfiguration! */
      end
   endgenerate

`else // !`ifndef SIM

   /* Testbench can make the input clocks something interesting,
    * so they don't need special treatment here.
    */
   assign       sys_clk = sys_clk_in;
   assign       pixel_clk = vidc_clk_in;
`endif // !`ifndef SIM

endmodule // clocks
