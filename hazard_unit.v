`timescale 1ns/1ns

`include "constants.v"

module hazard_unit(
   input [3:0] opcode,
   input [2:0] inst_type,
   input [5:0] func_code, 
   input       branch_ex, // used for stall-based resolution
   input       branch_miss, // used for branch prediction 
   input [1:0] rs_id, 
   input [1:0] rt_id, 
   input       reg_write_ex,
   input       reg_write_mem,
   input       reg_write_wb,
   input [1:0] write_reg_ex, 
   input [1:0] write_reg_mem, 
   input [1:0] write_reg_wb, 
   input       d_mem_read_ex,
   input       d_mem_read_mem,
   input       d_mem_read_wb,
   input [1:0] rt_ex, 
   input [1:0] rt_mem, 
   input [1:0] rt_wb, 
   output reg  bubblify, // reset all control signals to zero
   output reg  flush_if, // reset IR to nop
   output reg  pc_write,
   output reg  ir_write,
   output reg  incr_num_inst 
);
   parameter RF_SELF_FORWARDING = 1;
   parameter DATA_FORWARDING = 1;
   parameter PREDICT_ALWAYS_UNTAKEN = 1;

   reg         use_rs, use_rs_at_id, use_rt;

   always @* begin
      // defaults
      pc_write = 1;
      ir_write = 1;
      bubblify = 0;
      flush_if = 0;

      //----------------------------------------------------------------------//
      // Data hazard handling
      //
      // This takes precedence over control hazard handling, because data
      // dependence of the branch instructions must be handled first before
      // doing any stall/branch prediction (e.g. data dependence on equality
      // check register for BEQ, jump target register for JPR/JAL, etc).
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

      // Bypass unnecessary WB check by prefixing !RF_SELF_FORWARDING.
      if (!DATA_FORWARDING &&
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
          ((use_rs || use_rt) && d_mem_read_ex && (rs_id == rt_ex || rt_id == rt_ex)) ||
          (!DATA_FORWARDING && (use_rs || use_rt) && d_mem_read_mem && (rs_id == rt_mem || rt_id == rt_mem)) ||
          (!RF_SELF_FORWARDING && (use_rs || use_rt) && d_mem_read_wb && (rs_id == rt_wb || rt_id == rt_wb))) begin
         // stall ID
         pc_write = 0;
         ir_write = 0;
         bubblify = 1;
      end
      else begin
         //-------------------------------------------------------------------//
         // Control hazard handling
         //-------------------------------------------------------------------//

         if (inst_type == `INSTTYPE_JUMP) begin
            // PC + 1 has been fetched, flush it ("branch miss")
            flush_if = 1;
         end

         // branch_miss is always 1 on no prediction, so this becomes
         // unconditional stall-on-branch.
         if (branch_miss) begin
            // On branch miss, flush IF and bubblify ID, effectively erasing two
            // instructions.
            bubblify = 1;
            flush_if = 1;
         end
      end

      // don't increase num_inst in any kind of hazard
      incr_num_inst = !(bubblify || flush_if);
   end
endmodule // hazard_unit
