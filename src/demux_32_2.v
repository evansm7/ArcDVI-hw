/* Select a 2-bit field from a 32-bit vector, indexed with 0 as least-significant field.
 *
 * Copyright 2022 Matt Evans
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

module demux_32_2(input wire [31:0] in,
                  input wire [3:0]  sel,
                  output reg [1:0]  out		/* Wire */
                  );

   always @(*) begin
      out = 2'b00;

      case (sel)
        4'h0:		out = in[1:0];
        4'h1:		out = in[3:2];
        4'h2:		out = in[5:4];
        4'h3:		out = in[7:6];
        4'h4:		out = in[9:8];
        4'h5:		out = in[11:10];
        4'h6:		out = in[13:12];
        4'h7:		out = in[15:14];
        4'h8:		out = in[17:16];
        4'h9:		out = in[19:18];
        4'ha:		out = in[21:20];
        4'hb:		out = in[23:22];
        4'hc:		out = in[25:24];
        4'hd:		out = in[27:26];
        4'he:		out = in[29:28];
        default:	out = in[31:30];
      endcase
   end
endmodule // demux_32_2
