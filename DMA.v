`define WORD_SIZE 16
/*************************************************
* DMA module (DMA.v)
* input: clock (CLK), bus request (BR) signal, 
*        data from the device (edata), and DMA command (cmd)
* output: bus grant (BG) signal 
*         READ signal
*         memory address (addr) to be written by the device, 
*         offset device offset (0 - 2)
*         data that will be written to the memory
*         interrupt to notify DMA is end
* You should NOT change the name of the I/O ports and the module name
* You can (or may have to) change the type and length of I/O ports 
* (e.g., wire -> reg) if you want 
* Do not add more ports! 
*************************************************/

module DMA (
    input CLK, BG,
    input [4 * `WORD_SIZE - 1 : 0] edata,
    input [2 * `WORD_SIZE - 1 : 0] cmd, // [ADDR, LEN]
    output reg BR, READ,
    output [`WORD_SIZE - 1 : 0] addr, 
    output [4 * `WORD_SIZE - 1 : 0] data,
    output [1:0] offset,
    output interrupt);

   wire [`WORD_SIZE - 1 : 0] cmd_addr;
   wire [`WORD_SIZE - 1 : 0] cmd_len;
   assign cmd_addr = cmd[2 * `WORD_SIZE - 1 : `WORD_SIZE];
   assign cmd_len  = cmd[    `WORD_SIZE - 1 : 0];

   assign interrupt = !BR;

   initial begin
      BR <= 0;
   end

   always @(posedge CLK) begin
      if (cmd != 0) begin
         BR <= 1;
      end

      // TODO
      if (BG) begin
         #1000;
         BR <= 0;
      end
   end
endmodule


