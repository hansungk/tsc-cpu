// Instruction register module

module IR
  #(parameter WORD_SIZE = 16)
   (
    input                      clk,
    input                      nop, // asynchrnously overwrite content to nop (0xFFFF)
    input                      write,
    input [WORD_SIZE-1:0]      write_data,
    output reg [WORD_SIZE-1:0] inst
    );

   always @(posedge clk) begin
      if (nop) begin
         // all 1 is not used in the ISA, so use that for nop
         inst <= {WORD_SIZE{1'b1}};
      end
      else if (write) begin
         inst <= write_data;
      end
   end
endmodule
