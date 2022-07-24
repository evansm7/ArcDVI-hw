/* ArcDVI top-level
 *
 * This project interfaces to the Acorn Archimedes VIDC, passively tracking
 * when the Arc writes VIDC registers and when the VIDC receives DMA.
 *
 * The DMA is repackaged and streamed out in a possibly-upscaled/retimed fashion.
 *
 * This toplevel is for the ArcDVI PCB (currently with an MCU plus ICE40HX, and
 * external video transmitter/serialiser).
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


module soc_top_arcdvi(input wire         clk_in,
                      output wire        led,

                      output wire        v_vsync,
                      output wire        v_hsync,
                      output wire        v_de,
                      output wire [23:0] v_rgb,

                      input wire         spi_clk,
                      input wire         spi_ncs,
                      input wire         spi_din,
                      output wire        spi_dout,

                      input wire [31:0]  vidc_d,
                      input wire         vidc_nvidw,
                      input wire         vidc_nvcs,
                      input wire         vidc_nhs,
                      input wire         vidc_nsndrq,
                      input wire         vidc_nvidrq,
                      input wire         vidc_flybk,
                      input wire         vidc_ckin,
                      input wire         vidc_nsndak,
                      input wire         vidc_nvidak
                      );

   parameter CLK_RATE = 62500000;

   ////////////////////////////////////////////////////////////////////////////////
   /* Clocks and reset */

   wire                          clk, clk_pixel;

   /* Two PLLs: One generates system/CPU clock from crystal input.
    * The other generates the video output/pixel clock from the VIDC
    * clock.
    */

`ifdef HIRES_MODE
   localparam pixel_freq = 24000000*3.25;
`else
   localparam pixel_freq = 24000000;
`endif

   /* clk_in is 62.5MHz (MCU clock/2); it's used directly. */
   clocks #(.VIDC_CLK_IN_RATE(24000000),
            .PIXEL_CLK_RATE(pixel_freq)
            ) CLKS (
                    .sys_clk_in(clk_in),
                    .vidc_clk_in(vidc_ckin),

                    .pixel_clk(clk_pixel),
                    .sys_clk(clk)
               );


   wire 		   reset;
   reg [1:0]               resetc; // assume start at 0?
   initial begin
`ifdef SIM
           resetc 	<= 0;
`endif
   end
   always @(posedge clk) begin
           if (resetc != 2'b11)
             resetc <= resetc + 1;
   end
   assign 	reset = resetc[1:0] != 2'b11;


   ////////////////////////////////////////////////////////////////////////////////
   /* CPU subsystem:
    * This can be replaced by an SPI module receiving requests from the outside
    * world (e.g. run the firmware on an external MCU).
    */

   wire                    iomem_valid;
   wire [3:0]              iomem_wstrb;
   wire [13:0]             iomem_addr;
   wire [31:0]             iomem_wdata;
   wire [31:0]             iomem_rdata;
   wire                    iomem_wr;
   wire [11:0]             spireg_addr;

   assign iomem_addr[13:0]                  = {spireg_addr[11:0], 2'b00};

   spir SPIREGS (.clk(clk),
                 .reset(reset),

                 .spi_clk(spi_clk),
                 .spi_ncs(spi_ncs),
                 .spi_di(spi_din),
                 .spi_do(spi_dout),

                 .r_valid(iomem_valid),
	         .r_wen(iomem_wr),
	         .r_addr(spireg_addr),
	         .r_wdata(iomem_wdata),
	         .r_rdata(iomem_rdata)
	         );

   wire                    vidc_reg_select  = iomem_valid && (iomem_addr[13:12] == 2'b00);
   wire                    video_reg_select = iomem_valid && (iomem_addr[13:12] == 2'b10);
   /* Future use: */
   wire                    cgmem_select     = iomem_valid && (iomem_addr[13:12] == 2'b01);


   ////////////////////////////////////////////////////////////////////////////////
   // VIDC capture

   wire       		conf_hires;	// Configured later, used here

   wire [(12*16)-1:0] 	vidc_palette;
   wire [(12*3)-1:0] 	vidc_cursor_palette;
   wire [10:0]        	vidc_cursor_hstart;
   wire [9:0]         	vidc_cursor_vstart;
   wire [9:0]         	vidc_cursor_vend;
   wire [3:0] 		fr_cnt;
   wire [15:0] 		v_dma_ctr;
   wire [15:0] 		c_dma_ctr;
   wire                 vidc_special_written;
   wire [23:0]          vidc_special;
   wire [23:0]          vidc_special_data;
   wire                 load_dma;
   wire                 load_dma_cursor;
   wire [31:0]          load_dma_data;

   wire [5:0]           vidc_reg_idx = iomem_addr[7:2];  // register this pls
   wire [23:0]          vidc_reg_rdata;
   reg [31:0]           vidc_rd; // wire

   wire                 vidc_tregs_status;
   wire                 vidc_tregs_ack;

   vidc_capture	VIDCC(.clk(clk),
                      .reset(reset),

                      // VIDC pins input
                      .vidc_d(vidc_d),
                      .vidc_nvidw(vidc_nvidw),
                      .vidc_nvcs(vidc_nvcs),
                      .vidc_nhs(vidc_nhs),
                      .vidc_nsndrq(vidc_nsndrq),
                      .vidc_nvidrq(vidc_nvidrq),
                      .vidc_flybk(vidc_flybk),
                      .vidc_nsndak(vidc_nsndak),
                      .vidc_nvidak(vidc_nvidak),

                      .conf_hires(conf_hires),

                      .vidc_palette(vidc_palette),
                      .vidc_cursor_palette(vidc_cursor_palette),
                      .vidc_cursor_hstart(vidc_cursor_hstart),
                      .vidc_cursor_vstart(vidc_cursor_vstart),
                      .vidc_cursor_vend(vidc_cursor_vend),

                      .vidc_reg_sel(vidc_reg_idx),
                      .vidc_reg_rdata(vidc_reg_rdata),

                      .tregs_status(vidc_tregs_status),
                      .tregs_status_ack(vidc_tregs_ack),

                      .fr_count(fr_cnt),
                      .video_dma_counter(v_dma_ctr),
                      .cursor_dma_counter(c_dma_ctr),

                      .vidc_special_written(vidc_special_written),
                      .vidc_special(vidc_special),
                      .vidc_special_data(vidc_special_data),

                      .load_dma(load_dma),
                      .load_dma_cursor(load_dma_cursor),
                      .load_dma_data(load_dma_data)
                      );

   // Register read:
   always @(*) begin
           case (iomem_addr[8:2])
             7'b1_0000_00:	vidc_rd = {16'h0, v_dma_ctr};
             7'b1_0000_01:	vidc_rd = {16'h0, c_dma_ctr};
             default:		vidc_rd = {8'h0, vidc_reg_rdata};
           endcase // case (iomem_addr[8:2])
   end

   // LED blinky from frame counter:
   assign led = fr_cnt[3];


   /////////////////////////////////////////////////////////////////////////////
   // Video output control regs, timing/pixel generator:

   wire [31:0] 		   video_reg_rd;

   video VIDEO(.clk(clk),
               .reset(reset),

               .reg_wdata(iomem_wdata),
               .reg_rdata(video_reg_rd),
               .reg_addr(iomem_addr[5:0]),
               .reg_wstrobe(video_reg_select && iomem_wr),

               .load_dma(load_dma),
               .load_dma_cursor(load_dma_cursor),
               .load_dma_data(load_dma_data),

               .v_cursor_x(vidc_cursor_hstart),
               .v_cursor_y(vidc_cursor_vstart),
               .v_cursor_yend(vidc_cursor_vend),

               .vidc_palette(vidc_palette),
               .vidc_cursor_palette(vidc_cursor_palette),

               .vidc_special_written(vidc_special_written),
               .vidc_special(vidc_special),
               .vidc_special_data(vidc_special_data),

               .vidc_tregs_status(vidc_tregs_status),
               .vidc_tregs_ack(vidc_tregs_ack),

               .clk_pixel(clk_pixel),

               .video_r(v_rgb[23:16]),
               .video_g(v_rgb[15:8]),
               .video_b(v_rgb[7:0]),
               .video_hsync(v_hsync),
               .video_vsync(v_vsync),
               .video_de(v_de),

               .enable_test_card(sw[0]),

               .sync_flybk(vidc_flybk),

               .is_hires(conf_hires)
               );


   ////////////////////////////////////////////////////////////////////////////////
   // Finally, combine peripheral read data back to the MCU:

   assign iomem_rdata = vidc_reg_select ? vidc_rd :
                        cgmem_select ? 32'hffffffff :
                        video_reg_select ? video_reg_rd :
                        32'h0;

endmodule // soc_top
