`timescale 1ns/1ns

`include "constants.v"

module hazard_unit(
   input [2:0] inst_type, // decoded in the control unit
   input       valid_ex,
   output reg  bubblify,
   output reg  flush,
   output reg  pc_write,
   output reg  ir_write,
   output reg  incr_num_inst 
);
   always @* begin
      // defaults
      pc_write = 1;
      ir_write = 1;
      incr_num_inst = 1;
      bubblify = 0;
      flush = 0;

      case (inst_type)
        `INSTTYPE_JUMP: begin
           // @JUMP + 1 has been fetched, flush it
           incr_num_inst = 0;
           flush = 1;
        end
      endcase
   end
endmodule // hazard_unit
