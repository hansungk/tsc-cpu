// Decodes instruction into 6 types (R-type, Load, Store, Branch,
// Jump, Output, Nop)

`include "constants.v"

module InstTypeDecoder(
   input [3:0]      opcode,
   input [5:0]      func_code,
   output reg [2:0] inst_type
);
   always @(*) begin
      case (opcode)
        `OPCODE_RTYPE,`OPCODE_ADI, `OPCODE_ORI: begin
           case (func_code)
             `FUNC_JPR: inst_type = `INSTTYPE_JUMP;
             `FUNC_JRL: inst_type = `INSTTYPE_JUMP;
             `FUNC_WWD: inst_type = `INSTTYPE_OUTPUT;
             6'b111111:  inst_type = `INSTTYPE_NOP; // all 1 is reserved for nop
             default: inst_type = `INSTTYPE_RTYPE;
           endcase
        end
        `OPCODE_LHI, `OPCODE_LWD: begin
           inst_type = `INSTTYPE_LOAD;
        end
        `OPCODE_SWD: begin
           inst_type = `INSTTYPE_STORE;
        end
        `OPCODE_BNE, `OPCODE_BEQ, `OPCODE_BGZ, `OPCODE_BLZ: begin
           inst_type = `INSTTYPE_BRANCH;
        end
        `OPCODE_JMP, `OPCODE_JAL: begin
           inst_type = `INSTTYPE_JUMP;
        end
        default: begin
           inst_type = `INSTTYPE_NOP;
        end
      endcase
   end
endmodule
