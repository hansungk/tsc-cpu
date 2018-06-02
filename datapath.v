`timescale 1ns / 1ns
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2018/04/06 15:53:03
// Design Name: 
// Module Name: datapath
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

`include "constants.v"
`include "opcodes.v"

`define WORD_SIZE 16

module datapath
  #(parameter WORD_SIZE = `WORD_SIZE,
    parameter RF_SELF_FORWARDING = 1,
    parameter DATA_FORWARDING = 1,
    parameter BRANCH_PREDICTOR = `BPRED_SATURATION_COUNTER,
    parameter CACHE = 1)
   (input                      clk,
    input                        reset_n,
    input [1:0]                  pc_src,
    input                        i_or_d,

    // See control_unit.v for docs for each control signals

    // ID control signals
    input                        output_write,

    // EX control signals
    input [3:0]                  alu_op,
    input                        alu_src_a,
    input [1:0]                  alu_src_b,
    input                        alu_src_swap, 
    input [1:0]                  reg_dst,
    input                        branch,

    // MEM control signals
    // input                      i_mem_read, 
    input                        d_mem_read, 
    input                        i_mem_write,
    input                        d_mem_write,
    input                        i_ready,
    input                        i_input_ready,
    input                        d_ready,

    // WB control signals
    input                        reg_write,
    input [1:0]                  reg_write_src,
    input                        halt_id,

    // DMA
    input                        dma_begin,
    input                        dma_end,
    input                        bus_request,
    output reg                   bus_granted,
    output reg [2*WORD_SIZE-1:0] dma_cmd,

    output [WORD_SIZE-1:0]       i_address,
    output [WORD_SIZE-1:0]       d_address,
    output                       i_read,
    output                       d_read,
    output                       i_write,
    output                       d_write,
    inout [WORD_SIZE-1:0]        i_data,
    inout [WORD_SIZE-1:0]        d_data,
    output reg [WORD_SIZE-1:0]   output_port,
    output [3:0]                 opcode,
    output [5:0]                 func_code,
    output [2:0]                 inst_type,
    output                       is_halted, 
    output [WORD_SIZE-1:0]       num_inst,
    output reg [WORD_SIZE-1:0]   num_branch, // number of branches encountered
    output reg [WORD_SIZE-1:0]   num_branch_miss // number of branch prediction miss
);
   //-------------------------------------------------------------------------//
   // Wires
   //-------------------------------------------------------------------------//

   // Decoded info
   wire [1:0]           rs, rt, rd;
   wire [7:0]           imm;
   wire [11:0]          target_imm;
   wire [WORD_SIZE-1:0] imm_signed;

   // Hazard signals
   wire                 i_mem_read; // FIXME
   wire                 pc_write;
   wire                 ir_write;
   wire                 bubblify_id; // reset all control signals to zero
   wire                 bubblify_ex;
   wire                 bubblify_mem;
   wire                 flush_if; // reset IR to nop
   wire                 cond_branch_taken;

   // Conditional branch prediction miss flag.  If branch prediction
   // is disabled, this is always set to 1.
   wire                 cond_branch_miss;

   wire [WORD_SIZE-1:0] resolved_pc; // PC resolved as either branch target or PC+1
   wire [WORD_SIZE-1:0] jump_target; // target PC for unconditional branches (Jump)
   wire [WORD_SIZE-1:0] cond_branch_target; // target PC for conditional branches
   wire [WORD_SIZE-1:0] branch_target; // target PC for branches

   wire [WORD_SIZE-1:0] npc; // next PC; connected to either npc_pred
                             // or pc + 1 depending on configuration
   wire [WORD_SIZE-1:0] npc_pred; // predicted next PC (branch predictor output)
   wire                 tag_match; // BTB tag matched PC (branch predictor output)
   wire                 update_tag; // update BTB tag (branch predictor input)
   reg                  update_bht; // update BHT (branch predictor input)
   reg [WORD_SIZE-1:0]  pc_outcome; // PC when branch outcome is decided (branch predictor input)
   reg                  branch_outcome; // branch outcome (branch predictor input)

   wire                 incr_num_inst; // increase num_inst when it becomes positive that the
                                       // fetched instruction will not be discarded
   reg                  incr_num_branch; // increase num_branch when it becomes positive that the
                                         // fetched instruction will not be discarded, and is a
                                         // branch instruction

   wire                 d_cache_busy; // cache is handling read/write but is not ready yet

   // Unconditional branch prediction miss flag.  If branch prediction
   // is disabled, this is always set to 1.
   wire                 jump_miss;

   // Forward signals
   wire [1:0]           rs_forward_src;
   wire [1:0]           rt_forward_src;

   // register file
   wire [1:0]           addr1, addr2, addr3;
   wire [WORD_SIZE-1:0] data1, data2, writeData;

   // ALU
   wire [WORD_SIZE-1:0] mem_forwarded, a_forwarded, b_forwarded;
   wire [WORD_SIZE-1:0] alu_temp_1, alu_temp_2; // operands before swap
   wire [WORD_SIZE-1:0] alu_operand_1, alu_operand_2; // operands after swap
   wire [WORD_SIZE-1:0] alu_result;

   //-------------------------------------------------------------------------//
   // Pipeline registers
   //-------------------------------------------------------------------------//
   // don't forget to reset

   // Global
   reg                  interrupted; // save CPU interrupt state

   // unconditional latches
   reg [WORD_SIZE-1:0]  pc, pc_id, pc_ex, pc_mem, pc_wb; // program counter
   reg [WORD_SIZE-1:0]  pc_buffer;
   reg [WORD_SIZE-1:0]  npc_id, npc_ex, npc_mem, npc_wb; // PC + 4 saved for branch resolution and JAL writeback
   reg [WORD_SIZE-1:0]  cond_branch_target_ex; // carry branch target for misprediction check
   reg                  tag_match_id; // BTB search failed in IF;
                                      // should update in ID stage
   reg [WORD_SIZE-1:0]  inst_type_ex, inst_type_mem, inst_type_wb;
   wire [WORD_SIZE-1:0] ir; // instruction register, bound to separate module
   reg [WORD_SIZE-1:0]  MDR_wb; // memory data register
   reg [1:0]            rs_ex, rs_mem, rs_wb; // for stall/forward detection
   reg [1:0]            rt_ex, rt_mem, rt_wb; // for stall/forward detection
   reg [1:0]            rd_ex; // for write_reg
   reg [1:0]            write_reg_ex, write_reg_mem, write_reg_wb;
   reg [WORD_SIZE-1:0]  a_ex, b_ex, b_mem;
   reg [WORD_SIZE-1:0]  alu_out_mem, alu_out_wb;
   reg [WORD_SIZE-1:0]  imm_signed_ex, imm_signed_mem, imm_signed_wb;
   reg                  halt_ex, halt_mem, halt_wb;

   // Even though HLT is detected in ID, we have to wait in-flight instructions
   // to finish, so defer actual halt to the end of the pipeline.
   assign is_halted = halt_wb;

   // debug purpose: which inst # is being passed through this stage?
   // num_inst_if effectively means "number of instructions fetched"
   reg [WORD_SIZE-1:0]  num_inst_if, num_inst_id, num_inst_ex;
   reg [WORD_SIZE-1:0]  num_inst_if_saved_buffer;
   reg [WORD_SIZE-1:0]  num_inst_if_saved;
   assign num_inst = num_inst_ex; // num_inst is the inst passing through EX right now

   // control signal latches
   reg                  branch_ex; // branch instruction in EX?
   reg                  output_write_ex;
   reg [3:0]            alu_op_ex;
   reg                  alu_src_a_ex;
   reg [1:0]            alu_src_b_ex;
   reg                  alu_src_swap_ex;
   reg                  i_mem_read_ex, i_mem_read_mem;
   reg                  d_mem_read_ex, d_mem_read_mem;
   reg                  i_mem_write_ex, i_mem_write_mem;
   reg                  d_mem_write_ex, d_mem_write_mem, d_mem_write_wb;
   reg                  reg_write_ex, reg_write_mem, reg_write_wb;
   reg [1:0]            reg_write_src_ex, reg_write_src_mem, reg_write_src_wb;

   //-------------------------------------------------------------------------//
   // Module declarations
   //-------------------------------------------------------------------------//

   ALU alu(.OP(alu_op_ex),
           .A(alu_operand_1),
           .B(alu_operand_2),
           .Cin(1'b0),
           .C(alu_result)
           /*.Cout()*/);

   // Register file
   RF rf(.clk(RF_SELF_FORWARDING ? !clk : clk), // self-forwarding: write at negedge
         .reset_n(reset_n),
         .write(reg_write_wb),
         .addr1(addr1),
         .addr2(addr2),
         .addr3(addr3),
         .data1(data1),
         .data2(data2),
         .data3(writeData));

   // Instruction register
   IR ir_module(.clk(clk),
                .nop(flush_if || !reset_n),
                .write(ir_write),
                .write_data(i_data),
                .inst(ir));

   // Instruction type decoder
   InstTypeDecoder itd(.opcode(opcode),
                       .func_code(func_code),
                       .inst_type(inst_type));

   hazard_unit #(.RF_SELF_FORWARDING(RF_SELF_FORWARDING),
                 .DATA_FORWARDING(DATA_FORWARDING),
                 .CACHE(CACHE))
   HU (.clk(clk),
       .reset_n(reset_n),
       .opcode(opcode),
       .inst_type(inst_type),
       .func_code(func_code),
       .jump_miss(jump_miss),
       .cond_branch_miss(cond_branch_miss),
       .rs_id(rs),
       .rt_id(rt),
       .reg_write_ex(reg_write_ex),
       .reg_write_mem(reg_write_mem),
       .reg_write_wb(reg_write_wb),
       .write_reg_ex(write_reg_ex),
       .write_reg_mem(write_reg_mem),
       .write_reg_wb(write_reg_wb),
       .d_mem_read_ex(d_mem_read_ex),
       .d_mem_read_mem(d_mem_read_mem),
       .d_mem_read_wb(d_mem_read_wb),
       .d_mem_write_mem(d_mem_write_mem),
       .d_mem_write_wb(d_mem_write_wb),
       .i_ready(i_ready),
       .i_input_ready(i_input_ready),
       .d_ready(d_ready),
       .d_cache_busy(d_cache_busy),
       .rt_ex(rt_ex),
       .rt_mem(rt_mem),
       .rt_wb(rt_wb),
       .bus_granted(bus_granted),
       .i_mem_read(i_mem_read),
       .bubblify_id(bubblify_id),
       .bubblify_ex(bubblify_ex),
       .bubblify_mem(bubblify_mem),
       .flush_if(flush_if),
       .pc_write(pc_write),
       .ir_write(ir_write),
       .freeze_ex(freeze_ex),
       .freeze_mem(freeze_mem),
       .incr_num_inst(incr_num_inst));

   forwarding_unit #(.DATA_FORWARDING(DATA_FORWARDING))
   FU (.rs_ex(rs_ex),
       .rt_ex(rt_ex),
       .reg_write_mem(reg_write_mem),
       .reg_write_wb(reg_write_wb),
       .write_reg_mem(write_reg_mem),
       .write_reg_wb(write_reg_wb),
       .rs_forward_src(rs_forward_src),
       .rt_forward_src(rt_forward_src));

   branch_predictor #(.BTB_IDX_SIZE(8),
                      .BRANCH_PREDICTOR(BRANCH_PREDICTOR))
   BPRED (.clk(clk),
          .reset_n(reset_n),
          .update_tag(update_tag),
          .update_bht(update_bht),
          .pc(pc),
          .pc_collided(pc_id),
          .pc_outcome(pc_outcome),
          .branch_target(branch_target),
          .branch_outcome(branch_outcome),
          .tag_match(tag_match),
          .npc(npc_pred));

   //-------------------------------------------------------------------------//
   // Wire connections
   //-------------------------------------------------------------------------//

   // Global
   assign d_cache_busy = (d_read || d_write) && !d_ready;

   // IF stage
   // Connect npc to either BTB or pc+1 depending on the prediction policy
   assign npc = (BRANCH_PREDICTOR == `BPRED_NONE || BRANCH_PREDICTOR == `BPRED_ALWAYS_UNTAKEN) ?
                pc + 1 : npc_pred;
   assign i_address = pc;
   assign i_read = i_mem_read;
   assign i_write = 0; // no instruction write

   // ID stage
   assign opcode = ir[15:12];
   assign func_code = ir[5:0];
   assign rs = ir[11:10];
   assign rt = ir[9:8];
   assign rd = ir[7:6];
   assign addr1 = rs;
   assign addr2 = rt;
   assign imm = ir[7:0];
   assign imm_signed = {{8{imm[7]}}, imm};
   assign target_imm = ir[11:0];

   // Branch targets
   assign jump_target = (opcode == `OPCODE_RTYPE && (func_code == `FUNC_JPR || func_code == `FUNC_JRL)) ?
                        data1 :
                        {pc[15:12], target_imm};
   assign cond_branch_target = (pc_id + 1) + imm_signed; // FIXME
   assign branch_target = (inst_type == `INSTTYPE_JUMP) ?
                          jump_target :
                          cond_branch_target;
   assign jump_miss = (inst_type == `INSTTYPE_JUMP) &&
                      ((BRANCH_PREDICTOR != `BPRED_NONE) ? (jump_target != npc_id) : 1); // always miss on no prediction

   // If this is a branch instruction and BTB tag match failed in IF,
   // update tag in ID stage.
   assign update_tag = (inst_type == `INSTTYPE_JUMP || inst_type == `INSTTYPE_BRANCH) &&
                       !tag_match_id;
   
   // EX stage
   // Data forwarding (see forwarding_unit.v)

   // Since either ALUOut or immediate value can be forwarded from the MEM stage
   // (LHI), we need to check which is going to be eventually written back using
   // reg_write_src_mem, and forward the right one.
   assign mem_forwarded = (reg_write_src_mem == `REGWRITESRC_IMM) ? imm_signed_mem
                          : alu_out_mem;

   assign a_forwarded = (rs_forward_src == `FORWARD_SRC_MEM) ? mem_forwarded :
                        (rs_forward_src == `FORWARD_SRC_WB)  ? writeData :
                        /*(rs_forward_src == `FORWARD_SRC_RF) ?*/ a_ex;
   assign b_forwarded = (rt_forward_src == `FORWARD_SRC_MEM) ? mem_forwarded :
                        (rt_forward_src == `FORWARD_SRC_WB)  ? writeData :
                        /*(rt_forward_src == `FORWARD_SRC_RF) ?*/ b_ex;

   assign alu_temp_1 = (alu_src_a_ex == `ALUSRCA_PC) ? pc :
                       /*(alu_src_a_ex == `ALUSRCA_REG) ?*/ a_forwarded;
   assign alu_temp_2 = (alu_src_b_ex == `ALUSRCB_ONE) ? 1 :
                       (alu_src_b_ex == `ALUSRCB_REG) ? b_forwarded :
                       (alu_src_b_ex == `ALUSRCB_IMM) ? imm_signed_ex :
                       /*(alu_src_b_ex == `ALUSRCB_ZERO) ?*/ 0;

   assign alu_operand_1 = alu_src_swap_ex ? alu_temp_2 : alu_temp_1;
   assign alu_operand_2 = alu_src_swap_ex ? alu_temp_1 : alu_temp_2;
   assign cond_branch_taken = alu_result != 0; // alu_result == 0 means branch check fail
   assign resolved_pc = cond_branch_taken ? cond_branch_target_ex : (pc_ex + 1); // FIXME
   // Always miss if there is no prediction.
   assign cond_branch_miss = branch_ex &&
                             ((BRANCH_PREDICTOR != `BPRED_NONE) ? (resolved_pc != npc_ex) : 1);

   // BHT update logic
   always @(*) begin
      // Update BHT according to the branch outcome.  Done regardless
      // of hit/miss.
      //
      // If both conditional branch in EX and unconditional branch in ID was
      // mispredicted (possible with indirect jumps such as JPR), prioritize
      // conditional branch because then the ID stage instruction will be
      // flushed away.  Update num_branch here as well.  (same as PC resolution
      // logic below)
      if (branch_ex) begin // at EX stage
         update_bht = 1;
         pc_outcome = pc_ex;
         branch_outcome = cond_branch_taken;
         incr_num_branch = 1;
      end
      else if (inst_type == `INSTTYPE_JUMP) begin // at ID stage
         update_bht = 1;
         pc_outcome = pc_id;
         // All jump_miss happens on indirect jumps (e.g. JPR).
         //
         // We can't do better than just predicting always-taken on
         // indirect jumps, unless we examine return address stack.
         // Just assume always-taken.
         branch_outcome = 1; // !jump_miss;
         incr_num_branch = 1;
      end
      else begin
         update_bht = 0;
         pc_outcome = pc_ex; // doesn't matter
         branch_outcome = 1;
         incr_num_branch = 0;
      end

      // Cancel all this if this EX stage had been stalled.
      if (freeze_ex) begin
         update_bht = 0;
         incr_num_branch = 0;
      end
   end

   // MEM stage
   assign d_read = d_mem_read_mem;
   assign d_write = d_mem_write_mem;
   assign d_address = alu_out_mem;
   assign d_data = d_mem_write_mem ? b_mem : {WORD_SIZE{1'bz}};

   // WB stage
   assign addr3 = write_reg_wb;
   assign writeData = (reg_write_src_wb == `REGWRITESRC_IMM) ? imm_signed_wb : // LHI
                      (reg_write_src_wb == `REGWRITESRC_ALU) ? alu_out_wb :
                      (reg_write_src_wb == `REGWRITESRC_MEM) ? MDR_wb :
                      /*(reg_write_src_wb == `REGWRITESRC_PC) ?*/ (pc_wb + 1); // JAL, JRL

   //-------------------------------------------------------------------------//
   // Register transfers
   //-------------------------------------------------------------------------//

   always @(posedge clk) begin
      if (!reset_n) begin
         // reset all pipeline registers and control signal registers
         // to zero to prevent any initial output
         pc <= 0; pc_id <= 0; pc_ex <= 0; pc_mem <= 0; pc_wb <= 0;
         pc_buffer <= {WORD_SIZE{1'b1}};
         num_inst_if_saved <= {WORD_SIZE{1'b1}};
         num_inst_if_saved_buffer <= {WORD_SIZE{1'b1}};
         npc_id <= 0;
         npc_ex <= 0;
         npc_mem <= 0;
         npc_wb <= 0;
         halt_ex <= 0; halt_mem <= 0; halt_wb <= 0;
         cond_branch_target_ex <= 0;
         tag_match_id <= 0;
         MDR_wb <= 0;
         a_ex <= 0;
         b_ex <= 0;
         b_mem <= 0;
         alu_out_mem <= 0; alu_out_wb <= 0;
         alu_src_a_ex <= 0; alu_src_b_ex <= 0;
         alu_src_swap_ex <= 0;
         output_write_ex <= 0;
         d_mem_write_ex <= 0; d_mem_write_mem <= 0; d_mem_write_wb <= 0;
         write_reg_ex <= 0; write_reg_mem <= 0; write_reg_wb <= 0;
         reg_write_ex <= 0; reg_write_mem <= 0; reg_write_wb <= 0;
         reg_write_src_ex <= 0; reg_write_src_mem <= 0; reg_write_src_wb <= 0;
         interrupted <= 0;
         bus_granted <= 0;
         output_port <= {WORD_SIZE{1'bz}}; // initially float
         num_inst_if <= 0;
         num_inst_id <= 0;
         num_inst_ex <= 0;
         num_branch <= 0;
         num_branch_miss <= 0;
      end
      else begin
         //-------------------------------------------------------------------//
         // PC resolution
         //-------------------------------------------------------------------//

         // Should be careful about the case where conditional
         // branch and jump is resolved at the same time.
         //
         // Since branch is resolved in EX and jump in ID, the
         // branch is always older than jump, which means the jump
         // in ID could be a 'false' one that will be flushed if
         // the branch is revealed to be missed.  So handle
         // conditional branch miss first.
         if (cond_branch_miss) begin
            if (pc_write) begin
               pc <= resolved_pc;
               // Restore num_inst_if back to what it was.
               num_inst_if <= num_inst_if_saved;
               // Debug info: update branch miss count.
               num_branch_miss <= num_branch_miss + 1;
            end
            else begin
               pc_buffer <= resolved_pc;
               num_inst_if_saved_buffer <= num_inst_if_saved;
            end
         end
         // fall through on branch hit, jump or non-branch
         else if (jump_miss) begin
            // We are now sure that this jump is not going to be
            // flushed, and therefore that this is a valid jump
            // miss.  Update num_branch_miss here as well.

            if (opcode == `OPCODE_JMP || opcode == `OPCODE_JAL) begin
               if (pc_write)
                 pc <= jump_target;
               else
                 pc_buffer <= jump_target;
            end
            else if (opcode == `OPCODE_RTYPE) begin
               case (func_code)
                 `FUNC_JPR, `FUNC_JRL: begin
                    if (pc_write)
                      pc <= data1;
                    else
                      pc_buffer <= data1;
                 end
               endcase
            end

            if (pc_write) begin
               // Debug info: update branch miss count.
               num_branch_miss <= num_branch_miss + 1;
            end
         end
         // fall through on branch hit or non-branch
         else begin
            if (pc_write)
              pc <= npc;
         end

         //-------------------------------------------------------------------//
         // Pipeline stage latches
         //-------------------------------------------------------------------//

         // IF stage
         //
         // For ir_write = 0, the ID stage is stalled and every IF/ID latches
         // including IR, pc_id and npc_id should be preserved as is.
         if (ir_write) begin
            npc_id <= npc; // adder for PC
            pc_id <= pc; // for debugging purpose
         end
         // save BTB tag match result
         tag_match_id <= tag_match;
         // For branch, save num_inst_if so that it can be restored in case of
         // pipeline flush due to branch prediction miss.
         if (inst_type == `INSTTYPE_BRANCH)
           num_inst_if_saved <= num_inst_if;

         // ID stage
         if (!freeze_ex) begin
            npc_ex <= npc_id;
            pc_ex <= pc_id;
            cond_branch_target_ex <= cond_branch_target;
            num_inst_ex <= num_inst_id;
            inst_type_ex <= inst_type;
            rs_ex <= rs;
            rt_ex <= rt;
            rd_ex <= rd;
            a_ex <= data1;
            b_ex <= data2;
            write_reg_ex <= (reg_dst == `REGDST_RT) ? rt :
                            (reg_dst == `REGDST_RD) ? rd :
                            /*(reg_dst == `REGDST_2) ?*/ 2'd2;
            imm_signed_ex <= imm_signed;
            output_write_ex <= output_write;
         end

         // EX stage
         if (!freeze_mem) begin
            npc_mem <= npc_ex;
            pc_mem <= pc_ex;
            inst_type_mem <= inst_type_ex;
            rs_mem <= rs_ex;
            rt_mem <= rt_ex;
            b_mem <= b_ex;
            alu_out_mem <= alu_result;
            write_reg_mem <= write_reg_ex;
            imm_signed_mem <= imm_signed_ex;
         end

         // MEM stage
         //
         // HACK: while stalling MEM, stall WB as well to keep WB-forwarded data
         // from changing -- see hazard_unit.v
         if (!freeze_mem) begin
            npc_wb <= npc_mem;
            pc_wb <= pc_mem;
            inst_type_wb <= inst_type_mem;
            rs_wb <= rs_mem;
            rt_wb <= rt_mem;
            alu_out_wb <= alu_out_mem;
            MDR_wb <= d_data;
            write_reg_wb <= write_reg_mem;
            imm_signed_wb <= imm_signed_mem;
         end

         //-------------------------------------------------------------------//
         // Control signal latches
         //-------------------------------------------------------------------//

         // ID stage (EX+MEM+WB)
         // if hazard detected, insert bubbles into pipeline
         if (!freeze_ex) begin
            halt_ex          <= bubblify_id ? 0 : halt_id;
            branch_ex        <= bubblify_id ? 0 : branch;
            alu_op_ex        <= bubblify_id ? 0 : alu_op;
            alu_src_a_ex     <= bubblify_id ? 0 : alu_src_a;
            alu_src_b_ex     <= bubblify_id ? 0 : alu_src_b;
            alu_src_swap_ex  <= bubblify_id ? 0 : alu_src_swap;
            i_mem_read_ex    <= bubblify_id ? 0 : i_mem_read;
            d_mem_read_ex    <= bubblify_id ? 0 : d_mem_read;
            i_mem_write_ex   <= bubblify_id ? 0 : i_mem_write;
            d_mem_write_ex   <= bubblify_id ? 0 : d_mem_write;
            reg_write_ex     <= bubblify_id ? 0 : reg_write;
            reg_write_src_ex <= bubblify_id ? 0 : reg_write_src;
         end

         // EX stage (MEM+WB)
         if (!freeze_mem) begin
            halt_mem          <= bubblify_ex ? 0 : halt_ex;
            i_mem_read_mem    <= bubblify_ex ? 0 : i_mem_read_ex;
            d_mem_read_mem    <= bubblify_ex ? 0 : d_mem_read_ex;
            i_mem_write_mem   <= bubblify_ex ? 0 : i_mem_write_ex;
            d_mem_write_mem   <= bubblify_ex ? 0 : d_mem_write_ex;
            reg_write_mem     <= bubblify_ex ? 0 : reg_write_ex;
            reg_write_src_mem <= bubblify_ex ? 0 : reg_write_src_ex;
         end

         // MEM stage (WB)
         d_mem_write_wb   <= bubblify_mem ? 0 : d_mem_write_mem; // FIXME
         if (!freeze_mem) begin
            halt_wb          <= bubblify_mem ? 0 : halt_mem;
            reg_write_wb     <= bubblify_mem ? 0 : reg_write_mem;
            reg_write_src_wb <= bubblify_mem ? 0 : reg_write_src_mem;
         end

         //-------------------------------------------------------------------//
         // I/O
         //-------------------------------------------------------------------//

         // DMA interrupt
         if (dma_begin) begin
            interrupted <= 1;
            // Fixed address and length
            dma_cmd[2*WORD_SIZE-1:WORD_SIZE] <= {WORD_SIZE{16'h1F4}};
            dma_cmd[WORD_SIZE-1:0] <= {WORD_SIZE{16'd12}};
         end
         else begin
            interrupted <= 0;
            dma_cmd <= 0;
         end

         // Bus grant
         //
         // If a device interrupts CPU when the cache is doing a memory operation,
         // it should finish the memory read/write and then grant the bus to the
         // DMA controller.  Otherwise, as the DMA controller blocks the data bus
         // under BG, the CPU would be stuck in that unfinished memory operation.
         if (bus_request && !d_cache_busy) begin
            bus_granted <= 1;
         end
         // // Bus reclaim
         // //
         // // If the DMA does not request for bus anymore, reclaim it as fast as
         // // possible.

         // if (!bus_request) begin
         //    bus_granted <= 0;
         // end

         //-------------------------------------------------------------------//
         // Debug info
         //-------------------------------------------------------------------//

         // output port assertion
         if (output_write_ex == 1) begin
            // WWD can also benefit from forwarding
            output_port <= a_forwarded;
         end

         // num_inst update
         //
         // increased num_inst_if will propagate into the pipeline,
         // setting the right value for each stage
         if (incr_num_inst) begin
            num_inst_if <= num_inst_if + 1;
            num_inst_id <= num_inst_if;
         end

         // num_branch update
         // num_branch_miss is updated above
         if (incr_num_branch)
           num_branch <= num_branch + 1;

         // if (pc_write) begin
         //    if (pc_buffer != {WORD_SIZE{1'b1}}) begin
         //       pc <= pc_buffer;
         //       pc_buffer <= {WORD_SIZE{1'b1}};
         //    end
         //    if (num_inst_if_saved_buffer != {WORD_SIZE{1'b1}}) begin
         //       num_inst_if <= num_inst_if_saved_buffer;
         //       num_inst_if_saved_buffer <= {WORD_SIZE{1'b1}};
         //    end
         // end
      end
   end // always @ (posedge clk)

   always @(negedge bus_request) begin
      if (!bus_request) begin
         bus_granted <= 0;
      end
   end
endmodule
