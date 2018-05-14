`timescale 1ns/1ns

`include "constants.v"
`include "opcodes.v"

module forwarding_unit
  #(parameter DATA_FORWARDING = 1)
   (input [1:0]      rs_ex,
    input [1:0]      rt_ex,
    input            reg_write_mem,
    input            reg_write_wb,
    input [1:0]      write_reg_mem,
    input [1:0]      write_reg_wb,
    output reg [1:0] rs_forward_src, // 0: from MEM, 1: from WB, 2: no forwarding (RF)
    output reg [1:0] rt_forward_src // 0: from MEM, 1: from WB, 2: no forwarding (RF)
);

   always @(*) begin
      // If DATA_FORWARDING is disabled, r*_forward_src will always be set to
      // `FORWARD_SRC_RF by if-else fallthrough.

      // rs
      if (DATA_FORWARDING && reg_write_mem && rs_ex == write_reg_mem) begin
         rs_forward_src = `FORWARD_SRC_MEM;
      end
      else if (DATA_FORWARDING && reg_write_wb && rs_ex == write_reg_wb) begin
         rs_forward_src = `FORWARD_SRC_WB;
      end
      else begin
         rs_forward_src = `FORWARD_SRC_RF;
      end

      // rt
      if (DATA_FORWARDING && reg_write_mem && rt_ex == write_reg_mem) begin
         rt_forward_src = `FORWARD_SRC_MEM;
      end
      else if (DATA_FORWARDING && reg_write_wb && rt_ex == write_reg_wb) begin
         rt_forward_src = `FORWARD_SRC_WB;
      end
      else begin
         rt_forward_src = `FORWARD_SRC_RF;
      end
   end
endmodule
