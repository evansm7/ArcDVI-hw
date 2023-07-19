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

`define ID_REG_VAL	{8'h00, 24'h000001}

module soc_top_arcdvi(input wire         clk_in,
                      output wire        led,

                      output wire	 v_clk,
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

   wire                                  clk, pclk;

   wire                                  pclk_reset;		/* WRT pclk */
   wire                                  pclk_pll_nreset;	/* WRT clk (but should this be PLL input?) */
   wire                                  pclk_pll_bypass;
   wire                                  pclk_pll_locked;
   wire                                  pclk_pll_sdo;
   wire                                  pclk_pll_sdi;
   wire                                  pclk_pll_sclk;

   /* clk_in is 62.5MHz (MCU clock/2); it's used directly.
    * vidc_ckin is multiplied to give an alternative fast PCLK
    * (or the PLL is bypassed and vidc_ckin is used directly)
    */
   clocks #() CLKS (
                    .sys_clk_in(clk_in),
                    .sys_clk(clk),

                    .vidc_clk_in(vidc_ckin),
                    .pixel_clk(pclk),
                    .pixel_clk_nreset(pclk_pll_nreset),
                    .pixel_clk_bypass(pclk_pll_bypass),
                    .pixel_clk_locked(pclk_pll_locked),
                    .pixel_clk_cfg_sdo(pclk_pll_sdo),
                    .pixel_clk_cfg_sdi(pclk_pll_sdi),
                    .pixel_clk_cfg_sclk(pclk_pll_sclk)
               );

`ifndef SIM
   /* Use a DDR output pin to drive v_clk: */
   SB_IO #(.PIN_TYPE(6'b010001))	/* Simple input, DDR output, no enable */
         vclk_out(.OUTPUT_CLK(pclk),
		  .CLOCK_ENABLE(1'b1),
		  .D_OUT_0(1'b0), .D_OUT_1(1'b1),
		  .PACKAGE_PIN(v_clk)
	          );
`endif

   wire 		   reset;
   reg [1:0]               resetc; // assume start at 0?
   initial begin
           resetc 	<= 0;
   end
   always @(posedge clk) begin
           if (resetc != 2'b11)
             resetc <= resetc + 1;
   end
   assign 	reset = resetc[1:0] != 2'b11;


   /* Control registers (w.r.t. clk): */
   reg 					ctrl_pll_nreset;	/* Both initialised by SW */
   reg                                  ctrl_pclk_reset;

   /* Synchronise control regs into respective clock domains: */
   reg [1:0]                            synch_pclk_nreset;
   always @(posedge pclk)	synch_pclk_nreset[1:0] <= {synch_pclk_nreset[0], ctrl_pclk_reset};

   assign pclk_pll_nreset = ctrl_pll_nreset;			/* Async reset */
   assign pclk_reset = synch_pclk_nreset[1];


   ////////////////////////////////////////////////////////////////////////////////
   /* Outside-world interface
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
   wire                    ctrl_reg_select  = iomem_valid && (iomem_addr[13:12] == 2'b11);
   /* Future use: */
   wire                    cgmem_select     = iomem_valid && (iomem_addr[13:12] == 2'b01);
   /* Notes:  Short-term, add at least a register to control the LED and to
    * set up a test card.  (Ideally also to control the pclk PLL multiplication factor too.)
    * Measuring the rate of vidc_ckin would also be useful.
    */

   ////////////////////////////////////////////////////////////////////////////////
   // Control regs

   reg [31:0]              ctrl_rd; // Wire

   reg                     ctrl_pll_sd;
   reg                     ctrl_pll_sclk;
   reg                     ctrl_pll_bypass;

   always @(*) begin
      ctrl_rd = 32'h0;

      case (iomem_addr[3:2])
        2'h0:
          ctrl_rd = `ID_REG_VAL;

        2'h1:	/* Control register */
          ctrl_rd = {25'h0,
                     ctrl_pll_bypass,
                     pclk_pll_locked /* Which domain...? */,
                     pclk_pll_sdo /* Which domain...? */, ctrl_pll_sd, ctrl_pll_sclk,
                     ctrl_pll_nreset, ctrl_pclk_reset};
      endcase
   end

   always @(posedge clk) begin
      if (ctrl_reg_select && iomem_wr) begin
         if (iomem_addr[3:2] == 2'h1) begin
            ctrl_pclk_reset <= iomem_wdata[0];
            ctrl_pll_nreset <= iomem_wdata[1];
            ctrl_pll_sclk   <= iomem_wdata[2];
            ctrl_pll_sd     <= iomem_wdata[3];
            ctrl_pll_bypass <= iomem_wdata[6];
         end
      end
   end

   assign pclk_pll_sdi = ctrl_pll_sd;
   assign pclk_pll_sclk = ctrl_pll_sclk;
   assign pclk_pll_bypass = ctrl_pll_bypass;


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

               .clk_pixel(pclk),
               .reset_pixel(pclk_reset),

               .video_r(v_rgb[23:16]),
               .video_g(v_rgb[15:8]),
               .video_b(v_rgb[7:0]),
               .video_hsync(v_hsync),
               .video_vsync(v_vsync),
               .video_de(v_de),

               .test_card_data(64'h0),

               .sync_flybk(vidc_flybk),

               .is_hires(conf_hires)
               );


   ////////////////////////////////////////////////////////////////////////////////
   // Finally, combine peripheral read data back to the MCU:

   assign iomem_rdata = vidc_reg_select ? vidc_rd :
                        cgmem_select ? 32'hffffffff :
                        video_reg_select ? video_reg_rd :
                        ctrl_reg_select ? ctrl_rd :
                        32'h0;

endmodule // soc_top
