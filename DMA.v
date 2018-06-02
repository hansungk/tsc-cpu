`timescale 1ns/1ns

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
    input                           CLK, BG,
    input [4 * `WORD_SIZE - 1 : 0]  edata,
    input [2 * `WORD_SIZE - 1 : 0]  cmd, // [ADDR, LEN]
    input                           doneM, // ADDED: write complete signal from memory
    output reg                      BR,
    output                          WRITE,
    output [`WORD_SIZE - 1 : 0]     addr, 
    output [4 * `WORD_SIZE - 1 : 0] data,
    output reg [1:0]                offset,
    output reg                      interrupt);

   // Buffer to store command (like IR)
   reg [2 * `WORD_SIZE - 1 : 0]     cmd_reg;

   wire [`WORD_SIZE - 1 : 0] cmd_addr;
   wire [`WORD_SIZE - 1 : 0] cmd_len;
   assign cmd_addr = cmd_reg[2 * `WORD_SIZE - 1 : `WORD_SIZE] + 4 * offset;
   assign cmd_len  = cmd_reg[    `WORD_SIZE - 1 : 0];

   assign addr = BG ? cmd_addr : 'bz;
   assign data = BG ? edata : 'bz;

   initial begin
      cmd_reg <= 'bz;
      offset <= 2'b0;
      BR <= 0;
      interrupt <= 0;
   end

   assign WRITE = BR && BG && !doneM;

   always @(posedge CLK) begin
      if (cmd != 0) begin
         BR <= 1;
         cmd_reg <= cmd;
      end

      if (BG) begin
         // Increase offset after each write
         if (doneM) begin
            // cmd_len = 12 (words), cmd_len >> 2 = 4 (writes)
            if (offset < (cmd_len >> 2) - 1) begin
               offset <= offset + 1;
               // Cycle stealing: disable BR after every write.
               BR <= 0;
            end else if (offset == (cmd_len >> 2) - 1) begin
               // Operation finish, return bus to CPU
               offset <= 0;
               BR <= 0;
            end
         end
      end // if (BG)

      // Cycle stealing: set BR back on after 1 cycle, provided there are
      // remaining data to be written.  The bus grant logic of the CPU will
      // handle the steal by itself.
      if (!BR && offset != 0) begin
         BR <= 1;
      end

      // Reset after operation finish
      if (interrupt) begin
         cmd_reg <= 'bz;
         interrupt <= 0;
      end
   end // always @ (posedge CLK)

   // Interrupt dma_end to CPU as soon as the CPU reclaims bus
   always @(negedge BG) begin
      // set interrupt only when it's over
      if (offset == 0)
        interrupt <= 1;
   end
endmodule


