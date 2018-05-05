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
`define WORD_SIZE 16

module datapath
  #(parameter WORD_SIZE = `WORD_SIZE)
   (input                      clk,
    input                      reset_n,
    input [1:0]                pc_src,
    input                      i_or_d,

    // See control_unit.v for docs for each control signals

    // ID control signals
    input                      output_write,

    // EX control signals
    input [3:0]                alu_op,
    input                      alu_src_a,
    input [1:0]                alu_src_b,
    input                      alu_src_swap, 
    input [1:0]                reg_dst,
    input                      branch,

    // MEM control signals
    input                      i_mem_read, 
    input                      d_mem_read, 
    input                      i_mem_write,
    input                      d_mem_write, 

    // WB control signals
    input                      reg_write,
    input [1:0]                reg_write_src,
    input                      halt_id,

    input                      input_ready,
    output reg                 valid_ex,
    output [WORD_SIZE-1:0]     i_address,
    output [WORD_SIZE-1:0]     d_address,
    output                     i_readM,
    output                     d_readM,
    output                     i_writeM,
    output                     d_writeM,
    inout [WORD_SIZE-1:0]      i_data,
    inout [WORD_SIZE-1:0]      d_data,
    output reg [WORD_SIZE-1:0] output_port,
    output [3:0]               opcode,
    output [5:0]               func_code,
    output [2:0]               inst_type,
    output                     is_halted, 
    output [WORD_SIZE-1:0]     num_inst
);

   parameter RF_SELF_FORWARDING = 1;

   //-------------------------------------------------------------------------//
   // Wires
   //-------------------------------------------------------------------------//

   // Decoded info
   wire [1:0]           rs, rt, rd;
   wire [7:0]           imm;
   wire [11:0]          target_addr;

   // Hazard signals
   wire                 pc_write, pc_write_cond;
   wire                 ir_write;
   wire                 bubblify; // reset all control signals to zero
   wire                 flush_if; // reset IR to nop
   wire                 branch_miss;
   wire                 incr_num_inst; // increase num_inst when it becomes positive that the
                                       // fetched instruction will not be discarded
   wire [WORD_SIZE-1:0] resolved_pc; // PC resolved as either branch target or PC+1

   // register file
   wire [1:0]           addr1, addr2, addr3;
   wire [WORD_SIZE-1:0] data1, data2, writeData;

   // ALU
   wire [WORD_SIZE-1:0] alu_temp_1, alu_temp_2; // operands before swap
   wire [WORD_SIZE-1:0] alu_operand_1, alu_operand_2; // operands after swap
   wire [WORD_SIZE-1:0] alu_result;

   //-------------------------------------------------------------------------//
   // Pipeline registers
   //-------------------------------------------------------------------------//
   // don't forget to reset

   // unconditional latches
   reg [WORD_SIZE-1:0]  pc, pc_id, pc_ex, pc_mem, pc_wb; // program counter
   reg [WORD_SIZE-1:0]  npc, npc_id, npc_ex, npc_mem, npc_wb; // PC + 4 saved for branch resolution and JAL writeback
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
   assign num_inst = num_inst_ex; // num_inst is the inst passing through EX right now

   // control signal latches
   reg                  valid_mem, valid_wb; // valid_ex already declared
   reg                  branch_ex; // branch instruction in EX?
   reg [3:0]            alu_op_ex;
   reg                  alu_src_a_ex;
   reg [1:0]            alu_src_b_ex;
   reg                  alu_src_swap_ex;
   reg                  i_mem_read_ex, i_mem_read_mem;
   reg                  d_mem_read_ex, d_mem_read_mem;
   reg                  i_mem_write_ex, i_mem_write_mem;
   reg                  d_mem_write_ex, d_mem_write_mem;
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

   // Hazard detection unit
   hazard_unit #(.RF_SELF_FORWARDING(RF_SELF_FORWARDING))
   HU (.opcode(opcode),
       .inst_type(inst_type),
       .func_code(func_code),
       .branch_ex(branch_ex),
       .branch_miss(branch_miss),
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
       .rt_ex(rt_ex),
       .rt_mem(rt_mem),
       .rt_wb(rt_wb),
       .bubblify(bubblify),
       .flush_if(flush_if),
       .pc_write(pc_write),
       .ir_write(ir_write),
       .incr_num_inst(incr_num_inst));

   //-------------------------------------------------------------------------//
   // Per-stage wire connections
   //-------------------------------------------------------------------------//

   // IF stage
   assign i_address = pc;
   assign i_readM = i_mem_read;
   assign i_writeM = 0; // no instruction write

   // ID stage
   assign opcode = ir[15:12];
   assign func_code = ir[5:0];
   assign rs = ir[11:10];
   assign rt = ir[9:8];
   assign rd = ir[7:6];
   assign imm = ir[7:0];
   assign target_addr = ir[11:0];
   assign addr1 = rs;
   assign addr2 = rt;
   
   // EX stage
   assign alu_temp_1 = (alu_src_a_ex == `ALUSRCA_PC) ? pc :
                     /*(alu_src_a_ex == `ALUSRCA_REG) ?*/ a_ex;
   assign alu_temp_2 = (alu_src_b_ex == `ALUSRCB_ONE) ? 1 :
                       (alu_src_b_ex == `ALUSRCB_REG) ? b_ex :
                       (alu_src_b_ex == `ALUSRCB_IMM) ? imm_signed_ex :
                       /*(alu_src_b_ex == `ALUSRCB_ZERO) ?*/ 0;
   assign alu_operand_1 = alu_src_swap_ex ? alu_temp_2 : alu_temp_1;
   assign alu_operand_2 = alu_src_swap_ex ? alu_temp_1 : alu_temp_2;
   // alu_result == 0 means branch check fail
   assign resolved_pc = (alu_result == 0) ? npc_ex : npc_ex + imm_signed_ex;

   // MEM stage
   assign d_readM = d_mem_read_mem;
   assign d_writeM = d_mem_write_mem;
   assign d_address = alu_out_mem;
   assign d_data = d_mem_write_mem ? b_mem : {WORD_SIZE{1'bz}};

   // WB stage
   assign addr3 = write_reg_wb;
   assign writeData = (reg_write_src_wb == `REGWRITESRC_IMM) ? imm_signed_wb : // LHI
                      (reg_write_src_wb == `REGWRITESRC_ALU) ? alu_out_wb :
                      (reg_write_src_wb == `REGWRITESRC_MEM) ? MDR_wb :
                      /*(reg_write_src_wb == `REGWRITESRC_PC) ?*/ npc_wb;

   //-------------------------------------------------------------------------//
   // Register transfers
   //-------------------------------------------------------------------------//

   always @(posedge clk) begin
      if (reset_n == 0) begin
         // reset all pipeline registers and control signal registers
         // to zero to prevent any initial output
         pc <= 0;
         npc_id <= 0;
         npc_ex <= 0;
         npc_mem <= 0;
         npc_wb <= 0;
         valid_ex <= 0;
         MDR_wb <= 0;
         a_ex <= 0;
         b_ex <= 0;
         b_mem <= 0;
         alu_out_mem <= 0;
         // maybe set output_port to initially float
         output_port <= {WORD_SIZE{1'bz}};
         num_inst_if <= 0;
         num_inst_id <= 0;
         num_inst_ex <= 0;
      end
      else begin
         //------------------------//
         // Pipeline stage latches
         //------------------------//

         npc = pc + 1;

         if (pc_write) begin
            // Handle the case where conditional branch and jump is resolved at
            // the same time.
            //
            // Since branch is resolved in EX and jump in ID, PC resolution from
            // branch is always older than from jump and thus should be handled
            // first. Respect this order.
            if (branch_ex) begin
               pc <= resolved_pc;
            end
            else if (inst_type == `INSTTYPE_JUMP) begin // FIXME: 'jump' control signal?
               if (opcode == `OPCODE_JMP || opcode == `OPCODE_JAL) begin
                  pc <= {pc[15:12], target_addr};
               end
               else if (opcode == `OPCODE_RTYPE) begin
                  case (func_code)
                    `FUNC_JPR, `FUNC_JRL: begin
                       pc <= data1;
                    end
                    default: begin
                       // unknown jump type
                    end
                  endcase
               end
               else begin
                  // unknown jump type
               end
            end
            else begin
               pc <= npc;
            end
         end

         // IF stage
         //
         // For ir_write = 0, the ID stage is stalled and every IF/ID latches
         // including IR, pc_id and npc_id should be preserved as is.
         if (ir_write) begin
            npc_id <= npc; // adder for PC
            pc_id <= pc; // for debugging purpose
         end

         // ID stage
         npc_ex <= npc_id;
         pc_ex <= pc_id;
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
         imm_signed_ex <= {{8{imm[7]}}, imm};
         halt_ex <= halt_id;

         // EX stage
         npc_mem <= npc_ex;
         pc_mem <= pc_ex;
         inst_type_mem <= inst_type_ex;
         rs_mem <= rs_ex;
         rt_mem <= rt_ex;
         b_mem <= b_ex;
         alu_out_mem <= alu_result;
         write_reg_mem <= write_reg_ex;
         imm_signed_mem <= imm_signed_ex;
         halt_mem <= halt_ex;

         // MEM stage
         npc_wb <= npc_mem;
         pc_wb <= pc_mem;
         inst_type_wb <= inst_type_mem;
         rs_wb <= rs_mem;
         rt_wb <= rt_mem;
         alu_out_wb <= alu_out_mem;
         MDR_wb <= d_data;
         write_reg_wb <= write_reg_mem;
         imm_signed_wb <= imm_signed_mem;
         halt_wb <= halt_mem;

         //------------------------//
         // Control signal latches
         //------------------------//

         // ID stage (EX+MEM+WB)
         // if hazard detected, insert bubbles into pipeline
         valid_ex         <= bubblify ? 0 : 1;
         branch_ex        <= bubblify ? 0 : branch;
         alu_op_ex        <= bubblify ? 0 : alu_op;
         alu_src_a_ex     <= bubblify ? 0 : alu_src_a;
         alu_src_b_ex     <= bubblify ? 0 : alu_src_b;
         alu_src_swap_ex  <= bubblify ? 0 : alu_src_swap;
         i_mem_read_ex    <= bubblify ? 0 : i_mem_read;
         d_mem_read_ex    <= bubblify ? 0 : d_mem_read;
         i_mem_write_ex   <= bubblify ? 0 : i_mem_write;
         d_mem_write_ex   <= bubblify ? 0 : d_mem_write;
         reg_write_ex     <= bubblify ? 0 : reg_write;
         reg_write_src_ex <= bubblify ? 0 : reg_write_src;

         // EX stage (MEM+WB)
         valid_mem <= valid_ex;
         i_mem_read_mem <= i_mem_read_ex;
         d_mem_read_mem <= d_mem_read_ex;
         i_mem_write_mem <= i_mem_write_ex;
         d_mem_write_mem <= d_mem_write_ex;
         reg_write_mem <= reg_write_ex;
         reg_write_src_mem <= reg_write_src_ex;

         // MEM stage (WB)
         valid_wb <= valid_mem;
         reg_write_wb <= reg_write_mem;
         reg_write_src_wb <= reg_write_src_mem;

         // output port assertion
         if (output_write == 1) begin
            output_port <= data1;
         end

         // num_inst update
         //
         // increased num_inst_if will propagate into the pipeline,
         // setting the right value for each stage
         if (incr_num_inst) begin
            num_inst_if <= num_inst_if + 1;
            num_inst_id <= num_inst_if;
         end
      end
   end
endmodule
