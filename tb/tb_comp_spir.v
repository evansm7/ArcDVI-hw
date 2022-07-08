/* Instantiates spir, sends it some transactions.
 *
 * 7/1/22 ME
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

`define CLK   	25
`define CLK_P 	(`CLK/2)
`define SIM 	1

`define SCLK   	100
`define SCLK_P 	(`SCLK/2)


module tb_comp_spir();

   reg 			 clk;
   reg 			 reset;

   always #`CLK_P       clk <= ~clk;

   ////////////////////////////////////////////////////////////////////////////////

   wire                  hs, vs, de;
   reg                   load_dma;

   reg [31:0]            reg_data[3:0];
   wire [11:0]           addr;
   wire                  wen;
   wire                  valid;
   wire [31:0]           reg_rdata = reg_data[addr[1:0]];
   wire [31:0]           reg_wdata;

   reg                   sclk;
   reg                   sncs;
   reg                   sdi;
   wire                  sdo;

   spir #(
                  ) DUT (
                         .clk(clk),
                         .reset(reset),

                         .spi_clk(sclk),
                         .spi_ncs(sncs),
                         .spi_di(sdi),
                         .spi_do(sdo),

                         .r_valid(valid),
	                 .r_wen(wen),
	                 .r_addr(addr),
	                 .r_wdata(reg_wdata),
	                 .r_rdata(reg_rdata)
	                 );

   ////////////////////////////////////////////////////////////////////////////////

   reg [47:0]            wval;
   reg [47:0]            rval;
   reg [31:0]            v;
   reg [31:0]            junk;

   always @(posedge clk) begin
      if (valid && wen)
        reg_data[addr[1:0]] <= reg_wdata;
   end

   initial begin
      if (!$value$plusargs("NO_VCD=%d", junk)) begin
         $dumpfile("tb_comp_spir.vcd");
         $dumpvars(0, tb_comp_spir);
      end

      for (v = 0; v < 4; v++)
        reg_data[v]  = 32'hfacebeef ^ (32'hcafecace << v);

      clk              <= 1;

      sclk             <= 0;
      sdi              <= 0;
      sncs             <= 1;

      reset            <= 1;
      #(`CLK*2);
      reset 	       <= 0;

      #(`CLK*10);

      @(posedge clk);

      // Now run a few clocks:
      #(`CLK*3);

      // Commands: 00 read, 01 write
      // 12 bits of address, 2 bits of 00, 32 bits of data:
      v = 32'hca75f00d;
      wval = {2'b01, 12'hcba, 2'b00, v};
      spi_xfer(wval, rval);

      // Read it back:
      wval = {2'b00, 12'hcba, 2'b00, 32'haaaaaaaa};
      spi_xfer(wval, rval);
      if (rval[31:0] != v)	$fatal(1, "FAIL: %x should be %x", rval[31:0], v);

      // Write different regs:
      v = 32'hbacecace;
      wval = {2'b01, 12'h000, 2'b00, v};
      spi_xfer(wval, rval);
      wval = {2'b00, 12'h000, 2'b00, 32'h0};
      spi_xfer(wval, rval);
      if (rval[31:0] != v)	$fatal(1, "FAIL: %x should be %x", rval[31:0], v);

      v = 32'hc0ffee00;
      wval = {2'b01, 12'h001, 2'b00, v};
      spi_xfer(wval, rval);
      wval = {2'b00, 12'h001, 2'b00, 32'hffffffff};
      spi_xfer(wval, rval);
      if (rval[31:0] != v)	$fatal(1, "FAIL: %x should be %x", rval[31:0], v);

      v = 32'hbaebface;
      wval = {2'b01, 12'h003, 2'b00, v};
      spi_xfer(wval, rval);
      wval = {2'b00, 12'h003, 2'b00, 32'hf0f0f0f0};
      spi_xfer(wval, rval);
      if (rval[31:0] != v)	$fatal(1, "FAIL: %x should be %x", rval[31:0], v);

      $display("PASS");

      $finish;
   end

   task spi_xfer;
      input [47:0]  tx;
      output [47:0] rx;
      reg [5:0]     count;
      reg [47:0]    orig_tx;
      begin
         count = 0;
         sclk  = 0;

         orig_tx = tx;
         // Sample input at rising edge, change output at falling edge:

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

endmodule
