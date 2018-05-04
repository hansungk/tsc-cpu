`timescale 1ns / 1ns
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2018/04/06 13:15:45
// Design Name: 
// Module Name: control_unit
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

`define MPC_IF 4'd0
`define MPC_ID 4'd1
`define MPC_EX 4'd2
`define MPC_MEM 4'd3
`define MPC_WB 4'd4

module control_unit(
    input                       clk,
    input                       reset_n,
    input [3:0]                 opcode,
    input [5:0]                 func_code,
    output [2:0]                inst_type,
    output reg                  valid, // not bubble?
    output reg                  pc_write, // update pc
    output reg                  pc_write_cond, // update pc if branch taken
    output reg [1:0]            pc_src, // 0: PC+4, 1: jump, 2: branch, 3: reg (JPR)
    output reg                  i_or_d, // memory address from 0: PC, 1: alu_out
    output reg                  i_mem_read, // command memory read 
    output reg                  d_mem_read, // command memory read 
    output reg                  i_mem_write, // command memory write
    output reg                  d_mem_write, // command memory write
    output reg                  ir_write, // latch instruction memory
    output [3:0]                alu_op,
    output reg                  alu_src_a, // 0: PC, 1: A_ex
    output reg [1:0]            alu_src_b, // 0: 1 (sequential / branch untaken),
                                           // 1: B_ex,
                                           // 2: sign-extended immediate,
                                           // 3: 0 (for TCP & BGZ & BLZ)
    output reg                  alu_src_swap, // swap ALU input after
                                              // alu_src_a and alu_src_b
                                              // (for TCP)
    output reg                  reg_write, // write to register
    output reg [1:0]            reg_write_src, // register write data comes from
                                               // 0: imm (LHI),
                                               // 1: alu_out,
                                               // 2: MDR,
                                               // 3: PC (JAL)
    output reg [1:0]            reg_dst, // write to 0: rt, 1: rd, 2: $2 (JAL)
    output reg                  output_write, // write to output port
    output reg [`WORD_SIZE-1:0] num_inst,
    output                      is_halted
);

   // indicates whether to update num_inst
   // whenever microprogram control flow jumps to IF, this should be asserted.
   reg complete;

   reg ALUMode; // 0: address calculation, 1: opcode-specific arithmetics

   // Instruction type: R-Type / I-Type / Load / Store / Branch / Jump
   reg [2:0] inst_type;

   wire      isTCP;
   wire      isHLT;
   assign isTCP = (opcode == `OPCODE_RTYPE && func_code == `FUNC_TCP);
   assign isHLT = (opcode == `OPCODE_RTYPE && func_code == `FUNC_HLT);
   assign is_halted = isHLT;

   // ALU control logic. See alu_control.v
   alu_control ALUControl(.opcode(opcode), .func_code(func_code),
                          .ALUMode(ALUMode), .alu_op(alu_op));

   always @* begin
      // classify instructions into 5 types
      case (opcode)
        `OPCODE_RTYPE,`OPCODE_ADI, `OPCODE_ORI: begin
           case (func_code)
             `FUNC_JPR: inst_type = `INSTTYPE_JUMP;
             `FUNC_JRL: inst_type = `INSTTYPE_JUMP;
             `FUNC_WWD: inst_type = `INSTTYPE_OUTPUT;
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
           inst_type = `INSTTYPE_RTYPE;
        end
      endcase
   end

   always @(*) begin
      // FIXME Comment here

      // defaults
      valid = 0;
      i_or_d = 0;
      i_mem_read = 0;
      d_mem_read = 0;
      i_mem_write = 0;
      d_mem_write = 0;
      ir_write = 1;
      pc_write = 1;
      pc_write_cond = 0;
      pc_src = `PCSRC_SEQ;
      reg_dst = `REGDST_RD;
      reg_write = 0; // prevent write at stages other than WB
      ALUMode = 0;
      alu_src_swap = 0;
      output_write = 0;
      complete = 0;

      // fetch inst from memory and latch it
      i_mem_read = 1;

      // Instruction-specific control logic
      //
      // Dispatch by instruction type first rather than by stage,
      // because there are stage-independent control signals
      // (e.g. reg_write_src, reg_dst)
      case (inst_type)
        `INSTTYPE_RTYPE: begin
           pc_write = 1;

           reg_write_src = `REGWRITESRC_REG;
           reg_dst = (opcode == `OPCODE_ADI || opcode == `OPCODE_ORI) ? `REGDST_RT : `REGDST_RD;

           // switch to arithmetic mode from address calc mode
           ALUMode = 1;

           // TCP is calculated as 0 - A, which requires feeding
           // zero to SrcA and A to SrcB
           // ADI and ORI are treated as R-Type and also needs
           // special treatment here
           alu_src_swap = isTCP;
           alu_src_a = `ALUSRCA_REG;
           alu_src_b = (opcode == `OPCODE_ADI || opcode == `OPCODE_ORI) ?
                       `ALUSRCB_IMM : // A - imm
                       (isTCP ?
                        `ALUSRCB_ZERO : // 0 - A (with swap)
                        `ALUSRCB_REG); // A - B
        end
        `INSTTYPE_LOAD: begin
           reg_write_src = (opcode == `OPCODE_LHI) ? `REGWRITESRC_IMM : `REGWRITESRC_MEM;
           reg_dst = `REGDST_RT;

           // calculate memory read address
           alu_src_a = `ALUSRCA_REG;
           alu_src_b = `ALUSRCB_IMM;

           // read from data memory
           i_or_d = 1;
           d_mem_read = 1;
        end
        `INSTTYPE_STORE: begin
           // calculate memory write address
           alu_src_a = `ALUSRCA_REG;
           alu_src_b = `ALUSRCB_IMM;

           // write to data memory
           i_or_d = 1;
           d_mem_write = 1;
        end
        `INSTTYPE_BRANCH: begin
           complete = 1;

           // compute branch outcome
           ALUMode = 1;
           alu_src_a = `ALUSRCA_REG;
           alu_src_b = (opcode == `OPCODE_BGZ || opcode == `OPCODE_BLZ) ?
                       `ALUSRCB_ZERO :
                       `ALUSRCB_REG;
           alu_src_swap = opcode == `OPCODE_BLZ;

           pc_src = `PCSRC_BRANCH;
           pc_write_cond = 1;
        end
        `INSTTYPE_JUMP: begin
           complete = 1;
           pc_src = `PCSRC_JUMP;

           // write PC to $2 for JAL
           if (opcode == `OPCODE_JAL) begin
              reg_dst = `REGDST_2;
              reg_write_src = `REGWRITESRC_PC;
              reg_write = 1;
           end
           // write $rs to PC for JPR
           else if (opcode == `OPCODE_RTYPE && func_code == `FUNC_JPR) begin
              pc_src = `PCSRC_REG;
              pc_write = 1;
           end
           // do both for JRL
           else if (opcode == `OPCODE_RTYPE && func_code == `FUNC_JRL) begin
              reg_dst = `REGDST_2;
              reg_write_src = `REGWRITESRC_PC;
              reg_write = 1;

              pc_src = `PCSRC_REG;
              pc_write = 1;
           end
           // end
        end
        `INSTTYPE_OUTPUT: begin
           complete = 1;
           output_write = 1;
        end
        default: begin // flush (0x0000), wrong opcode, etc.
           pc_write = 0;
        end
      endcase // case (inst_type)
   end // always @ (*)

   // Microprogram state update
   always @(posedge clk) begin
      if (reset_n == 0) begin
         num_inst <= 0;
      end
      else begin
         if (complete)
           num_inst <= num_inst + 1;
      end
   end
endmodule
