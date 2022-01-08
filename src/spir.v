/* spir
 *
 * SPI responder (target/completer)
 *
 * Exposes a transaction interface to the SPI initiator, which in turn permits 32b
 * read/write accesses on an internal interconnect towards other system
 * components.  This is used to control internal regs from an external MCU.
 *
 * SPI clock is assumed to be << system clock, as it (and data) are sampled at
 * system clock.  Good for, say, 10MHz in a 50MHz system.
 *
 * 7 Jan 2022 ME
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

/*
 * Accesses from SPI initiator are all 48bit:
 *
 * 	byte 0	byte 1	byte 2	byte 3	byte 4	byte 5
 *
 * DIN	<-cmd/addr--->  <-- write data, if WR ------->
 *                      <-- read data, if RD -------->
 *
 * Command/addr bytes:
 * 	0 1 2 3 4 5 6 7 8 9 a b c d e f
 *      [C ][A0                 A11]0 0
 *
 * (Note: The two zero cycles at the end of the address are where a register
 * read transfer is performed.  This module does not support register
 * access wait states, so this is guaranteed.  Register writes happen in the
 * cucle after write data is complete, which might overlap the next transfer.)
 *
 * Commands:
 *	00:	Read word
 * 	01:	Write word
 * 	1x:	Reserved
 *
 * The r_valid strobe indicates a system-side register access.  Write data is
 * output in the cycle r_valid is active, and held until the next clock.
 * Read data is expected to be valid in the cycle after the first clock (i.e. is captured
 * on the 2nd clock after r_valid).
 *
 *
 * SPI: mode 0: sample in at rising edge, change out at falling edge
 * spi_do doesn't tristate.  Do tristate externally by:
 * 	pin_do = spi_ncs ? 1'bz : spi_do;
 */

module spir(input wire         clk,
            input wire         reset,

            input wire         spi_clk,
            input wire         spi_ncs,
            input wire         spi_di,
            output reg         spi_do,

            output wire        r_valid, // Register access request
	    output wire        r_wen, 	// Write cycle
	    output wire [11:0] r_addr, 	// This is a word address, i.e. 4K register space
	    output wire [31:0] r_wdata,
	    input wire [31:0]  r_rdata
            );

   /////////////////////////////////////////////////////////////////////////////
   // Synchronisers for external inputs:

   reg                    int_spi_clk_sync;
   reg                    int_spi_clk;
   reg                    int_spi_clk_last;
   reg			  int_spi_ncs_sync;
   reg			  int_spi_ncs;
   reg                    int_spi_di_sync;
   reg                    int_spi_di;

   always @(posedge clk) begin
      int_spi_clk_sync <= spi_clk;
      int_spi_clk      <= int_spi_clk_sync;
      int_spi_clk_last <= int_spi_clk;

      int_spi_ncs_sync <= spi_ncs;
      int_spi_ncs      <= int_spi_ncs_sync;

      int_spi_di_sync  <= spi_di;
      int_spi_di       <= int_spi_di_sync;
   end

   wire spi_selected 	= !int_spi_ncs;
   wire sclk_r		= !int_spi_clk_last && int_spi_clk; // rising edge
   wire sclk_f		= int_spi_clk_last && !int_spi_clk; // falling edge

   /////////////////////////////////////////////////////////////////////////////
   // Transaction FSM
   reg [11:0]             trx_address;
   reg [31:0]             trx_data;
   reg [1:0]              curr_cmd;
`define CMD_READ	2'b00
`define CMD_WRITE	2'b01

   reg [5:0]              counter;
   reg [2:0] 	   	  state;
`define STATE_CMD	0
`define STATE_ADDR 	1
`define STATE_WAIT 	2
`define STATE_DATA_IO 	3

   reg       	          write_pending;
   reg       	          read_pending;
   reg [1:0]              read_count;
   wire      		  do_read;
   assign do_read 	= read_pending;
   wire      		  do_write;
   assign do_write 	= (state == `STATE_CMD) && write_pending;
   reg                    obit;


   always @(posedge clk) begin
      if (reset) begin
         state         <= `STATE_CMD;
         counter       <= 0;
         write_pending <= 0;
         read_pending  <= 0;
         trx_address   <= 0;
         trx_data      <= 0;
         curr_cmd      <= `CMD_READ;
         read_count    <= 0;
         obit          <= 0;
         spi_do        <= 0;

      end else begin
         if (sclk_r) begin
            if (!spi_selected) begin
               // Releasing /CS resets the whole transaction.
               counter <= 0;
               state   <= `STATE_CMD;

            end else begin
               case (state)
                 `STATE_CMD: begin
                    // Two edges = two bits
                    curr_cmd <= {curr_cmd[0], int_spi_di};
                    if (counter == 0) begin
                       counter  <= 1;
                    end else begin
                       state   <= `STATE_ADDR;
                       counter <= 0;
                    end
                 end

                 `STATE_ADDR: begin
                    trx_address <= {trx_address[10:0], int_spi_di};
                    if (counter < 11) begin
                       counter <= counter + 1;
                    end else begin
                       state        <= `STATE_WAIT;
                       counter      <= 0;
                       read_pending <= (curr_cmd == `CMD_READ);
                    end
                 end

                 `STATE_WAIT: begin
                    if (counter == 0) begin
                       counter <= 1;
                    end else begin
                       state   <= `STATE_DATA_IO;
                       counter <= 0;

                       // Output data, as the host will capture it at next rising edge
                       if (curr_cmd == `CMD_READ) begin
                          spi_do    <= trx_data[31];
                          trx_data  <= {trx_data[30:0], 1'b0}; // MSB-first
                       end
                    end
                 end // case: `STATE_WAIT


                 `STATE_DATA_IO: begin
                    if (counter < 31) begin
                       counter <= counter + 1;
                    end else begin
                       state   <= `STATE_CMD;
                       counter <= 0;
                       // See below: do_write goes active here (for a write command).
                    end
                    // Sample input:
                    trx_data   <= {trx_data[30:0], int_spi_di}; // MSB-first
                    // Capture output bit (for later falling edge, below):
                    // obit       <= trx_data[31];
                    // FIXME: "incorrect but better", this rising edge is delayed after the input edge enough?
                    spi_do <= trx_data[31];
                 end

               endcase // case (state)
            end
         end // if (sclk_r)

         if (sclk_f && spi_selected && state == `STATE_DATA_IO) begin
            // FIXME: though this is at the flagged "falling edge", that can approach
            // the rising edge when SPI clock is fast due to sync delays.
            //            spi_do <= obit;
         end

         // write pending: Mirror the case above.
         if (sclk_r && spi_selected && state == `STATE_DATA_IO && counter == 31 && curr_cmd == `CMD_WRITE) begin
            write_pending <= 1;
         end else if (do_write) begin
            write_pending <= 0;
         end

         // read pending:
         if (read_pending && state == `STATE_WAIT) begin
            /* 2 cycles; in the first, r_valid just went
             * active and we give the component
             * 1 clock to get its house in order.  We capture
             * read data on the 2nd clock.
             */
            if (read_count == 0) begin
               read_count <= 1;
            end else begin
               read_count   <= 0;
               trx_data     <= r_rdata;
               read_pending <= 0;
            end
         end

      end
   end

   assign r_valid 	= (do_read || do_write);
   assign r_wen 	= do_write;
   assign r_addr 	= trx_address;
   assign r_wdata 	= trx_data;

endmodule // spir
