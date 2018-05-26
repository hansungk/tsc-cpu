`include "constants.v"
`include "opcodes.v"

module cache
  #(parameter WORD_SIZE = `WORD_SIZE)
   (input                 clk,
    input                 reset_n,
    input                 readC,
    input                 writeC,
    input                 readyM,
    input [WORD_SIZE-1:0] address,
    inout [WORD_SIZE-1:0] data, // data bus to the processor
    inout [WORD_SIZE-1:0] dataM, // data bus to the memory
    // issue memory access for cache misses
    output                readM,
    output                writeM,
    output                readyC,
    output reg            miss);

   // State register
   // needs reset

   // 4 4-word wide cache blocks (16 words)
   reg [4*WORD_SIZE-1:0]  data_bank[3:0];
   // Tag width = WORD_SIZE - log2(cache size) = WORD_SIZE - 6
   reg [WORD_SIZE-7:0]    tag_bank[3:0];
   reg [3:0]              valid;
   // 'Dirty' bit for the write-back, write-no-allocate cache
   reg [3:0]              dirty;

   // Logic

   // Processor <-> cache data bus: only output when read
   assign data = readC ? dataM : {WORD_SIZE{1'bz}};

   // Cache <-> memory data bus: only input when write
   assign dataM = writeM ? data : {WORD_SIZE{1'bz}};

   assign readM = readC;
   assign writeM = writeC;
   assign readyC = readyM;

   // Address decoding
   wire [2:0]             index;
   wire [WORD_SIZE-7:0]   tag;
   assign index = address[5:4];
   assign tag = address[WORD_SIZE-1:6];

   // Cache lookup hit
   wire                   hit;
   assign hit = valid[index] && (tag_bank[index] == tag);

   integer                i;

   always @(*) begin
      miss = !hit;
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
            if (hit) begin
               // data <= data_bank[index];
            end
            else begin
               tag_bank[index] <= tag;
               data_bank[index] <= data;
               valid[index] <= 1;
            end
         end
      end
   end
endmodule
