/* Testbench for soc_top_arcdvi
 *
 * Aiming to in some way mimic VIDC signals, and perform some SPI command
 * configuration as though from the MCU.
 *
 * 10/7/22 ME
 *
 * Copyright 2020, 2021, 2022 Matt Evans
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

`define CLK   	20
`define CLK_P 	(`CLK/2)
`define CLKV   	41
`define CLKV_P 	(`CLKV/2)
`define SIM 	1

`define SCLK_P  50

module tb_top_arcdvi();

   reg 			clk;
   reg 			clkv;
   reg 			reset;

   always #`CLK_P       clk <= ~clk;
   always #`CLKV_P      clkv <= ~clkv;

   ////////////////////////////////////////////////////////////////////////////////
   // Test units, model instances

   wire                 sdo;
   reg                  sclk;
   reg                  sncs;
   reg                  sdi;

   wire [31:0]          vidc_d;
   wire                 vidc_nvidw;
   wire                 vidc_nvcs;
   wire                 vidc_nhs;
   wire                 vidc_nsndrq;
   wire                 vidc_nvidrq;
   wire                 vidc_flybk;
   wire                 vidc_ckin;
   wire                 vidc_nsndak;
   wire                 vidc_nvidak;
   reg                  vidc_wr_req;
   wire                 vidc_wr_ack;
   reg [31:0]           vidc_wr_data;

   mem_model MEMC(.vidc_d(vidc_d),
                   .vidc_nwr(vidc_nvidw),
                   .vidc_nvidrq(vidc_nvidrq),
                   .vidc_nvidak(vidc_nvidak),
                   .vidc_nsndrq(vidc_nsndrq),
                   .vidc_nsndak(vidc_nsndak),

                   .vidc_reg_write_req(vidc_wr_req),
                   .vidc_reg_write_ack(vidc_wr_ack),
                   .wr_reg(vidc_wr_data)
                   );

   vidc_model VIDC(.vclk(clkv),
                   .vidc_d(vidc_d),
                   .vidc_nvidw(vidc_nvidw),
                   .vidc_nvcs(vidc_nvcs),
                   .vidc_nhs(vidc_nhs),
                   .vidc_nsndrq(vidc_nsndrq),
                   .vidc_nvidrq(vidc_nvidrq),
                   .vidc_flybk(vidc_flybk),
                   .vidc_nsndak(vidc_nsndak),
                   .vidc_nvidak(vidc_nvidak)
                   );

   // Note, no reset
   soc_top_arcdvi #(
                    ) DUT (
                           .clk_in(clk),

                           .spi_clk(sclk),
                           .spi_ncs(sncs),
                           .spi_din(sdi),
                           .spi_dout(sdo),

                           .vidc_d(vidc_d),
                           .vidc_nvidw(vidc_nvidw),
                           .vidc_nvcs(vidc_nvcs),
                           .vidc_nhs(vidc_nhs),
                           .vidc_nsndrq(vidc_nsndrq),
                           .vidc_nvidrq(vidc_nvidrq),
                           .vidc_flybk(vidc_flybk),
                           .vidc_ckin(clkv),
                           .vidc_nsndak(vidc_nsndak),
                           .vidc_nvidak(vidc_nvidak)
	                   );

   ////////////////////////////////////////////////////////////////////////////////

   reg 			junk;
   reg [31:0]           v;

   initial begin
      if (!$value$plusargs("NO_VCD=%d", junk)) begin
         $dumpfile("tb_top_arcdvi.vcd");
         $dumpvars(0, tb_top_arcdvi);
      end

      clk          <= 1;
      clkv         <= 1;
      reset        <= 1;
      sncs         <= 1;
      sclk         <= 0;
      sdi          <= 0;
      vidc_wr_req  <= 0;
      vidc_wr_data <= 0;

      #(`CLK*2);
      reset <= 0;

      $display("Starting sim");


      #(`CLK*100000);
      /* Set up video output regs */
      v = 32'h00000001;		/* Request sync */
      spi_wr(12'h808, v);

      #(`CLK*100000);

      /* Write some VIDC regs */
      for (v = 0; v < 16; v = v + 1) begin
         write_vidc_reg(v[5:0], {12'h000, v[3:0], v[3:0], v[3:0]} );	/* Pal 0-15 */
      end
      write_vidc_reg(6'h14, 24'h5a5a5a);	/* Special 0 */
      write_vidc_reg(6'h15, 24'hcace00);	/* Special 1 */

      /* See if they're accessible via the SPI interface....
       * VIDC regs are at address 0.
       */

      spi_rd(12'h000, v);
      $display("VIDC pal[0] = %x", v);
      spi_rd(12'h014, v);
      $display("VIDC special0 = %x", v);
      spi_rd(12'h015, v);
      $display("VIDC special1 = %x", v);

      #(`CLK*3000000);

      $display("Done.");
      $finish;
   end


   ////////////////////////////////////////////////////////////////////////////////
   // Helpers

   task spi_rd;
      input [11:0] addr;
      output [31:0] val;

      reg [47:0]    t;
      reg [47:0]    r;
      begin
         t = {2'b00 /* Read */, addr[11:0], 2'b00, 32'h0};
         spi_xfer(t, r);
         val = r[31:0];
      end
   endtask // spi_rd

   task spi_wr;
      input [11:0] addr;
      input [31:0] val;

      reg [47:0]    t;
      reg [47:0]    r;
      begin
         t = {2'b01 /* Write */, addr[11:0], 2'b00, val[31:0]};
         spi_xfer(t, r);
      end
   endtask // spi_rd

   task spi_xfer;
      input [47:0]  tx;
      output [47:0] rx;
      reg [5:0]     count;
      reg [47:0]    orig_tx;
      begin
         count   = 0;
         sclk    = 0;

         orig_tx = tx;
         /* Generate a shitty SPI "clock", not synchronous to anything.
          * Sample input at rising edge, change output at falling edge:
          */
         #`SCLK_P;
         sncs  = 0;
         #`SCLK_P;

         sdi = tx[47];			// MSB
         tx = {tx[46:0], tx[47]};

         #`SCLK_P;

         for (count = 0; count < 48; count++) begin
            #`SCLK_P;
            rx = {rx[46:0], sdo};
            sclk = 1;

            #`SCLK_P;
            sclk = 0;
            #1;
            sdi = tx[47];
            tx = {tx[46:0], tx[47]};
         end

         #1;
         sdi  = 0;
         #`SCLK_P;
         sncs = 1;

	 $display("[SPI: Read %x, write %x]", rx, orig_tx);
      end
   endtask

   task write_vidc_reg;
      input [5:0] addr;
      input [23:0] data;

      // Ask the mem model to flag a reg transfer plz
      vidc_wr_data <= {addr, 2'b00, data};
      vidc_wr_req  <= 1;
      wait (vidc_wr_ack == 1);
      wait (vidc_wr_ack == 0);
      vidc_wr_req  <= 0;
   endtask // write_vidc_reg

endmodule

////////////////////////////////////////////////////////////////////////////////

/* Models of VIDC and MEMC's DMA handshake
 *
 * These are the shittiest phonies ever, but create bus traffic roughly like
 * VIDC.  Cursors aren't differentiated, sound isn't supported, and
 * DMA doesn't really follow the FIFO timing, but it's roughly right.
 */

module mem_model(input wire	    vidc_nvidrq,
                 output reg         vidc_nvidak,
                 input wire	    vidc_nsndrq,
                 output reg         vidc_nsndak,
                 output reg  [31:0] vidc_d,
                 output reg         vidc_nwr,

                 input wire         vidc_reg_write_req,
                 output reg         vidc_reg_write_ack,
                 input wire [31:0]  wr_reg
                 );

   initial begin
      vidc_d             <= 32'h0;
      vidc_nwr           <= 1;
      vidc_nvidak        <= 1;
      vidc_nsndak        <= 1;	// No sound yet

      vidc_reg_write_ack <= 0;
   end

   int i;

   always @(negedge vidc_nvidrq) begin
      #(`CLKV * 1);
      for (i = 0; i < 4; i++) begin
         vidc_d <= vidc_d + 32'h01020304;
         #(`CLKV * 1);
         vidc_nvidak <= 0;
         #(`CLKV * 1);
         vidc_nvidak <= 1;
      end
   end

   always @(posedge vidc_reg_write_req) begin
      wait (vidc_nvidrq == 1);
      wait (vidc_nvidak == 1);
      vidc_d            <= wr_reg;
      #(`CLKV_P);
      vidc_nwr <= 0;
      #(`CLKV);
      vidc_nwr           <= 1;
      vidc_reg_write_ack <= 1;
      #1;
      vidc_reg_write_ack <= 0;
   end

endmodule // mem_model

module vidc_model(input wire 	    vclk,

                  input wire [31:0] vidc_d,
                  input wire        vidc_nvidw,
                  output wire       vidc_nvcs,
                  output wire       vidc_nhs,
                  output reg        vidc_nsndrq,
                  output reg        vidc_nvidrq,
                  output reg        vidc_flybk,
                  input wire        vidc_nsndak,
                  input wire        vidc_nvidak
                  );

   /* Shoot for roughly 640x480 mode timings */
   parameter hcyc = 800;
   parameter hsw = 95;
   parameter hstart = 132;
   parameter hend = 772;
   parameter vcyc = 525;
   parameter vsw = 3;
   parameter vstart = 33;
   parameter vend = 513;

   reg [31:0]                        x;
   reg [31:0]                        y;
   reg [7:0]                         dmac;
   reg                               last_va;

   initial begin
      x           <= 0;
      y           <= 0;
      vidc_flybk  <= 0;
      vidc_nvidrq <= 1;
      vidc_nsndrq <= 1;
      dmac        <= 0;
   end

   always @(posedge vclk) begin
      if (x < hcyc) begin
        x <= x + 1;
      end else begin
         x <= 0;

         if (y < vcyc) begin
            y <= y + 1;
         end else begin
            y <= 0;
         end
      end // else: !if(x < hcyc)

      if (y == vend) begin
         vidc_flybk <= 1;
      end else if (y == vstart - 1) begin
         vidc_flybk <= 0;
      end

      if (y >= vstart && y < vend &&
          x[3:0] == 4'b1111 && x > hsw) begin
         // Do some DMA requests
         vidc_nvidrq <= 0;
         dmac <= 0;
      end

      last_va     <= vidc_nvidak;

      if (last_va == 1 && vidc_nvidak == 0) begin
         if (dmac < 3)
           dmac <= dmac + 1;
         else
           vidc_nvidrq <= 1;
      end

   end // always @ (vclk)

   assign vidc_nvcs = ~(y < vsw);
   assign vidc_nhs = ~(x < hsw);


endmodule // vidc_model
