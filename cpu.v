`timescale 1ns/1ns
`define WORD_SIZE 16    // data and address word size

`include "opcodes.v"

module cpu(
        input clk, 
        input reset_n,

	// Instruction memory interface
        output i_readM, 
        output i_writeM, 
        output [`WORD_SIZE-1:0] i_address, 
        inout [`WORD_SIZE-1:0] i_data, 

	// Data memory interface
        output d_readM, 
        output d_writeM, 
        output [`WORD_SIZE-1:0] d_address, 
        inout [`WORD_SIZE-1:0] d_data, 

        output [`WORD_SIZE-1:0] num_inst, 
        output [`WORD_SIZE-1:0] output_port, 
        output is_halted
);

   // Datapath - control Unit
   wire        clk;
   wire        reset_n;
   wire        pc_write;
   wire        pc_write_cond;
   wire        i_or_d;
   wire        input_ready;
   wire [3:0]  opcode;
   wire [5:0]  func_code;
   wire        reg_write, ir_write, output_write;
   wire [1:0]  reg_dst, reg_write_src;
   wire        alu_src_a;
   wire [1:0]  pc_src, alu_src_b;
   wire        alu_src_swap;
   wire [3:0]  alu_op;

   control_unit Control (.clk (clk),
			 .reset_n (reset_n),
			 .opcode (opcode),
			 .func_code (func_code),
			 .pc_write (pc_write),
			 .pc_write_cond (pc_write_cond),
			 .pc_src (pc_src),
			 .i_or_d (i_or_d),
			 .i_mem_read(i_readM),
			 .d_mem_read(d_readM),
			 .i_mem_write(i_writeM),
			 .d_mem_write(d_writeM),
			 .ir_write (ir_write),
			 .alu_op (alu_op),
			 .alu_src_a (alu_src_a),
			 .alu_src_b (alu_src_b),
			 .alu_src_swap (alu_src_swap),
			 .reg_write (reg_write),
			 .reg_write_src (reg_write_src),
			 .reg_dst (reg_dst),
			 .output_write (output_write),
			 .num_inst (num_inst),
			 .is_halted (is_halted)); 
   
   datapath #(.WORD_SIZE (`WORD_SIZE)) 
   DP (
       .clk(clk),
       .reset_n (reset_n),
       .pc_write (pc_write),
       .pc_write_cond (pc_write_cond),
       .pc_src (pc_src),
       .i_or_d (i_or_d),
       .i_mem_write (i_writeM),
       .d_mem_write (d_writeM),
       .ir_write (ir_write),
       .alu_op (alu_op),
       .alu_src_a (alu_src_a),
       .alu_src_b (alu_src_b),
       .alu_src_swap (alu_src_swap),
       .reg_write (reg_write),
       .reg_write_src (reg_write_src),
       .reg_dst (reg_dst),
       .output_write (output_write),
       .i_data (i_data),
       .d_data (d_data),
       .input_ready (input_ready),
       .i_address (i_address),
       .d_address (d_address),
       .output_port (output_port),
       .opcode(opcode),
       .func_code (func_code)
       );
endmodule
