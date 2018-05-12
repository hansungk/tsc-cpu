`timescale 1ns/1ns

`define WORD_SIZE 16

module branch_predictor
  #(parameter WORD_SIZE = `WORD_SIZE)
   (input                      clk,
    input                      reset_n, // clear BTB to all zero
    input                      update_tag, // update tag on collision; synchronous write
    input                      update_bht, // update BHT on branch outcome; synchronous write
    input [WORD_SIZE-1:0]      pc, // current PC
    input [WORD_SIZE-1:0]      pc_collided, // PC of the branch which just caused tag collision
                                                // (always pc_id)
    input [WORD_SIZE-1:0]      pc_outcome, // PC of the branch whose outcome is just decided
                                               // (could be either pc_ex or pc_id (JPR miss))
    input [WORD_SIZE-1:0]      branch_target, // PC of the branch target
    input                      branch_outcome, 
    output                     tag_match, // tag matched PC
    output reg [WORD_SIZE-1:0] npc // predictd next PC; asynchronous read
);
   parameter BRANCH_PREDICTOR = `BPRED_SATURATION_COUNTER;
   parameter BTB_IDX_SIZE = 8;

   // Tag table
   reg [WORD_SIZE-BTB_IDX_SIZE-1:0] tags[2**BTB_IDX_SIZE-1:0];
   // Branch history table
   reg [1:0]                        bht[2**BTB_IDX_SIZE-1:0];
   // Branch target buffer
   reg [BTB_IDX_SIZE-1:0]           btb[2**BTB_IDX_SIZE-1:0];
   // BTB index
   wire [BTB_IDX_SIZE-1:0]          btb_idx;
   assign btb_idx = pc[BTB_IDX_SIZE-1:0];
   // PC tag
   wire [WORD_SIZE-BTB_IDX_SIZE-1:0] pc_tag;
   assign pc_tag = pc[WORD_SIZE-1:BTB_IDX_SIZE];
   // BTB hit
   assign tag_match = (tags[btb_idx] == pc_tag);

   wire [BTB_IDX_SIZE-1:0]           btb_idx_collided;
   assign btb_idx_collided = pc_collided[BTB_IDX_SIZE-1:0];
   wire [WORD_SIZE-BTB_IDX_SIZE-1:0] pc_tag_collided;
   assign pc_tag_collided = pc_collided[WORD_SIZE-1:BTB_IDX_SIZE];

   // BHT update
   wire [BTB_IDX_SIZE-1:0]           btb_idx_outcome;
   assign btb_idx_outcome = pc_outcome[BTB_IDX_SIZE-1:0];

   always @(*) begin
      if (tag_match)
        npc = (bht[btb_idx] >= 2'b10) ? btb[btb_idx] : pc + 1;
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
            if (BRANCH_PREDICTOR == `BPRED_ALWAYS_TAKEN)
              bht[i] <= 2'b10; // initialize to 'weakly taken' and never update
            else
              bht[i] <= 2'b10; // initialize to 'weakly taken'
            btb[i] <= 0;
         end
      end
      else begin
         // On collision, at ID stage
         //
         // This should be done for all predictors including always taken.
         if (update_tag) begin
            tags[btb_idx_collided] <= pc_tag_collided;
            btb[btb_idx_collided] <= branch_target;
         end

         // On branch outcome, at EX(conditional)/ID(jump) stage
         if (update_bht) begin
            case (BRANCH_PREDICTOR)
              `BPRED_SATURATION_COUNTER: begin
                 if (branch_outcome) begin
                    if (bht[btb_idx_outcome] != 2'b11)
                      bht[btb_idx_outcome] <= bht[btb_idx_outcome] + 1;
                 end
                 else begin
                    if (bht[btb_idx_outcome] != 2'b00)
                      bht[btb_idx_outcome] <= bht[btb_idx_outcome] - 1;
                 end
              end
              `BPRED_HYSTERESIS_COUNTER: begin
                 if (branch_outcome) begin
                    case (bht[btb_idx_outcome])
                      2'b00: bht[btb_idx_outcome] <= 2'b01;
                      2'b01: bht[btb_idx_outcome] <= 2'b11;
                      2'b10: bht[btb_idx_outcome] <= 2'b11;
                      2'b11: bht[btb_idx_outcome] <= 2'b11;
                    endcase
                 end
                 else begin
                    case (bht[btb_idx_outcome])
                      2'b00: bht[btb_idx_outcome] <= 2'b00;
                      2'b01: bht[btb_idx_outcome] <= 2'b00;
                      2'b10: bht[btb_idx_outcome] <= 2'b00;
                      2'b11: bht[btb_idx_outcome] <= 2'b10;
                    endcase
                 end
              end
              // Never update BHT for always taken prediction
            endcase
         end
      end
   end
endmodule
