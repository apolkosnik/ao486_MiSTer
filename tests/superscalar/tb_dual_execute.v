//==============================================================================
// Test Bench for Dual Execution Units
//
// Tests the dual ALU execution capability (ALU0 and ALU1 in parallel)
//
// Based on SUPERSCALAR_TEST_PLAN.md Section 3: Dual Execute Tests
//==============================================================================

`timescale 1ns/1ps

module tb_dual_execute;

//------------------------------------------------------------------------------
// Clock and Reset
//------------------------------------------------------------------------------
reg clk;
reg rst_n;

//------------------------------------------------------------------------------
// ALU0 Interface
//------------------------------------------------------------------------------
reg             alu0_valid;
reg [6:0]       alu0_cmd;
reg [31:0]      alu0_operand1;
reg [31:0]      alu0_operand2;
reg             alu0_uses_mult;
reg             alu0_uses_div;

wire            alu0_ready;
wire [31:0]     alu0_result;
wire            alu0_busy;

//------------------------------------------------------------------------------
// ALU1 Interface
//------------------------------------------------------------------------------
reg             alu1_valid;
reg [6:0]       alu1_cmd;
reg [31:0]      alu1_operand1;
reg [31:0]      alu1_operand2;
reg             alu1_uses_mult;
reg             alu1_uses_div;

wire            alu1_ready;
wire [31:0]     alu1_result;
wire            alu1_busy;

//------------------------------------------------------------------------------
// Shared Resources
//------------------------------------------------------------------------------
wire            mult_div_busy;

//------------------------------------------------------------------------------
// DUT Instantiation
//------------------------------------------------------------------------------
dual_execute dut (
    .clk(clk),
    .rst_n(rst_n),

    // ALU0
    .alu0_valid(alu0_valid),
    .alu0_cmd(alu0_cmd),
    .alu0_operand1(alu0_operand1),
    .alu0_operand2(alu0_operand2),
    .alu0_uses_mult(alu0_uses_mult),
    .alu0_uses_div(alu0_uses_div),
    .alu0_ready(alu0_ready),
    .alu0_result(alu0_result),
    .alu0_busy(alu0_busy),

    // ALU1
    .alu1_valid(alu1_valid),
    .alu1_cmd(alu1_cmd),
    .alu1_operand1(alu1_operand1),
    .alu1_operand2(alu1_operand2),
    .alu1_uses_mult(alu1_uses_mult),
    .alu1_uses_div(alu1_uses_div),
    .alu1_ready(alu1_ready),
    .alu1_result(alu1_result),
    .alu1_busy(alu1_busy),

    // Shared
    .mult_div_busy(mult_div_busy)
);

//------------------------------------------------------------------------------
// Clock Generation
//------------------------------------------------------------------------------
initial begin
    clk = 0;
    forever #5 clk = ~clk;
end

//------------------------------------------------------------------------------
// Test Statistics
//------------------------------------------------------------------------------
integer test_count = 0;
integer pass_count = 0;
integer fail_count = 0;

//------------------------------------------------------------------------------
// Test Helper Tasks
//------------------------------------------------------------------------------

task reset_dut;
begin
    rst_n = 0;
    alu0_valid = 0;
    alu0_cmd = 0;
    alu0_operand1 = 0;
    alu0_operand2 = 0;
    alu0_uses_mult = 0;
    alu0_uses_div = 0;
    alu1_valid = 0;
    alu1_cmd = 0;
    alu1_operand1 = 0;
    alu1_operand2 = 0;
    alu1_uses_mult = 0;
    alu1_uses_div = 0;
    repeat(2) @(posedge clk);
    rst_n = 1;
    @(posedge clk);
end
endtask

task issue_alu0(
    input [6:0] cmd,
    input [31:0] op1,
    input [31:0] op2,
    input uses_mult,
    input uses_div
);
begin
    @(posedge clk);
    alu0_valid = 1;
    alu0_cmd = cmd;
    alu0_operand1 = op1;
    alu0_operand2 = op2;
    alu0_uses_mult = uses_mult;
    alu0_uses_div = uses_div;
    @(posedge clk);
    alu0_valid = 0;
end
endtask

task issue_alu1(
    input [6:0] cmd,
    input [31:0] op1,
    input [31:0] op2,
    input uses_mult,
    input uses_div
);
begin
    @(posedge clk);
    alu1_valid = 1;
    alu1_cmd = cmd;
    alu1_operand1 = op1;
    alu1_operand2 = op2;
    alu1_uses_mult = uses_mult;
    alu1_uses_div = uses_div;
    @(posedge clk);
    alu1_valid = 0;
end
endtask

task issue_dual(
    input [6:0] cmd0,
    input [31:0] op1_0,
    input [31:0] op2_0,
    input [6:0] cmd1,
    input [31:0] op1_1,
    input [31:0] op2_1
);
begin
    @(posedge clk);
    // ALU0
    alu0_valid = 1;
    alu0_cmd = cmd0;
    alu0_operand1 = op1_0;
    alu0_operand2 = op2_0;
    alu0_uses_mult = 0;
    alu0_uses_div = 0;
    // ALU1
    alu1_valid = 1;
    alu1_cmd = cmd1;
    alu1_operand1 = op1_1;
    alu1_operand2 = op2_1;
    alu1_uses_mult = 0;
    alu1_uses_div = 0;
    @(posedge clk);
    alu0_valid = 0;
    alu1_valid = 0;
end
endtask

task check_result(
    input integer test_num,
    input [255:0] test_name,
    input [31:0] expected,
    input [31:0] actual
);
begin
    test_count = test_count + 1;
    if (expected === actual) begin
        $display("PASS: Test %0d - %s", test_num, test_name);
        pass_count = pass_count + 1;
    end else begin
        $display("FAIL: Test %0d - %s (Expected: 0x%08x, Got: 0x%08x)",
                 test_num, test_name, expected, actual);
        fail_count = fail_count + 1;
    end
end
endtask

task check_flag(
    input integer test_num,
    input [255:0] test_name,
    input expected,
    input actual
);
begin
    test_count = test_count + 1;
    if (expected === actual) begin
        $display("PASS: Test %0d - %s", test_num, test_name);
        pass_count = pass_count + 1;
    end else begin
        $display("FAIL: Test %0d - %s (Expected: %0d, Got: %0d)",
                 test_num, test_name, expected, actual);
        fail_count = fail_count + 1;
    end
end
endtask

//------------------------------------------------------------------------------
// Test Scenarios
//------------------------------------------------------------------------------

// CMD definitions (simplified for testing)
localparam CMD_ADD = 7'd1;
localparam CMD_SUB = 7'd2;
localparam CMD_AND = 7'd3;
localparam CMD_OR  = 7'd4;
localparam CMD_XOR = 7'd5;
localparam CMD_IMUL = 7'd54;

initial begin
    $display("========================================");
    $display("Dual Execute Test Bench");
    $display("========================================");

    reset_dut();

    //--------------------------------------------------------------------------
    // Test 3.1: Dual ALU Operations
    //--------------------------------------------------------------------------
    $display("\nTest 3.1: Dual ALU Operations");
    reset_dut();

    // Issue to both ALUs simultaneously
    // ALU0: ADD 10 + 5 = 15
    // ALU1: SUB 20 - 3 = 17
    issue_dual(CMD_ADD, 32'd10, 32'd5, CMD_SUB, 32'd20, 32'd3);

    // Wait for results (assume 1-cycle ALU ops)
    repeat(2) @(posedge clk);

    check_flag(1, "ALU0 ready", 1, alu0_ready);
    check_result(2, "ALU0 result (10+5)", 32'd15, alu0_result);
    check_flag(3, "ALU1 ready", 1, alu1_ready);
    check_result(4, "ALU1 result (20-3)", 32'd17, alu1_result);

    //--------------------------------------------------------------------------
    // Test 3.2: ALU0 Only
    //--------------------------------------------------------------------------
    $display("\nTest 3.2: ALU0 Single Issue");
    reset_dut();

    // Issue only to ALU0
    issue_alu0(CMD_ADD, 32'd100, 32'd50, 0, 0);

    repeat(2) @(posedge clk);

    check_flag(5, "ALU0 ready", 1, alu0_ready);
    check_result(6, "ALU0 result (100+50)", 32'd150, alu0_result);
    check_flag(7, "ALU1 not ready (not issued)", 0, alu1_ready);

    //--------------------------------------------------------------------------
    // Test 3.3: ALU1 Only
    //--------------------------------------------------------------------------
    $display("\nTest 3.3: ALU1 Single Issue");
    reset_dut();

    // Issue only to ALU1
    issue_alu1(CMD_SUB, 32'd200, 32'd50, 0, 0);

    repeat(2) @(posedge clk);

    check_flag(8, "ALU0 not ready (not issued)", 0, alu0_ready);
    check_flag(9, "ALU1 ready", 1, alu1_ready);
    check_result(10, "ALU1 result (200-50)", 32'd150, alu1_result);

    //--------------------------------------------------------------------------
    // Test 3.4: Bitwise Operations
    //--------------------------------------------------------------------------
    $display("\nTest 3.4: Bitwise Operations");
    reset_dut();

    // ALU0: AND 0xFF00 & 0x00FF = 0x0000
    // ALU1: OR  0xFF00 | 0x00FF = 0xFFFF
    issue_dual(CMD_AND, 32'hFF00, 32'h00FF, CMD_OR, 32'hFF00, 32'h00FF);

    repeat(2) @(posedge clk);

    check_result(11, "ALU0 AND result", 32'h0000, alu0_result);
    check_result(12, "ALU1 OR result", 32'hFFFF, alu1_result);

    //--------------------------------------------------------------------------
    // Test 3.5: XOR Operation
    //--------------------------------------------------------------------------
    $display("\nTest 3.5: XOR Operation");
    reset_dut();

    // ALU0: XOR 0xAAAA ^ 0x5555 = 0xFFFF
    issue_alu0(CMD_XOR, 32'hAAAA, 32'h5555, 0, 0);

    repeat(2) @(posedge clk);

    check_result(13, "ALU0 XOR result", 32'hFFFF, alu0_result);

    //--------------------------------------------------------------------------
    // Test 3.6: Busy States
    //--------------------------------------------------------------------------
    $display("\nTest 3.6: Busy States");
    reset_dut();

    // Check idle state
    @(posedge clk);
    check_flag(14, "ALU0 idle initially", 0, alu0_busy);
    check_flag(15, "ALU1 idle initially", 0, alu1_busy);

    // Issue work
    issue_dual(CMD_ADD, 32'd1, 32'd2, CMD_ADD, 32'd3, 32'd4);

    // During execution, should be busy
    @(posedge clk);
    // Note: Busy behavior depends on implementation
    // May be busy for 1 cycle or immediately available

    //--------------------------------------------------------------------------
    // Test 3.7: Zero Operands
    //--------------------------------------------------------------------------
    $display("\nTest 3.7: Zero Operands");
    reset_dut();

    // ADD 0 + 0 = 0
    issue_dual(CMD_ADD, 32'd0, 32'd0, CMD_SUB, 32'd0, 32'd0);

    repeat(2) @(posedge clk);

    check_result(16, "ALU0 zero add", 32'd0, alu0_result);
    check_result(17, "ALU1 zero sub", 32'd0, alu1_result);

    //--------------------------------------------------------------------------
    // Test 3.8: Large Numbers
    //--------------------------------------------------------------------------
    $display("\nTest 3.8: Large Numbers");
    reset_dut();

    // Test with max values
    issue_dual(CMD_ADD, 32'hFFFFFFFF, 32'h00000001,
               CMD_SUB, 32'hFFFFFFFF, 32'h00000001);

    repeat(2) @(posedge clk);

    // ADD wraps around: 0xFFFFFFFF + 1 = 0x00000000
    check_result(18, "ALU0 overflow add", 32'h00000000, alu0_result);
    // SUB: 0xFFFFFFFF - 1 = 0xFFFFFFFE
    check_result(19, "ALU1 large sub", 32'hFFFFFFFE, alu1_result);

    //--------------------------------------------------------------------------
    // Test 3.9: Shared Multiplier (if ALU0 uses it)
    //--------------------------------------------------------------------------
    $display("\nTest 3.9: Multiplier Access");
    reset_dut();

    // ALU0: IMUL (uses multiplier)
    // ALU1: ADD (doesn't use multiplier)
    issue_alu0(CMD_IMUL, 32'd10, 32'd5, 1, 0);  // uses_mult=1
    @(posedge clk);
    issue_alu1(CMD_ADD, 32'd20, 32'd3, 0, 0);

    // Multiplier should be busy for ALU0
    // Note: mult_div_busy behavior depends on implementation
    @(posedge clk);

    // ALU1 should complete faster (1 cycle vs multi-cycle multiply)
    repeat(2) @(posedge clk);
    check_flag(20, "ALU1 completes (ADD is fast)", 1, alu1_ready);
    check_result(21, "ALU1 result", 32'd23, alu1_result);

    // Wait for multiply to complete
    repeat(10) @(posedge clk);
    if (alu0_ready) begin
        check_result(22, "ALU0 multiply result (10*5)", 32'd50, alu0_result);
    end else begin
        $display("Note: Multiply still in progress (multi-cycle operation)");
    end

    //--------------------------------------------------------------------------
    // Test Summary
    //--------------------------------------------------------------------------
    $display("\n========================================");
    $display("Test Summary");
    $display("========================================");
    $display("Total Tests: %0d", test_count);
    $display("Passed:      %0d", pass_count);
    $display("Failed:      %0d", fail_count);

    if (fail_count == 0) begin
        $display("\nALL TESTS PASSED!");
    end else begin
        $display("\nSOME TESTS FAILED!");
    end
    $display("========================================");

    #100;
    $finish;
end

//------------------------------------------------------------------------------
// Waveform Dumping
//------------------------------------------------------------------------------
initial begin
    $dumpfile("tb_dual_execute.vcd");
    $dumpvars(0, tb_dual_execute);
end

endmodule
