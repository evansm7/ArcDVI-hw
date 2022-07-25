/* Pick pixels from a 32-bit DMA word, given a colour depth and
 * X coordinate
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

module video_pixel_demux(input wire [31:0] pixword,
                         input wire [4:0]  x_index,

                         output reg        pixel1b,
                         output reg [3:0]  pixel1b_hires,
                         output reg [1:0]  pixel2b,
                         output reg [3:0]  pixel4b,
                         output reg [7:0]  pixel8b,
                         output reg [15:0] pixel16b
                         );


   /* These case statements gave a significant perf improvement over
    * ternary ops; yosys seems to do a much better job with these.
    */
   always @(*) begin
      pixel1b 	= 0;
      case (x_index[4:0])
        0: pixel1b       	= pixword[0];
        1: pixel1b       	= pixword[1];
        2: pixel1b       	= pixword[2];
        3: pixel1b       	= pixword[3];
        4: pixel1b       	= pixword[4];
        5: pixel1b       	= pixword[5];
        6: pixel1b       	= pixword[6];
        7: pixel1b       	= pixword[7];
        8: pixel1b       	= pixword[8];
        9: pixel1b       	= pixword[9];
        10: pixel1b      	= pixword[10];
        11: pixel1b      	= pixword[11];
        12: pixel1b      	= pixword[12];
        13: pixel1b      	= pixword[13];
        14: pixel1b      	= pixword[14];
        15: pixel1b      	= pixword[15];
        16: pixel1b      	= pixword[16];
        17: pixel1b      	= pixword[17];
        18: pixel1b      	= pixword[18];
        19: pixel1b      	= pixword[19];
        20: pixel1b      	= pixword[20];
        21: pixel1b      	= pixword[21];
        22: pixel1b      	= pixword[22];
        23: pixel1b      	= pixword[23];
        24: pixel1b      	= pixword[24];
        25: pixel1b      	= pixword[25];
        26: pixel1b      	= pixword[26];
        27: pixel1b      	= pixword[27];
        28: pixel1b      	= pixword[28];
        29: pixel1b      	= pixword[29];
        30: pixel1b      	= pixword[30];
        default: pixel1b 	= pixword[31];
      endcase

      /* The "high resolution mode" version is 4bpp, changing every 4
       * display pixels.
       */
      pixel1b_hires	= 0;
      case (x_index[4:2])
        0: pixel1b_hires	= pixword[3:0];
        1: pixel1b_hires 	= pixword[7:4];
        2: pixel1b_hires 	= pixword[11:8];
        3: pixel1b_hires 	= pixword[15:12];
        4: pixel1b_hires 	= pixword[19:16];
        5: pixel1b_hires 	= pixword[23:20];
        6: pixel1b_hires 	= pixword[27:24];
        default: pixel1b_hires 	= pixword[31:28];
      endcase


      pixel2b 	= 0;
      case (x_index[3:0])
        0: pixel2b 		= pixword[1:0];
        1: pixel2b 		= pixword[3:2];
        2: pixel2b 		= pixword[5:4];
        3: pixel2b 		= pixword[7:6];
        4: pixel2b 		= pixword[9:8];
        5: pixel2b 		= pixword[11:10];
        6: pixel2b 		= pixword[13:12];
        7: pixel2b 		= pixword[15:14];
        8: pixel2b 		= pixword[17:16];
        9: pixel2b 		= pixword[19:18];
        10: pixel2b 		= pixword[21:20];
        11: pixel2b 		= pixword[23:22];
        12: pixel2b 		= pixword[25:24];
        13: pixel2b 		= pixword[27:26];
        14: pixel2b 		= pixword[29:28];
        default: pixel2b 	= pixword[31:30];
      endcase

      pixel4b	= 0;
      case (x_index[2:0])
        0: pixel4b 		= pixword[3:0];
        1: pixel4b 		= pixword[7:4];
        2: pixel4b 		= pixword[11:8];
        3: pixel4b 		= pixword[15:12];
        4: pixel4b 		= pixword[19:16];
        5: pixel4b 		= pixword[23:20];
        6: pixel4b 		= pixword[27:24];
        default: pixel4b 	= pixword[31:28];
      endcase

      pixel8b	= 0;
      case (x_index[1:0])
        0: pixel8b       	= pixword[7:0];
        1: pixel8b       	= pixword[15:8];
        2: pixel8b       	= pixword[23:16];
        default: pixel8b 	= pixword[31:24];
      endcase

      pixel16b 			= x_index[0] ? pixword[31:16] : pixword[15:0];

   end // always @ (*)

endmodule // video_pixel_demux
