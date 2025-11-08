/*
 * Test Bench for Dispatch Unit
 *
 * Tests the dispatch module's ability to:
 * - Detect data dependencies between instructions
 * - Detect resource conflicts
 * - Make correct dual-issue decisions
 * - Handle structural hazards
 */

`timescale 1ns/1ps

`include "../../rtl/ao486/defines.v"

module tb_dispatch();

//------------------------------------------------------------------------------
// Clock and Reset
//------------------------------------------------------------------------------

reg clk;
reg rst_n;

initial begin
    clk = 0;
    forever #5 clk = ~clk; // 100MHz clock
end

initial begin
    rst_n = 0;
    #20;
    rst_n = 1;
end

//------------------------------------------------------------------------------
// DUT Signals
//------------------------------------------------------------------------------

reg             dispatch_reset;

// Instruction 0
reg             inst0_valid;
reg [6:0]       inst0_cmd;
reg [3:0]       inst0_cmdex;
reg [10:0]      inst0_mutex;
reg             inst0_uses_alu;
reg             inst0_uses_mult;
reg             inst0_uses_div;
reg             inst0_uses_memory;
reg             inst0_is_branch;
reg             inst0_is_complex;

// Instruction 1
reg             inst1_valid;
reg [6:0]       inst1_cmd;
reg [3:0]       inst1_cmdex;
reg [10:0]      inst1_mutex;
reg             inst1_uses_alu;
reg             inst1_uses_mult;
reg             inst1_uses_div;
reg             inst1_uses_memory;
reg             inst1_is_branch;
reg             inst1_is_complex;

// Execution unit status
reg             alu0_busy;
reg             alu1_busy;
reg             mult_busy;
reg             div_busy;
reg             mem_busy;

// Pipeline mutex state
reg [10:0]      exe0_mutex;
reg [10:0]      exe1_mutex;
reg [10:0]      wr0_mutex;
reg [10:0]      wr1_mutex;

// Outputs
wire            dispatch_inst0;
wire            dispatch_inst1;
wire            inst0_to_alu0;
wire            inst0_to_alu1;
wire            inst1_to_alu0;
wire            inst1_to_alu1;
wire            dual_issue;
wire            stall_dependency;
wire            stall_structural;

//------------------------------------------------------------------------------
// DUT Instantiation
//------------------------------------------------------------------------------

dispatch dut(
    .clk                    (clk),
    .rst_n                  (rst_n),
    .dispatch_reset         (dispatch_reset),

    .inst0_valid            (inst0_valid),
    .inst0_cmd              (inst0_cmd),
    .inst0_cmdex            (inst0_cmdex),
    .inst0_mutex            (inst0_mutex),
    .inst0_uses_alu         (inst0_uses_alu),
    .inst0_uses_mult        (inst0_uses_mult),
    .inst0_uses_div         (inst0_uses_div),
    .inst0_uses_memory      (inst0_uses_memory),
    .inst0_is_branch        (inst0_is_branch),
    .inst0_is_complex       (inst0_is_complex),

    .inst1_valid            (inst1_valid),
    .inst1_cmd              (inst1_cmd),
    .inst1_cmdex            (inst1_cmdex),
    .inst1_mutex            (inst1_mutex),
    .inst1_uses_alu         (inst1_uses_alu),
    .inst1_uses_mult        (inst1_uses_mult),
    .inst1_uses_div         (inst1_uses_div),
    .inst1_uses_memory      (inst1_uses_memory),
    .inst1_is_branch        (inst1_is_branch),
    .inst1_is_complex       (inst1_is_complex),

    .alu0_busy              (alu0_busy),
    .alu1_busy              (alu1_busy),
    .mult_busy              (mult_busy),
    .div_busy               (div_busy),
    .mem_busy               (mem_busy),

    .exe0_mutex             (exe0_mutex),
    .exe1_mutex             (exe1_mutex),
    .wr0_mutex              (wr0_mutex),
    .wr1_mutex              (wr1_mutex),

    .dispatch_inst0         (dispatch_inst0),
    .dispatch_inst1         (dispatch_inst1),
    .inst0_to_alu0          (inst0_to_alu0),
    .inst0_to_alu1          (inst0_to_alu1),
    .inst1_to_alu0          (inst1_to_alu0),
    .inst1_to_alu1          (inst1_to_alu1),
    .dual_issue             (dual_issue),
    .stall_dependency       (stall_dependency),
    .stall_structural       (stall_structural)
);

//------------------------------------------------------------------------------
// Test Tasks
//------------------------------------------------------------------------------

task reset_inputs;
begin
    dispatch_reset = 0;
    inst0_valid = 0;
    inst0_cmd = `CMD_NULL;
    inst0_cmdex = 0;
    inst0_mutex = 0;
    inst0_uses_alu = 0;
    inst0_uses_mult = 0;
    inst0_uses_div = 0;
    inst0_uses_memory = 0;
    inst0_is_branch = 0;
    inst0_is_complex = 0;

    inst1_valid = 0;
    inst1_cmd = `CMD_NULL;
    inst1_cmdex = 0;
    inst1_mutex = 0;
    inst1_uses_alu = 0;
    inst1_uses_mult = 0;
    inst1_uses_div = 0;
    inst1_uses_memory = 0;
    inst1_is_branch = 0;
    inst1_is_complex = 0;

    alu0_busy = 0;
    alu1_busy = 0;
    mult_busy = 0;
    div_busy = 0;
    mem_busy = 0;

    exe0_mutex = 0;
    exe1_mutex = 0;
    wr0_mutex = 0;
    wr1_mutex = 0;
end
endtask

task setup_instruction;
input [10:0] inst_num;      // 0 or 1
input [6:0]  cmd;
input [10:0] mutex;
input        uses_alu;
input        uses_mult;
input        uses_div;
input        uses_mem;
input        is_branch;
input        is_complex;
begin
    if (inst_num == 0) begin
        inst0_valid = 1;
        inst0_cmd = cmd;
        inst0_mutex = mutex;
        inst0_uses_alu = uses_alu;
        inst0_uses_mult = uses_mult;
        inst0_uses_div = uses_div;
        inst0_uses_memory = uses_mem;
        inst0_is_branch = is_branch;
        inst0_is_complex = is_complex;
    end else begin
        inst1_valid = 1;
        inst1_cmd = cmd;
        inst1_mutex = mutex;
        inst1_uses_alu = uses_alu;
        inst1_uses_mult = uses_mult;
        inst1_uses_div = uses_div;
        inst1_uses_memory = uses_mem;
        inst1_is_branch = is_branch;
        inst1_is_complex = is_complex;
    end
end
endtask

//------------------------------------------------------------------------------
// Test Sequences
//------------------------------------------------------------------------------

integer test_num;
integer pass_count;
integer fail_count;

initial begin
    $display("========================================");
    $display("Dispatch Unit Test Bench");
    $display("========================================");

    test_num = 0;
    pass_count = 0;
    fail_count = 0;

    reset_inputs();
    @(posedge rst_n);
    @(posedge clk);

    //--------------------------------------------------------------------------
    // Test 1: Independent ALU operations (should dual-issue)
    //--------------------------------------------------------------------------
    test_num = test_num + 1;
    $display("\nTest %0d: Independent ALU operations", test_num);
    reset_inputs();
    // ADD EAX, EBX (writes EAX, reads EBX)
    setup_instruction(0, `CMD_ADD, 11'b00000000001, 1, 0, 0, 0, 0, 0); // EAX mutex
    // XOR ECX, EDX (writes ECX, reads EDX)
    setup_instruction(1, `CMD_XOR, 11'b00000000010, 1, 0, 0, 0, 0, 0); // ECX mutex
    @(posedge clk);
    #1;
    if (dual_issue && dispatch_inst0 && dispatch_inst1) begin
        $display("  PASS: Both instructions dispatched");
        pass_count = pass_count + 1;
    end else begin
        $display("  FAIL: Expected dual-issue, got dispatch_inst0=%b dispatch_inst1=%b",
                 dispatch_inst0, dispatch_inst1);
        fail_count = fail_count + 1;
    end

    //--------------------------------------------------------------------------
    // Test 2: Register dependency (should NOT dual-issue)
    //--------------------------------------------------------------------------
    test_num = test_num + 1;
    $display("\nTest %0d: Register dependency (RAW hazard)", test_num);
    reset_inputs();
    // ADD EAX, EBX (writes EAX)
    setup_instruction(0, `CMD_ADD, 11'b00000000001, 1, 0, 0, 0, 0, 0); // EAX mutex
    // SUB EAX, ECX (reads/writes EAX)
    setup_instruction(1, `CMD_SUB, 11'b00000000001, 1, 0, 0, 0, 0, 0); // EAX mutex
    @(posedge clk);
    #1;
    if (!dual_issue && dispatch_inst0 && !dispatch_inst1) begin
        $display("  PASS: Only inst0 dispatched (dependency detected)");
        pass_count = pass_count + 1;
    end else begin
        $display("  FAIL: Expected single-issue, got dispatch_inst0=%b dispatch_inst1=%b",
                 dispatch_inst0, dispatch_inst1);
        fail_count = fail_count + 1;
    end

    //--------------------------------------------------------------------------
    // Test 3: Resource conflict - both need multiplier
    //--------------------------------------------------------------------------
    test_num = test_num + 1;
    $display("\nTest %0d: Resource conflict (both need multiplier)", test_num);
    reset_inputs();
    // MUL EAX, EBX
    setup_instruction(0, `CMD_ADD, 11'b00000000001, 0, 1, 0, 0, 0, 0);
    // MUL ECX, EDX
    setup_instruction(1, `CMD_ADD, 11'b00000000010, 0, 1, 0, 0, 0, 0);
    @(posedge clk);
    #1;
    if (!dual_issue && dispatch_inst0 && !dispatch_inst1) begin
        $display("  PASS: Only inst0 dispatched (resource conflict)");
        pass_count = pass_count + 1;
    end else begin
        $display("  FAIL: Expected single-issue, got dispatch_inst0=%b dispatch_inst1=%b",
                 dispatch_inst0, dispatch_inst1);
        fail_count = fail_count + 1;
    end

    //--------------------------------------------------------------------------
    // Test 4: Branch instruction (must execute alone)
    //--------------------------------------------------------------------------
    test_num = test_num + 1;
    $display("\nTest %0d: Branch instruction (no dual-issue)", test_num);
    reset_inputs();
    // JMP (branch)
    setup_instruction(0, `CMD_ADD, 11'b00000000000, 0, 0, 0, 0, 1, 0);
    // ADD EAX, EBX
    setup_instruction(1, `CMD_ADD, 11'b00000000001, 1, 0, 0, 0, 0, 0);
    @(posedge clk);
    #1;
    if (!dual_issue && dispatch_inst0 && !dispatch_inst1) begin
        $display("  PASS: Only branch dispatched");
        pass_count = pass_count + 1;
    end else begin
        $display("  FAIL: Expected single-issue, got dispatch_inst0=%b dispatch_inst1=%b",
                 dispatch_inst0, dispatch_inst1);
        fail_count = fail_count + 1;
    end

    //--------------------------------------------------------------------------
    // Test 5: Pipeline dependency (in-flight instruction)
    //--------------------------------------------------------------------------
    test_num = test_num + 1;
    $display("\nTest %0d: Pipeline dependency (in-flight writes EAX)", test_num);
    reset_inputs();
    exe0_mutex = 11'b00000000001; // In-flight instruction writes EAX
    // ADD EAX, EBX (also writes EAX)
    setup_instruction(0, `CMD_ADD, 11'b00000000001, 1, 0, 0, 0, 0, 0);
    @(posedge clk);
    #1;
    if (!dispatch_inst0 && stall_dependency) begin
        $display("  PASS: Instruction stalled (pipeline dependency)");
        pass_count = pass_count + 1;
    end else begin
        $display("  FAIL: Expected stall, got dispatch_inst0=%b stall_dependency=%b",
                 dispatch_inst0, stall_dependency);
        fail_count = fail_count + 1;
    end

    //--------------------------------------------------------------------------
    // Test 6: Memory operations (should NOT dual-issue)
    //--------------------------------------------------------------------------
    test_num = test_num + 1;
    $display("\nTest %0d: Memory operations (no dual-issue)", test_num);
    reset_inputs();
    // MOV [EAX], EBX
    setup_instruction(0, `CMD_MOV, 11'b00000000001, 1, 0, 0, 1, 0, 0);
    // MOV ECX, [EDX]
    setup_instruction(1, `CMD_MOV, 11'b00000000010, 1, 0, 0, 1, 0, 0);
    @(posedge clk);
    #1;
    if (!dual_issue && dispatch_inst0 && !dispatch_inst1) begin
        $display("  PASS: Only one memory op dispatched");
        pass_count = pass_count + 1;
    end else begin
        $display("  FAIL: Expected single-issue, got dispatch_inst0=%b dispatch_inst1=%b",
                 dispatch_inst0, dispatch_inst1);
        fail_count = fail_count + 1;
    end

    //--------------------------------------------------------------------------
    // Test 7: I/O dependency check
    //--------------------------------------------------------------------------
    test_num = test_num + 1;
    $display("\nTest %0d: I/O dependency (both access I/O)", test_num);
    reset_inputs();
    // IN AL, DX (I/O read)
    setup_instruction(0, `CMD_ADD, 11'b10000000001, 1, 0, 0, 0, 0, 0); // I/O bit + EAX
    // OUT DX, AL (I/O write)
    setup_instruction(1, `CMD_ADD, 11'b10000000001, 1, 0, 0, 0, 0, 0); // I/O bit + EAX
    @(posedge clk);
    #1;
    if (!dual_issue && dispatch_inst0 && !dispatch_inst1) begin
        $display("  PASS: I/O dependency detected");
        pass_count = pass_count + 1;
    end else begin
        $display("  FAIL: Expected single-issue, got dispatch_inst0=%b dispatch_inst1=%b",
                 dispatch_inst0, dispatch_inst1);
        fail_count = fail_count + 1;
    end

    //--------------------------------------------------------------------------
    // Test 8: ALU busy (structural hazard)
    //--------------------------------------------------------------------------
    test_num = test_num + 1;
    $display("\nTest %0d: ALU busy (structural hazard)", test_num);
    reset_inputs();
    alu0_busy = 1;
    alu1_busy = 1;
    // ADD EAX, EBX
    setup_instruction(0, `CMD_ADD, 11'b00000000001, 1, 0, 0, 0, 0, 0);
    @(posedge clk);
    #1;
    if (!dispatch_inst0 && stall_structural) begin
        $display("  PASS: Stalled due to ALU busy");
        pass_count = pass_count + 1;
    end else begin
        $display("  FAIL: Expected stall, got dispatch_inst0=%b stall_structural=%b",
                 dispatch_inst0, stall_structural);
        fail_count = fail_count + 1;
    end

    //--------------------------------------------------------------------------
    // Summary
    //--------------------------------------------------------------------------
    #50;
    $display("\n========================================");
    $display("Test Summary");
    $display("========================================");
    $display("Total tests: %0d", test_num);
    $display("Passed:      %0d", pass_count);
    $display("Failed:      %0d", fail_count);

    if (fail_count == 0) begin
        $display("\nALL TESTS PASSED!");
    end else begin
        $display("\nSOME TESTS FAILED!");
    end
    $display("========================================\n");

    $finish;
end

//------------------------------------------------------------------------------
// Waveform Dump
//------------------------------------------------------------------------------

initial begin
    $dumpfile("tb_dispatch.vcd");
    $dumpvars(0, tb_dispatch);
end

endmodule
