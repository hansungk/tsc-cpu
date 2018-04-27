// Author: 2014-16824 Hansung Kim
// Date: 2018-04-21

`include "constants.v"
`include "opcodes.v"

// Module that controls ALU operation using opcode and func code
// decoded from the instruction.
module alu_control(
   input [3:0] 		opcode,
   input [5:0] 		func_code,
   input 			ALUMode, // 0: address calculation (add),
				             // 1: opcode-specific arithmetic
   output reg [3:0] alu_op
);
   always @(*) begin
	  // override alu_op translation with address calculation (ADD)
	  if (ALUMode == 0) begin
		 alu_op = `OP_ADD;
	  end
	  else begin
		 case (opcode)
		   `OPCODE_RTYPE: begin
			  case (func_code)
				`FUNC_ADD: alu_op = `OP_ADD;
				`FUNC_SUB: alu_op = `OP_SUB;
				`FUNC_AND: alu_op = `OP_AND;
				`FUNC_ORR: alu_op = `OP_OR;
				`FUNC_NOT: alu_op = `OP_NOT;
				`FUNC_SHL: alu_op = `OP_ALS;
				`FUNC_SHR: alu_op = `OP_ARS;
				`FUNC_SUB: alu_op = `OP_SUB;
				`FUNC_TCP: alu_op = `OP_SUB;
				default: alu_op = `OP_ADD;
			  endcase
		   end // case: `OPCODE_RTYPE
		   `OPCODE_ADI: alu_op = `OP_ADD;
		   `OPCODE_ORI: alu_op = `OP_OR;
		   // branch
		   `OPCODE_BNE: alu_op = `OP_NE;
		   `OPCODE_BEQ: alu_op = `OP_EQ;
		   `OPCODE_BGZ: alu_op = `OP_GT;
		   `OPCODE_BLZ: alu_op = `OP_GT;

		   // for all others, ALU is used for address calculation (add)
		   default: alu_op = `OP_ADD;
		 endcase
	  end
   end
endmodule // alu_control
