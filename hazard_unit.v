`timescale 1ns/1ns

`include "constants.v"
`include "opcodes.v"

module hazard_unit
  #(parameter RF_SELF_FORWARDING = 1,
    parameter DATA_FORWARDING = 1)
   (input                  clk,
    input                  reset_n,
    input [3:0]            opcode,
    input [2:0]            inst_type,
    input [5:0]            func_code,
    input                  jump_miss, // misprediction for unconditional branch
    input                  branch_miss, // used for branch prediction 
    input [1:0]            rs_id, 
    input [1:0]            rt_id, 
    input                  reg_write_ex,
    input                  reg_write_mem,
    input                  reg_write_wb,
    input [1:0]            write_reg_ex, 
    input [1:0]            write_reg_mem, 
    input [1:0]            write_reg_wb, 
    input                  d_mem_read_ex,
    input                  d_mem_read_mem,
    input                  d_mem_read_wb,
    input                  d_mem_write_mem,
    input                  d_mem_write_wb,
    input                  i_ready,
    input                  i_input_ready,
    input                  d_ready,
    input [`WORD_SIZE-1:0] d_written_address,
    input [1:0]            rt_ex, 
    input [1:0]            rt_mem,
    input [1:0]            rt_wb,
    output reg             i_mem_read,
    output reg             bubblify_id, // reset all control signals of ID to zero
    output reg             bubblify_ex, // reset all control signals of EX to zero
    output reg             bubblify_mem, // reset all control signals of MEM to zero
    output reg             flush_if, // reset IR to nop
    output reg             pc_write,
    output reg             ir_write,
    output reg             freeze_ex,
    output reg             freeze_mem,
    output reg             incr_num_inst 
);
   reg          use_rs, use_rs_at_id, use_rt;

   always @* begin
      // defaults
      pc_write = 1;
      ir_write = 1;
      freeze_ex = 0;
      freeze_mem = 0;
      bubblify_id = 0;
      bubblify_ex = 0;
      bubblify_mem = 0;
      flush_if = 0;

      //----------------------------------------------------------------------//
      // Data hazard handling
      //
      // Data hazard handling takes precedence over control hazard handling,
      // because data dependence of the branch instructions must be handled
      // first before doing any stall or branch prediction (e.g. data dependence
      // of the operand register for BEQ, jump target register for JPR/JAL,
      // etc).
      // ----------------------------------------------------------------------//

      use_rs_at_id = (opcode == `OPCODE_RTYPE && (func_code == `FUNC_JPR || func_code == `FUNC_JRL)); // JPR and JRL uses rs at ID
      use_rs = inst_type == `INSTTYPE_RTYPE ||
               (inst_type == `INSTTYPE_LOAD && opcode != `OPCODE_LHI) || // LHI only uses rt
               inst_type == `INSTTYPE_STORE ||
               use_rs_at_id ||
               inst_type == `INSTTYPE_BRANCH ||
               inst_type == `INSTTYPE_OUTPUT;
      use_rt = (inst_type == `INSTTYPE_RTYPE && opcode != `OPCODE_ADI)|| // ADI only uses rs
               inst_type == `INSTTYPE_LOAD ||
               inst_type == `INSTTYPE_STORE ||
               inst_type == `INSTTYPE_BRANCH;

      // MEM stage load stall.
      //
      // Memory load should always stall if the operation is not finished within
      // its cycle.  This is because a load has self-dependency -- the writeback
      // stage always requires the loaded data to finish.  After the load is
      // finished, any access to this data becomes RAW on the writeback
      // register, which is handled by forwarding (or stall condition check from
      // the ID).
      if ((d_mem_read_mem || d_mem_write_mem) && (!d_ready /*|| d_mem_write_wb*/)) begin
         pc_write = 0;
         ir_write = 0;
         freeze_ex = 1;
         freeze_mem = 1;
         bubblify_mem = 1;
      end
      // ID stall.
      //
      // Bypass unnecessary stall checks by ANDing with the forwarding flags.
      else if (!DATA_FORWARDING &&
          ((                       use_rs && reg_write_ex  && rs_id == write_reg_ex) ||
           (                       use_rs && reg_write_mem && rs_id == write_reg_mem) ||
           (!RF_SELF_FORWARDING && use_rs && reg_write_wb  && rs_id == write_reg_wb) ||
           (use_rt && reg_write_ex  && rt_id == write_reg_ex) ||
           (use_rt && reg_write_mem && rt_id == write_reg_mem) ||
           (!RF_SELF_FORWARDING && use_rt && reg_write_wb  && rt_id == write_reg_wb))
          ||
          // produce-JUMP stall check (JPR, JRL)
          ((                       use_rs_at_id && reg_write_ex  && rs_id == write_reg_ex) ||
           (                       use_rs_at_id && reg_write_mem && rs_id == write_reg_mem) ||
           (!RF_SELF_FORWARDING && use_rs_at_id && reg_write_wb  && rs_id == write_reg_wb))
          ||
          // Load-use stall check
          //
          // Although data is forwarded to EX, this should be at ID stage
          // because that's where the instruction can get its operand info.
          ((use_rs || use_rt) && d_mem_read_ex && (rs_id == rt_ex || rt_id == rt_ex)) ||
          (!DATA_FORWARDING && (use_rs || use_rt) && d_mem_read_mem && (rs_id == rt_mem || rt_id == rt_mem)) ||
          (!RF_SELF_FORWARDING && (use_rs || use_rt) && d_mem_read_wb && (rs_id == rt_wb || rt_id == rt_wb))) begin
         // stall ID
         pc_write = 0;
         ir_write = 0;
         bubblify_id = 1;
      end
      else begin
         //-------------------------------------------------------------------//
         // Control hazard handling
         //-------------------------------------------------------------------//

         // jump_miss is always 1 on no prediction, so this becomes
         // unconditional stall-on-branch.
         if (jump_miss) begin
            // PC + 1 has been fetched, flush it ("branch miss")
            flush_if = 1;
         end

         // branch_miss is always 1 on no prediction, so this becomes
         // unconditional stall-on-branch.
         if (branch_miss) begin
            // On branch miss, flush IF and bubblify ID, effectively erasing two
            // instructions.
            bubblify_id = 1;
            flush_if = 1;
         end
      end

      // IF stall.
      //
      // This happens because of the I-Cache miss.
      i_mem_read = 1;

      // if (i_readyM && (branch_miss || jump_miss)) begin
      //    i_mem_read = 0;
      // end

      if (!i_ready && (stall < 2))
        i_mem_read = 0;

      if (ir_write && !i_ready) begin
         pc_write = 0;
         if (jump_miss || branch_miss)
           pc_write = 1;
         flush_if = 1;
         // pc_write = 0;
         // ir_write = 0;
         // flush_if = 0;
         // freeze_ex = 1;
         // freeze_mem = 1;
         // bubblify_mem = 1;
      end

      // don't increase num_inst in any kind of hazard
      incr_num_inst = !(bubblify_id || bubblify_mem || !pc_write || flush_if);
   end // always @ *

   reg [3:0] stall;

   always @(posedge clk) begin
      if (!reset_n) begin
         stall <= 0;
      end
      else begin
         if (!i_ready && !(branch_miss || jump_miss)) begin
            stall <= stall + 1;
         end
         else
           stall <= 0;

         if (!i_ready && stall)
           i_mem_read <= 1;
      end
   end
endmodule // hazard_unit
