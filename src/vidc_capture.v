/* Capture VIDC registers, DMA and interesting configuration observations.
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

module vidc_capture(input wire 	       	      clk,
                    input wire                reset,

                    /* VIDC signals directly from pins: */
                    input wire [31:0]         vidc_d,
                    input wire                vidc_nvidw,
                    input wire                vidc_nvcs,
                    input wire                vidc_nhs,
                    input wire                vidc_nsndrq, // Unused
                    input wire                vidc_nvidrq,
                    input wire                vidc_flybk,
                    input wire                vidc_nsndak, // Unused
                    input wire                vidc_nvidak,

                    /* Input config */
                    input wire                conf_hires,

                    /* Output info: */
                    output wire [(12*16)-1:0] vidc_palette,
                    output wire [(12*3)-1:0]  vidc_cursor_palette,
                    output wire [10:0]        vidc_cursor_hstart,
                    output wire [9:0]         vidc_cursor_vstart,
                    output wire [9:0]         vidc_cursor_vend,

                    input wire [5:0]          vidc_reg_sel,
                    output wire [23:0]        vidc_reg_rdata,

                    output reg                tregs_status,
                    input wire                tregs_status_ack,

                    /* Debug counters: */
                    output reg [3:0]          fr_count,
                    output reg [15:0]         video_dma_counter,
                    output reg [15:0]         cursor_dma_counter,

                    /* Extension register interface: */
                    output reg                vidc_special_written,
                    output wire [23:0]        vidc_special,
                    output wire [23:0]        vidc_special_data,

                    /* DMA interface: */
                    output wire               load_dma,
                    output wire               load_dma_cursor,
                    output wire [31:0]        load_dma_data
                    );


   /* Principle of operation:
    *
    * The VIDC is clocked at 24MHz, but the register writes (strobed by /VIDW)
    * aren't necessarily synchronous to this.  We treat the strobe (and DMA
    * strobes from MEMC) as fully asynchronous, and synchronise them on input.
    *
    * A register write is then detected by the rising edge of /VIDW; the data
    * comes from a pipeline that gives the data sampled when /VIDW was still low.
    *
    * The DMA works the same, though the timing is tighter; the data comes from
    * a 1 stage deeper pipeline, i.e. "further back in time".
    */

   /* VIDC register mirrors, as per datasheet names.
    *
    * Our special "port" register is at register offset 0x50/54
    * (i.e. reg 0x14/0x15).
    * VIDC decodes this, harmlessly, to the border reg & cursor col1 reg.
    */
   reg [11:0]                                 vidc_VPLC[15:0];	 // Palette/colours ignore supremacy bit
   reg [11:0]                                 vidc_BCR;
   reg [11:0]                                 vidc_CPLC1;
   reg [11:0]                                 vidc_CPLC2;
   reg [11:0]                                 vidc_CPLC3;

   reg [23:0]                                 vidc_special0;
   reg [23:0]                                 vidc_special1;

   reg [2:0]                                  vidc_SIR[7:0];

   reg [9:0]                                  vidc_HCR;
   reg [9:0]                                  vidc_HSWR;
   reg [9:0]                                  vidc_HBSR;
   reg [9:0]                                  vidc_HDSR;
   reg [9:0]                                  vidc_HDER;
   reg [9:0]                                  vidc_HBER;
   reg [12:0]                                 vidc_HCSR;
   reg [9:0]                                  vidc_HIR;

   reg [9:0]                                  vidc_VCR;
   reg [9:0]                                  vidc_VSWR;
   reg [9:0]                                  vidc_VBSR;
   reg [9:0]                                  vidc_VDSR;
   reg [9:0]                                  vidc_VDER;
   reg [9:0]                                  vidc_VBER;
   reg [9:0]                                  vidc_VCSR;
   reg [9:0]                                  vidc_VCER;

   reg [8:0]                                  vidc_SFR; // Including test bit8
   reg [10:0]                                 vidc_CR;  // Compacted, 13:9 removed

   // Register reads (to MCU):
   reg [31:0]                                 rdata; // wire

   always @(*) begin
      rdata = 0;

      casez (vidc_reg_sel)
        6'b00????:		rdata = {12'h0, vidc_VPLC[vidc_reg_sel[3:0]]};
        6'b010000:		rdata = {12'h0, vidc_BCR};
        6'b010001:		rdata = {12'h0, vidc_CPLC1};
        6'b010010:		rdata = {12'h0, vidc_CPLC2};
        6'b010011:		rdata = {12'h0, vidc_CPLC3};
        6'b010100:		rdata = vidc_special0;
        6'b010101:		rdata = vidc_special1;

        6'b011000:		rdata = {21'h0, vidc_SIR[7]};
        6'b011001:		rdata = {21'h0, vidc_SIR[0]};
        6'b011010:		rdata = {21'h0, vidc_SIR[1]};
        6'b011011:		rdata = {21'h0, vidc_SIR[2]};
        6'b011100:		rdata = {21'h0, vidc_SIR[3]};
        6'b011101:		rdata = {21'h0, vidc_SIR[4]};
        6'b011110:		rdata = {21'h0, vidc_SIR[5]};
        6'b011111:		rdata = {21'h0, vidc_SIR[6]};
        6'b100000:		rdata = {vidc_HCR, 14'h0};
        6'b100001:		rdata = {vidc_HSWR, 14'h0};
        6'b100010:		rdata = {vidc_HBSR, 14'h0};
        6'b100011:		rdata = {vidc_HDSR, 14'h0};
        6'b100100:		rdata = {vidc_HDER, 14'h0};
        6'b100101:		rdata = {vidc_HBER, 14'h0};
        6'b100110:		rdata = {vidc_HCSR, 11'h0};
        6'b100111:		rdata = {vidc_HIR, 14'h0};
        6'b101000:		rdata = {vidc_VCR, 14'h0};
        6'b101001:		rdata = {vidc_VSWR, 14'h0};
        6'b101010:		rdata = {vidc_VBSR, 14'h0};
        6'b101011:		rdata = {vidc_VDSR, 14'h0};
        6'b101100:		rdata = {vidc_VDER, 14'h0};
        6'b101101:		rdata = {vidc_VBER, 14'h0};
        6'b101110:		rdata = {vidc_VCSR, 14'h0};
        6'b101111:		rdata = {vidc_VCER, 14'h0};
        6'b110000:		rdata = {15'h0, vidc_SFR};

        6'b111000:		rdata = {8'h0, vidc_CR[10:9], 5'b00000, vidc_CR[8:0]};
      endcase // case (vidc_reg_sel)
   end
   assign vidc_reg_rdata 	= rdata;


   ////////////////////////////////////////////////////////////////////////////////
   // Data bus capture, synchronisers and pipeline/history bit:
   reg                  vidc_nvidw_hist[2:0];
   reg [31:0]           vidc_d_hist[2:0];

   wire                 nvidw_edge          = (vidc_nvidw_hist[2] == 1) &&
                        (vidc_nvidw_hist[1] == 0);

   wire [5:0]           vidc_regw_addr      = vidc_d_hist[1][31:26];
   wire [23:0]          vidc_regw_data      = vidc_d_hist[1][23:0];

   /* Detect changes to display timing:
    * This isn't foolproof, testing only HCR/VCR, but is enough to detect a
    * standard OS-driven mode change.
    */
   wire                 tregs               = (vidc_regw_addr == 8'h80/4) ||
                        (vidc_regw_addr == 8'ha0/4);

   always @(posedge clk) begin
           if (reset) begin
                   tregs_status       	<= 1'b0;
                   vidc_nvidw_hist[0]   <= 1'b0;
                   vidc_nvidw_hist[1]   <= 1'b0;
                   vidc_nvidw_hist[2]   <= 1'b0;
                   vidc_special_written <= 0;

           end else begin
                   // Watch for nVIDW falling edge:
                   vidc_nvidw_hist[0] <= vidc_nvidw;
                   vidc_nvidw_hist[1] <= vidc_nvidw_hist[0];
                   vidc_nvidw_hist[2] <= vidc_nvidw_hist[1];

                   // Synchroniser/delay on D to align with sampled edge:
                   vidc_d_hist[0] <= vidc_d;
                   vidc_d_hist[1] <= vidc_d_hist[0];
                   vidc_d_hist[2] <= vidc_d_hist[1];

                   /* vidc_d_hist[1] (vidc_regw_data) is data sampled
                    * at same point as the strobe which has been
                    * detected as being low.
                    */
                   if (nvidw_edge) begin
                           casez (vidc_regw_addr)
                             6'b00????:	vidc_VPLC[vidc_regw_addr[3:0]] <= vidc_regw_data[11:0];
                             6'b010000:	vidc_BCR	<= vidc_regw_data[11:0];
                             6'b010001:	vidc_CPLC1	<= vidc_regw_data[11:0];
                             6'b010010:	vidc_CPLC2 	<= vidc_regw_data[11:0];
                             6'b010011:	vidc_CPLC3	<= vidc_regw_data[11:0];
                             6'b010100:	vidc_special0	<= vidc_regw_data[23:0];
                             6'b010101:	vidc_special1	<= vidc_regw_data[23:0];

                             6'b011000:	vidc_SIR[7]	<= vidc_regw_data[2:0];
                             6'b011001:	vidc_SIR[0]	<= vidc_regw_data[2:0];
                             6'b011010:	vidc_SIR[1]	<= vidc_regw_data[2:0];
                             6'b011011:	vidc_SIR[2]	<= vidc_regw_data[2:0];
                             6'b011100:	vidc_SIR[3]	<= vidc_regw_data[2:0];
                             6'b011101:	vidc_SIR[4]	<= vidc_regw_data[2:0];
                             6'b011110:	vidc_SIR[5]	<= vidc_regw_data[2:0];
                             6'b011111:	vidc_SIR[6]	<= vidc_regw_data[2:0];
                             6'b100000:	vidc_HCR	<= vidc_regw_data[23:14];
                             6'b100001:	vidc_HSWR	<= vidc_regw_data[23:14];
                             6'b100010:	vidc_HBSR	<= vidc_regw_data[23:14];
                             6'b100011:	vidc_HDSR	<= vidc_regw_data[23:14];
                             6'b100100:	vidc_HDER	<= vidc_regw_data[23:14];
                             6'b100101:	vidc_HBER	<= vidc_regw_data[23:14];
                             6'b100110:	vidc_HCSR	<= vidc_regw_data[23:11];
                             6'b100111:	vidc_HIR	<= vidc_regw_data[23:14];
                             6'b101000:	vidc_VCR	<= vidc_regw_data[23:14];
                             6'b101001:	vidc_VSWR	<= vidc_regw_data[23:14];
                             6'b101010:	vidc_VBSR	<= vidc_regw_data[23:14];
                             6'b101011:	vidc_VDSR	<= vidc_regw_data[23:14];
                             6'b101100:	vidc_VDER	<= vidc_regw_data[23:14];
                             6'b101101:	vidc_VBER	<= vidc_regw_data[23:14];
                             6'b101110:	vidc_VCSR	<= vidc_regw_data[23:14];
                             6'b101111:	vidc_VCER	<= vidc_regw_data[23:14];
                             6'b110000:	vidc_SFR	<= vidc_regw_data[8:0];

                             6'b111000: begin
	                        vidc_CR[10:9] 		<= vidc_regw_data[15:14];
                                vidc_CR[8:0]		<= vidc_regw_data[8:0];
                             end
                           endcase // case (vidc_reg_sel)

                           vidc_special_written      <= (vidc_regw_addr == 6'h14);

                           if (tregs && (tregs_status_ack == tregs_status))
                             tregs_status <= ~tregs_status;
                   end else begin
                           vidc_special_written <= 0;
                   end
           end
   end


   ////////////////////////////////////////////////////////////////////////////////
   // Registers to export directly to display circuitry:

   assign vidc_cursor_hstart         	= conf_hires ? vidc_HCSR[10:0] : vidc_HCSR[12:2];
   assign vidc_cursor_vstart 		= vidc_VCSR - vidc_VDSR;
   assign vidc_cursor_vend 		= vidc_VCER - vidc_VDSR;

   assign vidc_palette  		= { vidc_VPLC[15], vidc_VPLC[14],
                                            vidc_VPLC[13], vidc_VPLC[12],
                                            vidc_VPLC[11], vidc_VPLC[10],
                                            vidc_VPLC[9], vidc_VPLC[8],
                                            vidc_VPLC[7], vidc_VPLC[6],
                                            vidc_VPLC[5], vidc_VPLC[4],
                                            vidc_VPLC[3], vidc_VPLC[2],
                                            vidc_VPLC[1], vidc_VPLC[0] };

   assign vidc_cursor_palette 		= { vidc_CPLC3, vidc_CPLC2, vidc_CPLC1 };

   // When vidc_special is changed, vidc_special_written pulses:
   assign        vidc_special	 	= vidc_special0;
   assign        vidc_special_data  	= vidc_special1;


   ////////////////////////////////////////////////////////////////////////////////
   // Tracking syncs and DMA requests:

   wire			vs, hs, vs_last, hs_last;
   reg [2:0]            s_vs;
   reg [2:0]            s_hs;
   reg [2:0]            s_flybk;
   assign		vs = s_vs[1];	// Watch out!  Might be composite sync
   assign		hs = s_hs[1];
   assign		vs_last = s_vs[2];
   assign		hs_last = s_hs[2];
   wire                 flybk = s_flybk[1];
   wire                 flybk_last = s_flybk[2];

   wire			vdrq, vdak, vdrq_last, vdak_last;
   reg [2:0]	        s_vdrq;
   reg [2:0]	        s_vdak;
   assign		vdrq             = s_vdrq[1];
   assign		vdrq_last 	 = s_vdrq[2];
   assign		vdak             = s_vdak[1];
   assign		vdak_last 	 = s_vdak[2];
   wire			new_video_dmarq  = (vdrq == 0) && (hs == 1);
   wire			new_cursor_dmarq = (vdrq == 0) && (hs == 0);

   reg [15:0]           int_v_dma_counter;
   reg [15:0]           int_c_dma_counter;
   reg [2:0]            dma_beat_counter;
   reg [1:0]            v_state;

   wire                 flybk_start      = ~flybk_last && flybk;
   wire                 vdak_rising_edge = vdak_last == 0 && vdak == 1;
   wire                 hs_rising_edge   = hs_last == 0 && hs == 1;

   always @(posedge clk) begin
           if (reset) begin
                   v_state  <= 0;
                   s_vs     <= 3'b111;
                   s_hs     <= 3'b111;
                   s_flybk  <= 3'b111;
                   s_vdrq   <= 3'b111;
                   s_vdak   <= 3'b111;
                   fr_count <= 0;
           end else begin

                   // Synchronisers & history/edge-detect:
                   s_vs[2:0]    <= {s_vs[1:0], vidc_nvcs};
                   s_hs[2:0]    <= {s_hs[1:0], vidc_nhs};
                   s_flybk[2:0] <= {s_flybk[1:0], vidc_flybk};

                   s_vdrq[2:0]  <= {s_vdrq[1:0], vidc_nvidrq};
                   s_vdak[2:0]  <= {s_vdak[1:0], vidc_nvidak};

                   if (flybk_start) begin
                           // reset counters at start of flyback
                           video_dma_counter  <= int_v_dma_counter;
                           int_v_dma_counter  <= 0;
                           cursor_dma_counter <= int_c_dma_counter;
                           int_c_dma_counter  <= 0;

                           // Useful for LED blinky, and wait-for-next-frame:
                           fr_count           <= fr_count + 1;
                   end

                   /* Note, it can happen that a DMA ack occurs coincident with
                    * the start of flyback... so a counter could be incremented
                    * after all.
                    *
                    * This FSM relies on MEMC always returning four beats (as
                    * it should).
                    */
                   if (v_state == 0) begin // Idle
                           if (new_video_dmarq) begin
                                   v_state           <= 1;
                                   int_v_dma_counter <= int_v_dma_counter + 1;
                                   dma_beat_counter  <= 3;
                           end else if (new_cursor_dmarq) begin
                                   v_state           <= 2;
                                   int_c_dma_counter <= int_c_dma_counter + 1;
                                   dma_beat_counter  <= 3;
                           end
                   end else begin // Some kind of DMA ongoing
                           // Look for a rising edge on vidak:
                           if (vdak_rising_edge) begin
                                   // FIXME, poke vidc_d_hist[1] into FIFO
                                   if (dma_beat_counter != 0) begin
                                           dma_beat_counter <= dma_beat_counter - 1;
                                   end else begin
                                           // Seen 'em all.
                                           v_state <= 0;
                                   end
                           end
                   end
           end
   end // always @ (posedge clk)

   // Now we know when DMA is being transferred, and have the data:
   assign load_dma              = !reset && (v_state == 1) && vdak_rising_edge;
   assign load_dma_cursor       = !reset && (v_state == 2) && vdak_rising_edge;
   assign load_dma_data 	= vidc_d_hist[2];

endmodule // vidc_capture
