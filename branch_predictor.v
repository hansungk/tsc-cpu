`timescale 1ns/1ns

`define WORD_SIZE 16

module branch_predictor
  #(parameter WORD_SIZE = `WORD_SIZE)
   (input                      clk,
	input 					   reset_n, // clear BTB to all zero
	input 					   update_tag, // update tag on collision; synchronous write
	input [WORD_SIZE-1:0] 	   pc, // current PC
	input [WORD_SIZE-1:0] 	   pc_collided, // FIXME
	input [WORD_SIZE-1:0] 	   branch_target, // PC of the branch target
	output 					   tag_match, // tag matched PC
	output reg [WORD_SIZE-1:0] npc // predictd next PC; asynchronous read
);
   parameter BTB_IDX_SIZE = 8;

   // Tag table
   reg [WORD_SIZE-BTB_IDX_SIZE-1:0] tags[2**BTB_IDX_SIZE-1:0];
   // Branch target buffer
   reg [BTB_IDX_SIZE-1:0] 			btb[2**BTB_IDX_SIZE-1:0];
   // BTB index
   wire [BTB_IDX_SIZE-1:0] 			btb_idx;
   assign btb_idx = pc[BTB_IDX_SIZE-1:0];
   // PC tag
   wire [WORD_SIZE-BTB_IDX_SIZE-1:0] pc_tag;
   assign pc_tag = pc[WORD_SIZE-1:BTB_IDX_SIZE];
   // BTB hit
   assign tag_match = (tags[btb_idx] == pc_tag);

   wire [BTB_IDX_SIZE-1:0] 			 btb_idx_collided;
   assign btb_idx_collided = pc_collided[BTB_IDX_SIZE-1:0];
   wire [WORD_SIZE-BTB_IDX_SIZE-1:0] pc_tag_collided;
   assign pc_tag_collided = pc_collided[WORD_SIZE-1:BTB_IDX_SIZE];

   always @(*) begin
	  if (tag_match)
		npc = btb[btb_idx];
	  else
		npc = pc + 1;
   end

   integer i; // for reset
   
   always @(posedge clk) begin
	  if (!reset_n) begin
		 for (i=0; i<2**BTB_IDX_SIZE; i=i+1) begin
			// set to all 1 to make sure tag always misses on first
			// access on each entry
			tags[i] <= {WORD_SIZE-BTB_IDX_SIZE{1'b1}};
			btb[i] <= 0;
		 end
	  end
	  else begin
		 if (update_tag) begin
			tags[btb_idx_collided] <= pc_tag_collided;
			btb[btb_idx_collided] <= branch_target;
		 end
	  end
   end
endmodule
