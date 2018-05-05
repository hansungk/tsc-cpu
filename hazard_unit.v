`timescale 1ns/1ns

`include "constants.v"

module hazard_unit(
   input [3:0] opcode,
   input [2:0] inst_type,
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
   output reg  bubblify,
   output reg  flush,
   output reg  pc_write,
   output reg  ir_write,
   output reg  incr_num_inst 
);
   reg         use_rs, use_rt;

   always @* begin
      // defaults
      pc_write = 1;
      ir_write = 1;
      incr_num_inst = 1;
      bubblify = 0;
      flush = 0;

      // Flush determination
      case (inst_type)
        `INSTTYPE_JUMP: begin
           // Stall-based control hazard resolution: stall 1 cycle
           // after branch

           // @JUMP + 1 has been fetched, flush it
           incr_num_inst = 0;
           flush = 1;
        end
      endcase

      // Stall determination
      use_rs = inst_type == `INSTTYPE_RTYPE ||
               (inst_type == `INSTTYPE_LOAD && opcode != `OPCODE_LHI) || // LHI only uses rt
               inst_type == `INSTTYPE_STORE ||
               inst_type == `INSTTYPE_BRANCH ||
               inst_type == `INSTTYPE_OUTPUT;
      use_rt = (inst_type == `INSTTYPE_RTYPE && opcode != `OPCODE_ADI)|| // ADI only uses rs
               inst_type == `INSTTYPE_LOAD ||
               inst_type == `INSTTYPE_STORE ||
               inst_type == `INSTTYPE_BRANCH;
      if ((use_rs && reg_write_ex  && rs_id == write_reg_ex) ||
          (use_rs && reg_write_mem && rs_id == write_reg_mem) ||
          (use_rs && reg_write_wb  && rs_id == write_reg_wb) ||
          (use_rt && reg_write_ex  && rt_id == write_reg_ex) ||
          (use_rt && reg_write_mem && rt_id == write_reg_mem) ||
          (use_rt && reg_write_wb  && rt_id == write_reg_wb) ||
          // stall for LOAD
          ((use_rs || use_rt) && d_mem_read_ex && (rs_id == rt_ex || rt_id == rt_ex)) ||
          ((use_rs || use_rt) && d_mem_read_mem && (rs_id == rt_mem || rt_id == rt_mem)) ||
          ((use_rs || use_rt) && d_mem_read_wb && (rs_id == rt_wb || rt_id == rt_wb))) begin
         pc_write = 0;
         ir_write = 0;
         incr_num_inst = 0;
         bubblify = 1;
      end
      
   end
endmodule // hazard_unit
