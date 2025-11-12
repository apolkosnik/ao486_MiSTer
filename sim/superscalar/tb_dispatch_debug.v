`timescale 1ns/1ps

`include "../../rtl/ao486/defines.v"

// Minimal test to debug X propagation
module tb_dispatch_debug();

reg clk = 0;
reg rst_n = 0;

always #5 clk = ~clk;

initial begin
    #20 rst_n = 1;
end

// All inputs initialized
reg dispatch_reset = 0;
reg inst0_valid = 0;
reg [6:0] inst0_cmd = 0;
reg [3:0] inst0_cmdex = 0;
reg [10:0] inst0_mutex = 0;
reg inst0_uses_alu = 0;
reg inst0_uses_mult = 0;
reg inst0_uses_div = 0;
reg inst0_uses_memory = 0;
reg inst0_is_branch = 0;
reg inst0_is_complex = 0;

reg inst1_valid = 0;
reg [6:0] inst1_cmd = 0;
reg [3:0] inst1_cmdex = 0;
reg [10:0] inst1_mutex = 0;
reg inst1_uses_alu = 0;
reg inst1_uses_mult = 0;
reg inst1_uses_div = 0;
reg inst1_uses_memory = 0;
reg inst1_is_branch = 0;
reg inst1_is_complex = 0;

reg alu0_busy = 0;
reg alu1_busy = 0;
reg mult_busy = 0;
reg div_busy = 0;
reg mem_busy = 0;

reg [10:0] exe0_mutex = 0;
reg [10:0] exe1_mutex = 0;
reg [10:0] wr0_mutex = 0;
reg [10:0] wr1_mutex = 0;

wire dispatch_inst0;
wire dispatch_inst1;
wire inst0_to_alu0;
wire inst0_to_alu1;
wire inst1_to_alu0;
wire inst1_to_alu1;
wire dual_issue;
wire stall_dependency;
wire stall_structural;

dispatch dut(
    .clk(clk),
    .rst_n(rst_n),
    .dispatch_reset(dispatch_reset),
    .inst0_valid(inst0_valid),
    .inst0_cmd(inst0_cmd),
    .inst0_cmdex(inst0_cmdex),
    .inst0_mutex(inst0_mutex),
    .inst0_uses_alu(inst0_uses_alu),
    .inst0_uses_mult(inst0_uses_mult),
    .inst0_uses_div(inst0_uses_div),
    .inst0_uses_memory(inst0_uses_memory),
    .inst0_is_branch(inst0_is_branch),
    .inst0_is_complex(inst0_is_complex),
    .inst1_valid(inst1_valid),
    .inst1_cmd(inst1_cmd),
    .inst1_cmdex(inst1_cmdex),
    .inst1_mutex(inst1_mutex),
    .inst1_uses_alu(inst1_uses_alu),
    .inst1_uses_mult(inst1_uses_mult),
    .inst1_uses_div(inst1_uses_div),
    .inst1_uses_memory(inst1_uses_memory),
    .inst1_is_branch(inst1_is_branch),
    .inst1_is_complex(inst1_is_complex),
    .alu0_busy(alu0_busy),
    .alu1_busy(alu1_busy),
    .mult_busy(mult_busy),
    .div_busy(div_busy),
    .mem_busy(mem_busy),
    .exe0_mutex(exe0_mutex),
    .exe1_mutex(exe1_mutex),
    .wr0_mutex(wr0_mutex),
    .wr1_mutex(wr1_mutex),
    .dispatch_inst0(dispatch_inst0),
    .dispatch_inst1(dispatch_inst1),
    .inst0_to_alu0(inst0_to_alu0),
    .inst0_to_alu1(inst0_to_alu1),
    .inst1_to_alu0(inst1_to_alu0),
    .inst1_to_alu1(inst1_to_alu1),
    .dual_issue(dual_issue),
    .stall_dependency(stall_dependency),
    .stall_structural(stall_structural)
);

initial begin
    $display("Debug Test - Checking signal propagation");

    @(posedge rst_n);
    @(posedge clk);

    $display("\nInitial state (all zeros):");
    $display("  dispatch_inst0 = %b", dispatch_inst0);
    $display("  dispatch_inst1 = %b", dispatch_inst1);
    #1;

    // Set up a simple test
    inst0_valid = 1;
    inst0_cmd = `CMD_ADD;
    inst0_mutex = 11'b00000000001;  // EAX
    inst0_uses_alu = 1;

    #1;
    $display("\nAfter setting inst0:");
    $display("  inst0_valid = %b", inst0_valid);
    $display("  inst0_uses_alu = %b", inst0_uses_alu);
    $display("  alu0_busy = %b, alu1_busy = %b", alu0_busy, alu1_busy);
    $display("  dispatch_inst0 = %b", dispatch_inst0);

    @(posedge clk);
    #1;
    $display("\nAfter clock:");
    $display("  dispatch_inst0 = %b", dispatch_inst0);

    if (dispatch_inst0 === 1'b1)
        $display("PASS: dispatch_inst0 is 1");
    else if (dispatch_inst0 === 1'b0)
        $display("FAIL: dispatch_inst0 is 0 (should be 1)");
    else
        $display("FAIL: dispatch_inst0 is X or Z!");

    $finish;
end

initial begin
    $dumpfile("debug.vcd");
    $dumpvars(0, tb_dispatch_debug);
end

endmodule
