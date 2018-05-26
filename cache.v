`include "constants.v"
`include "opcodes.v"

module cache
  #(parameter WORD_SIZE = `WORD_SIZE,
    parameter READ_SIZE = 4*`WORD_SIZE)
   (input                  clk,
    input                  reset_n,
    input                  readC,
    input                  writeC,
    input                  readyM,
    input [WORD_SIZE-1:0]  address,
    inout [WORD_SIZE-1:0]  data, // data bus to the processor
    inout [READ_SIZE-1:0]  dataM, // data bus to the memory
    // issue memory access for cache misses
    output reg             readM,
    output                 writeM,
    output                 readyC,
    output reg             miss,
    output [1:0]           index,
    output [1:0]           block);

   // State register
   // needs reset

   // 4 4-word wide cache blocks (16 words)
   reg [4*WORD_SIZE-1:0]  data_bank[3:0];
   // Tag width = WORD_SIZE - log2(cache size) = WORD_SIZE - 4
   reg [WORD_SIZE-5:0]    tag_bank[3:0];
   reg [3:0]              valid;
   // 'Dirty' bit for the write-back, write-no-allocate cache
   reg [3:0]              dirty;

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
   assign dataM = writeC ? ((data_bank[index] & mask) | (data << (block * WORD_SIZE))) : {READ_SIZE{1'bz}};

   assign writeM = writeC;
   assign readyC = (readC && hit) || (writeC && readyM);

   integer                i;

   always @(*) begin
      miss = !hit;
      readM = readC && !hit;
   end

   always @(posedge clk) begin
      if (!reset_n) begin
         for (i=0; i<4; i=i+1) begin
            data_bank[i] <= 0;
            tag_bank[i] <= 0;
            valid[i] <= 0;
            dirty[i] <= 0;
         end
      end
      else begin
         if (readC) begin
            // Update cache on read miss
            if (readM && readyM) begin
               // If a read is issued and it is a miss, issue memory read
               tag_bank[index] <= tag;
               data_bank[index] <= dataM;
               valid[index] <= 1;
            end
         end
         if (writeC) begin
            if (hit) begin
               tag_bank[index] <= tag;
               data_bank[index] <= dataM;
               valid[index] <= 1;
            end
         end
      end
   end
endmodule
