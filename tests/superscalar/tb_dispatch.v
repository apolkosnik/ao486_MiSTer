//==============================================================================
// Test Bench for Dispatch Logic
//
// Tests the superscalar dispatch unit that makes dual-issue decisions
//
// Based on SUPERSCALAR_TEST_PLAN.md Section 2: Dispatch Logic Tests
//==============================================================================

`timescale 1ns/1ps

module tb_dispatch;

//------------------------------------------------------------------------------
// Clock and Reset
//------------------------------------------------------------------------------
reg clk;
reg rst_n;

//------------------------------------------------------------------------------
// Instruction Queue Interface
//------------------------------------------------------------------------------
reg             inst0_valid;
reg [6:0]       inst0_cmd;
reg [10:0]      inst0_mutex;
reg             inst0_is_mult;
reg             inst0_is_div;
reg             inst0_is_branch;

reg             inst1_valid;
reg [6:0]       inst1_cmd;
reg [10:0]      inst1_mutex;
reg             inst1_is_mult;
reg             inst1_is_div;
reg             inst1_is_branch;

//------------------------------------------------------------------------------
// Resource Availability
//------------------------------------------------------------------------------
reg             alu0_busy;
reg             alu1_busy;
reg             mult_div_busy;

//------------------------------------------------------------------------------
// Dispatch Outputs
//------------------------------------------------------------------------------
wire            dispatch_inst0;
wire            dispatch_inst1;
wire            dual_issue;

wire            inst0_to_alu0;
wire            inst0_to_alu1;
wire            inst1_to_alu0;
wire            inst1_to_alu1;

wire            stall_dependency;
wire            stall_structural;
wire            inst0_must_single_issue;
wire            inst1_must_single_issue;

//------------------------------------------------------------------------------
// DUT Instantiation
//------------------------------------------------------------------------------
dispatch dut (
    .clk(clk),
    .rst_n(rst_n),

    // Instruction inputs
    .inst0_valid(inst0_valid),
    .inst0_cmd(inst0_cmd),
    .inst0_mutex(inst0_mutex),
    .inst0_is_mult(inst0_is_mult),
    .inst0_is_div(inst0_is_div),
    .inst0_is_branch(inst0_is_branch),

    .inst1_valid(inst1_valid),
    .inst1_cmd(inst1_cmd),
    .inst1_mutex(inst1_mutex),
    .inst1_is_mult(inst1_is_mult),
    .inst1_is_div(inst1_is_div),
    .inst1_is_branch(inst1_is_branch),

    // Resource status
    .alu0_busy(alu0_busy),
    .alu1_busy(alu1_busy),
    .mult_div_busy(mult_div_busy),

    // Dispatch decisions
    .dispatch_inst0(dispatch_inst0),
    .dispatch_inst1(dispatch_inst1),
    .dual_issue(dual_issue),

    // Routing
    .inst0_to_alu0(inst0_to_alu0),
    .inst0_to_alu1(inst0_to_alu1),
    .inst1_to_alu0(inst1_to_alu0),
    .inst1_to_alu1(inst1_to_alu1),

    // Stall reasons
    .stall_dependency(stall_dependency),
    .stall_structural(stall_structural),
    .inst0_must_single_issue(inst0_must_single_issue),
    .inst1_must_single_issue(inst1_must_single_issue)
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
    inst0_valid = 0;
    inst0_cmd = 0;
    inst0_mutex = 0;
    inst0_is_mult = 0;
    inst0_is_div = 0;
    inst0_is_branch = 0;
    inst1_valid = 0;
    inst1_cmd = 0;
    inst1_mutex = 0;
    inst1_is_mult = 0;
    inst1_is_div = 0;
    inst1_is_branch = 0;
    alu0_busy = 0;
    alu1_busy = 0;
    mult_div_busy = 0;
    repeat(2) @(posedge clk);
    rst_n = 1;
    @(posedge clk);
end
endtask

task set_instruction0(
    input [6:0] cmd,
    input [10:0] mutex,
    input is_mult,
    input is_div,
    input is_branch
);
begin
    inst0_valid = 1;
    inst0_cmd = cmd;
    inst0_mutex = mutex;
    inst0_is_mult = is_mult;
    inst0_is_div = is_div;
    inst0_is_branch = is_branch;
end
endtask

task set_instruction1(
    input [6:0] cmd,
    input [10:0] mutex,
    input is_mult,
    input is_div,
    input is_branch
);
begin
    inst1_valid = 1;
    inst1_cmd = cmd;
    inst1_mutex = mutex;
    inst1_is_mult = is_mult;
    inst1_is_div = is_div;
    inst1_is_branch = is_branch;
end
endtask

task check_result(
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

initial begin
    $display("========================================");
    $display("Dispatch Logic Test Bench");
    $display("========================================");

    reset_dut();

    //--------------------------------------------------------------------------
    // Test 2.1: RAW Dependency Detection
    //--------------------------------------------------------------------------
    $display("\nTest 2.1: RAW Dependency Detection");
    reset_dut();

    // Inst0: MOV EAX, 1 (writes EAX, mutex[0]=1)
    // Inst1: ADD EBX, EAX (reads EAX, mutex[0]=1)
    // Should detect dependency and stall inst1
    set_instruction0(7'd10, 11'b00000000001, 0, 0, 0);  // mutex[0]=1 (EAX)
    set_instruction1(7'd20, 11'b00000000001, 0, 0, 0);  // mutex[0]=1 (EAX)

    @(posedge clk);
    #1;  // Wait for combinational logic

    check_result(1, "stall_dependency asserted", 1, stall_dependency);
    check_result(2, "dispatch_inst0 issued", 1, dispatch_inst0);
    check_result(3, "dispatch_inst1 stalled", 0, dispatch_inst1);
    check_result(4, "dual_issue is 0", 0, dual_issue);

    //--------------------------------------------------------------------------
    // Test 2.2: No Dependency
    //--------------------------------------------------------------------------
    $display("\nTest 2.2: No Dependency - Dual Issue");
    reset_dut();

    // Inst0: MOV EAX, 1 (mutex[0]=1, writes EAX)
    // Inst1: MOV EBX, 2 (mutex[3]=1, writes EBX)
    // No dependency, should dual-issue
    set_instruction0(7'd10, 11'b00000000001, 0, 0, 0);  // mutex[0]=1 (EAX)
    set_instruction1(7'd20, 11'b00000001000, 0, 0, 0);  // mutex[3]=1 (EBX)

    @(posedge clk);
    #1;

    check_result(5, "No dependency detected", 0, stall_dependency);
    check_result(6, "dispatch_inst0 issued", 1, dispatch_inst0);
    check_result(7, "dispatch_inst1 issued", 1, dispatch_inst1);
    check_result(8, "dual_issue ENABLED", 1, dual_issue);

    //--------------------------------------------------------------------------
    // Test 2.3: Resource Conflict (Multiplier)
    //--------------------------------------------------------------------------
    $display("\nTest 2.3: Resource Conflict - Multiplier");
    reset_dut();

    // Both instructions need multiplier
    // Inst0: IMUL EAX, EBX
    // Inst1: IMUL ECX, EDX
    set_instruction0(7'd30, 11'b00000001001, 1, 0, 0);  // is_mult=1
    set_instruction1(7'd31, 11'b00000010010, 1, 0, 0);  // is_mult=1

    @(posedge clk);
    #1;

    check_result(9, "structural hazard detected", 1, stall_structural);
    check_result(10, "dispatch_inst0 issued", 1, dispatch_inst0);
    check_result(11, "dispatch_inst1 stalled", 0, dispatch_inst1);
    check_result(12, "dual_issue is 0", 0, dual_issue);

    //--------------------------------------------------------------------------
    // Test 2.4: Branch Serialization
    //--------------------------------------------------------------------------
    $display("\nTest 2.4: Branch Serialization");
    reset_dut();

    // Inst0: JNZ label (is_branch=1)
    // Inst1: MOV EAX, 1 (normal ALU)
    // Branch should force single-issue
    set_instruction0(7'd40, 11'b00000000000, 0, 0, 1);  // is_branch=1
    set_instruction1(7'd41, 11'b00000000001, 0, 0, 0);

    @(posedge clk);
    #1;

    check_result(13, "inst0_must_single_issue", 1, inst0_must_single_issue);
    check_result(14, "dispatch_inst0 issued", 1, dispatch_inst0);
    check_result(15, "dispatch_inst1 stalled", 0, dispatch_inst1);
    check_result(16, "dual_issue is 0", 0, dual_issue);

    //--------------------------------------------------------------------------
    // Test 2.5: ALU Routing
    //--------------------------------------------------------------------------
    $display("\nTest 2.5: ALU Routing");
    reset_dut();

    // Two independent ALU operations
    // Inst0: ADD EAX, EBX
    // Inst1: SUB ECX, EDX
    set_instruction0(7'd50, 11'b00000001001, 0, 0, 0);  // EAX, EBX
    set_instruction1(7'd51, 11'b00000010010, 0, 0, 0);  // ECX, EDX

    @(posedge clk);
    #1;

    check_result(17, "inst0 routed to ALU0", 1, inst0_to_alu0);
    check_result(18, "inst0 NOT to ALU1", 0, inst0_to_alu1);
    check_result(19, "inst1 NOT to ALU0", 0, inst1_to_alu0);
    check_result(20, "inst1 routed to ALU1", 1, inst1_to_alu1);
    check_result(21, "dual_issue enabled", 1, dual_issue);

    //--------------------------------------------------------------------------
    // Test 2.6: ALU0 Busy
    //--------------------------------------------------------------------------
    $display("\nTest 2.6: ALU0 Busy - Structural Hazard");
    reset_dut();

    // ALU0 is busy
    alu0_busy = 1;

    set_instruction0(7'd60, 11'b00000000001, 0, 0, 0);
    set_instruction1(7'd61, 11'b00000001000, 0, 0, 0);

    @(posedge clk);
    #1;

    check_result(22, "structural hazard (ALU0 busy)", 1, stall_structural);
    check_result(23, "dispatch_inst0 stalled", 0, dispatch_inst0);
    check_result(24, "dispatch_inst1 stalled", 0, dispatch_inst1);

    //--------------------------------------------------------------------------
    // Test 2.7: WAW Hazard (Write-After-Write)
    //--------------------------------------------------------------------------
    $display("\nTest 2.7: WAW Hazard Detection");
    reset_dut();

    // Both write to EAX (should never happen, but test detects it)
    // Inst0: MOV EAX, 1
    // Inst1: MOV EAX, 2
    set_instruction0(7'd70, 11'b00000000001, 0, 0, 0);  // EAX
    set_instruction1(7'd71, 11'b00000000001, 0, 0, 0);  // EAX (same mutex)

    @(posedge clk);
    #1;

    check_result(25, "WAW dependency detected", 1, stall_dependency);
    check_result(26, "Only inst0 dispatches", 1, dispatch_inst0);
    check_result(27, "inst1 stalled", 0, dispatch_inst1);

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
    $dumpfile("tb_dispatch.vcd");
    $dumpvars(0, tb_dispatch);
end

endmodule
