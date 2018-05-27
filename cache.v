`include "constants.v"
`include "opcodes.v"

module cache
  #(parameter WORD_SIZE = `WORD_SIZE,
    parameter READ_SIZE = 4*`WORD_SIZE)
   (input                  clk,
    input                      reset_n,
    input                      readC,
    input                      writeC,
    input                      readyM,
    input                      input_readyM,
    input                      doneM,
    input [WORD_SIZE-1:0]      address,
    inout [WORD_SIZE-1:0]      data, // data bus to the processor
    inout [READ_SIZE-1:0]      dataM, // data bus to the memory
    // issue memory access for cache misses
    output reg                 readM,
    output reg                 writeM,
    output                     readyC,
    output reg [WORD_SIZE-1:0] num_miss,
    output reg [WORD_SIZE-1:0] num_access,
    output [1:0]               index,
    output [1:0]               block);

   // State register
   // needs reset

   // 4 4-word wide cache blocks (16 words)
   reg [4*WORD_SIZE-1:0]  data_bank[3:0];
   // Tag width = WORD_SIZE - log2(cache size) = WORD_SIZE - 4
   reg [WORD_SIZE-5:0]    tag_bank[3:0];
   reg [3:0]              valid;
   // 'Dirty' bit for the write-back, write-no-allocate cache
   reg [3:0]              dirty;

   reg [READ_SIZE-1:0]    temp_block;
   reg                    block_ready;                    

   // Logic

   // Address decoding
   wire [1:0]             index;
   wire [WORD_SIZE-5:0]   tag;
   wire [1:0]             block;             
   assign index = address[3:2];
   assign tag = address[WORD_SIZE-1:4];
   assign block = address[1:0];

   // Cache lookup hit
   wire                   hit;
   assign hit = valid[index] && (tag_bank[index] == tag);

   // Processor <-> cache data bus: only output on processor read
   assign data = (readC && readyC) ? (data_bank[index] >> (block * WORD_SIZE)) : {WORD_SIZE{1'bz}};

   // Cache <-> memory data bus: only input on cache/memory write
   wire [READ_SIZE-1:0]   mask;
   assign mask = ~({WORD_SIZE{1'b1}} << (block * WORD_SIZE));
   assign dataM = (writeC && hit) ? (data_bank[index] & mask) | (data << (block * WORD_SIZE)) :
                  (writeC && block_ready) ? (temp_block & mask) | (data << (block * WORD_SIZE)) :
                  {READ_SIZE{1'bz}};

   // Mark operation finish.
   //
   // Cache read finishes when the block is read in and exhibits a cache hit.
   // Cache write finishes when the final writeM finishes.
   assign readyC = (readC && hit) || (writeC && (doneM && !input_readyM));

   integer i;

   always @(*) begin
      // Should access memory on both read miss and write miss, because write
      // needs whole cache block to be loaded.

      // Memory read: when it's a read miss, or when it's a write miss and the
      // container block is not loaded yet.
      readM = ((readC && !hit) || (writeC && !hit && !block_ready)) && !input_readyM;

      // Memory write: when it's a write hit, or when it's a write miss but the
      // container block is loaded by former readM.
      writeM = writeC && (hit || block_ready) && !doneM;
   end

   always @(posedge clk) begin
      if (!reset_n) begin
         for (i=0; i<4; i=i+1) begin
            data_bank[i] <= 0;
            tag_bank[i] <= 0;
            valid[i] <= 0;
            dirty[i] <= 0;
            temp_block <= 0;
            block_ready <= 0;
            num_miss <= 0;
            num_access <= 0;
         end
      end
      else begin
         // readC and writeC is guaranteed by the datapath to remain asserted
         // during an entire operation, so it is safe to do if check on them
         // without early-exiting.
         if (readC) begin
            // Read miss: read block into the cache.
            if (!hit && input_readyM) begin
               // If a read is issued and it is a miss, issue memory read
               tag_bank[index] <= tag;
               data_bank[index] <= dataM;
               valid[index] <= 1;
               num_miss <= num_miss + 1;
            end
         end
         if (writeC) begin
            // Write hit: update both cache and memory (memory handled above)
            if (hit) begin
               tag_bank[index] <= tag;
               data_bank[index] <= dataM;
               valid[index] <= 1;
            end
            // Write miss: wait until the container block is read, latch the
            // read block into a temporary register, write to it, and write
            // through to memory.
            if (!hit && input_readyM) begin
               temp_block <= dataM;
               block_ready <= 1;
               num_miss <= num_miss + 1;
            end
         end

         // Every time an operation ends, reset block_ready and increment num_access.
         if (readyC) begin
            block_ready <= 0;
            num_access <= num_access + 1;
         end
      end
   end
endmodule
