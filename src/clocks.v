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
              input wire  pixel_clk_nreset,
              output wire pixel_clk_locked,
              input wire  pixel_clk_cfg_sdi,
              output wire pixel_clk_cfg_sdo,
              input wire  pixel_clk_cfg_sclk,
              input wire  pixel_clk_bypass,
              output wire sys_clk
              );


`ifndef SIM

   /* Clock input of 62.5MHz is ideal as system clock, no need for a PLL: */
   assign sys_clk = sys_clk_in;

   /* VIDC clock does want to be multiplied: */
   SB_PLL40_CORE #(
                   .TEST_MODE(1),
 `include "pll.vh"
	           ) vpll (
		           .REFERENCECLK(vidc_clk_in),
		           .PLLOUTGLOBAL(pixel_clk),
		           .LOCK(pixel_clk_locked),
		           .RESETB(pixel_clk_nreset),
		           .BYPASS(pixel_clk_bypass),
                           .SDO(pixel_clk_cfg_sdo),
                           .SDI(pixel_clk_cfg_sdi),
                           .SCLK(pixel_clk_cfg_sclk)
	                   );

`else // !`ifndef SIM

   /* Testbench can make the input clocks something interesting,
    * so they don't need special treatment here.
    */
   assign       sys_clk = sys_clk_in;
   assign       pixel_clk = vidc_clk_in;
`endif // !`ifndef SIM

endmodule // clocks
