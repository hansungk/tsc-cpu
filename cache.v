`timescale 1ns/1ns

`include "constants.v"
`include "opcodes.v"

module cache
  #(parameter WORD_SIZE = `WORD_SIZE,
    parameter READ_SIZE = 4*`WORD_SIZE,
    parameter BYPASS = 1)
   (input                      clk,
    input                      reset_n,
    input                      bus_granted,
    input                      readC,
    input                      writeC,
    input                      input_readyM,
    input                      doneM,
    input [WORD_SIZE-1:0]      address,
    inout [WORD_SIZE-1:0]      data, // data bus to the processor
    inout [READ_SIZE-1:0]      dataM, // data bus to the memory
    // issue memory access for cache misses
    output [WORD_SIZE-1:0]     addressM,
    output reg                 readM,
    output reg                 writeM,
    output reg                 readyC,
    output reg [WORD_SIZE-1:0] num_cache_access,
    output reg [WORD_SIZE-1:0] num_cache_miss,
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

   reg                    done;

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
   assign data = !BYPASS ?
                 ((readC && readyC) ? (data_bank[index] >> (block * WORD_SIZE)) : {WORD_SIZE{1'bz}}) :
                 ((readC && readyC) ? dataM : {WORD_SIZE{1'bz}});

   // Cache <-> memory data bus: only input on cache/memory write
   wire [READ_SIZE-1:0]   mask;
   assign mask = ~({WORD_SIZE{1'b1}} << (block * WORD_SIZE));
   // Only use address bus when the bus is not used by DMA
   assign addressM = !bus_granted ? address : {WORD_SIZE{1'bz}};
   assign dataM = !bus_granted ?
                  !BYPASS ?
                  ((writeC && hit) ? (data_bank[index] & mask) | (data << (block * WORD_SIZE)) :
                   (writeC && block_ready) ? (temp_block & mask) | (data << (block * WORD_SIZE)) :
                   {READ_SIZE{1'bz}}) :
                  ((writeM) ? data : {READ_SIZE{1'bz}}) :
                  {READ_SIZE{1'bz}};

   integer i;

   always @(*) begin
      // Should access memory on both read miss and write miss, because write
      // needs whole cache block to be loaded.

      if (!BYPASS) begin
         // Memory read: when it's a read miss, or when it's a write miss and the
         // container block is not loaded yet.
         readM = ((readC && !hit) || (writeC && !hit && !block_ready)) && !input_readyM && !bus_granted;

         // Memory write: when it's a write hit, or when it's a write miss but the
         // container block is loaded by former readM.
         writeM = writeC && (hit || block_ready) && !doneM && !bus_granted;

         // Mark operation finish.
         //
         // Cache read finishes when the block is read in and exhibits a cache hit.
         // Cache write finishes when the final writeM finishes.
         readyC = (readC && hit) || (writeC && (doneM && !input_readyM && !bus_granted));
      end
      else begin
         readM = readC && !input_readyM && !bus_granted;
         writeM = writeC && !doneM && !bus_granted;
         readyC = (readC && input_readyM) || (writeC && (doneM && !input_readyM && !bus_granted));
      end
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
            num_cache_miss <= 0;
            num_cache_access <= 0;
         end
      end
      else begin
         // readC and writeC is guaranteed by the datapath to remain asserted
         // during an entire operation, so it is safe to do if check on them
         // without early-exiting.
         if (readC) begin
            // Read miss: read block into the cache.
            if (/*!hit & */input_readyM) begin
               // If a read is issued and it is a miss, issue memory read
               tag_bank[index] <= tag;
               data_bank[index] <= dataM;
               valid[index] <= 1;
               num_cache_miss <= num_cache_miss + 1;
            end
         end
         if (writeC && !bus_granted) begin
            // Write hit: update both cache and memory (memory handled above)
            // For a write-through cache, cache write should be altogether
            // prohibited under bus granted.
            if (hit && !bus_granted) begin
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
               num_cache_miss <= num_cache_miss + 1;
            end
         end

         // Every time an operation ends, reset block_ready and increment
         // num_cache_access.
         if (readyC) begin
            block_ready <= 0;
            num_cache_access <= num_cache_access + 1;
            // For cache bypass, report all-miss
            if (BYPASS) num_cache_miss <= num_cache_miss + 1;
         end
      end
   end
endmodule
