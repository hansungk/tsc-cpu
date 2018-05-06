`timescale 1ns/1ns

`define WORD_SIZE 16

module branch_predictor
  #(parameter WORD_SIZE = `WORD_SIZE)
   (input                      clk,
	input 					   reset_n, // clear BTB to all zero
	input 					   update, // update tag on collision; synchronous write
	input [WORD_SIZE-1:0] 	   pc, // current PC
	input [WORD_SIZE-1:0] 	   branch_target, // PC of the branch target
	output 					   found, // tag matched PC
	output reg [WORD_SIZE-1:0] npc // predictd next PC; asynchronous read
);
   parameter BTB_IDX_SIZE = 8;

   // Tag table
   reg [2**BTB_IDX_SIZE-1:0] tags[WORD_SIZE-BTB_IDX_SIZE-1:0];
   // Branch target buffer
   reg [2**BTB_IDX_SIZE-1:0] btb[BTB_IDX_SIZE-1:0];
   // BTB index
   wire [BTB_IDX_SIZE-1:0] 	 btb_idx;
   assign btb_idx = pc[BTB_IDX_SIZE-1:0];
   // PC tag
   wire [WORD_SIZE-BTB_IDX_SIZE-1:0] pc_tag;
   assign pc_tag = pc[WORD_SIZE-1:WORD_SIZE-BTB_IDX_SIZE];
   // BTB hit
   wire btb_hit;
   assign btb_hit = (tags[btb_idx] == pc_tag);
   assign collision = !btb_hit;

   always @(*) begin
	  if (btb_hit)
		npc = btb[btb_idx];
	  else
		npc = pc + 1;
   end

   integer i; // for reset
   
   always @(posedge clk) begin
	  if (!reset_n) begin
		 for (i=0; i<2**BTB_IDX_SIZE; i=i+1) begin
			tags[i] <= 0;
			btb[i] <= 0;
		 end
	  end
	  else if (update) begin
		 tags[btb_idx] <= pc_tag;
		 btb[btb_idx] <= branch_target;
	  end
   end
endmodule
