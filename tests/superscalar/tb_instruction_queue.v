//==============================================================================
// Test Bench for Instruction Queue
//
// Tests the 4-entry FIFO instruction queue used for superscalar dispatch
//
// Based on SUPERSCALAR_TEST_PLAN.md Section 1: Instruction Queue Tests
//==============================================================================

`timescale 1ns/1ps

module tb_instruction_queue;

//------------------------------------------------------------------------------
// Clock and Reset
//------------------------------------------------------------------------------
reg clk;
reg rst_n;

//------------------------------------------------------------------------------
// Instruction Queue Inputs
//------------------------------------------------------------------------------
reg             enqueue_valid;
reg [6:0]       enqueue_cmd;
reg [10:0]      enqueue_mutex;
reg [31:0]      enqueue_operand1;
reg [31:0]      enqueue_operand2;
reg [5:0]       enqueue_modregrm;

reg             dequeue_ready;  // Dispatch ready to consume
reg             queue_reset;    // Pipeline flush

//------------------------------------------------------------------------------
// Instruction Queue Outputs
//------------------------------------------------------------------------------
wire            queue_full;
wire            queue_empty;
wire [2:0]      queue_count;

wire            inst0_valid;
wire [6:0]      inst0_cmd;
wire [10:0]     inst0_mutex;
wire [31:0]     inst0_operand1;
wire [31:0]     inst0_operand2;
wire [5:0]      inst0_modregrm;

wire            inst1_valid;
wire [6:0]      inst1_cmd;
wire [10:0]     inst1_mutex;
wire [31:0]     inst1_operand1;
wire [31:0]     inst1_operand2;
wire [5:0]      inst1_modregrm;

//------------------------------------------------------------------------------
// DUT Instantiation
//------------------------------------------------------------------------------
instruction_queue dut (
    .clk(clk),
    .rst_n(rst_n),

    // Enqueue interface (from READ stage)
    .enqueue_valid(enqueue_valid),
    .enqueue_cmd(enqueue_cmd),
    .enqueue_mutex(enqueue_mutex),
    .enqueue_operand1(enqueue_operand1),
    .enqueue_operand2(enqueue_operand2),
    .enqueue_modregrm(enqueue_modregrm),

    // Dequeue interface (to DISPATCH)
    .dequeue_ready(dequeue_ready),

    // Status
    .queue_full(queue_full),
    .queue_empty(queue_empty),
    .queue_count(queue_count),

    // Outputs (top 2 instructions)
    .inst0_valid(inst0_valid),
    .inst0_cmd(inst0_cmd),
    .inst0_mutex(inst0_mutex),
    .inst0_operand1(inst0_operand1),
    .inst0_operand2(inst0_operand2),
    .inst0_modregrm(inst0_modregrm),

    .inst1_valid(inst1_valid),
    .inst1_cmd(inst1_cmd),
    .inst1_mutex(inst1_mutex),
    .inst1_operand1(inst1_operand1),
    .inst1_operand2(inst1_operand2),
    .inst1_modregrm(inst1_modregrm),

    // Control
    .queue_reset(queue_reset)
);

//------------------------------------------------------------------------------
// Clock Generation (100 MHz)
//------------------------------------------------------------------------------
initial begin
    clk = 0;
    forever #5 clk = ~clk;  // 10ns period
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
    enqueue_valid = 0;
    dequeue_ready = 0;
    queue_reset = 0;
    enqueue_cmd = 0;
    enqueue_mutex = 0;
    enqueue_operand1 = 0;
    enqueue_operand2 = 0;
    enqueue_modregrm = 0;
    repeat(2) @(posedge clk);
    rst_n = 1;
    @(posedge clk);
end
endtask

task enqueue_instruction(
    input [6:0] cmd,
    input [10:0] mutex,
    input [31:0] op1,
    input [31:0] op2,
    input [5:0] modregrm
);
begin
    @(posedge clk);
    enqueue_valid = 1;
    enqueue_cmd = cmd;
    enqueue_mutex = mutex;
    enqueue_operand1 = op1;
    enqueue_operand2 = op2;
    enqueue_modregrm = modregrm;
    @(posedge clk);
    enqueue_valid = 0;
end
endtask

task dequeue_instructions(input integer count);
begin
    @(posedge clk);
    dequeue_ready = 1;
    @(posedge clk);
    dequeue_ready = 0;
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
    $display("Instruction Queue Test Bench");
    $display("========================================");

    // Initialize
    reset_dut();

    //--------------------------------------------------------------------------
    // Test 1.1: Basic Enqueue/Dequeue
    //--------------------------------------------------------------------------
    $display("\nTest 1.1: Basic Enqueue/Dequeue");
    reset_dut();

    // Initially empty
    check_result(1, "Queue starts empty", 1, queue_empty);
    check_result(2, "Queue count is 0", 0, queue_count);

    // Enqueue 4 instructions
    enqueue_instruction(7'd10, 11'h001, 32'h100, 32'h200, 6'b000_000);
    enqueue_instruction(7'd20, 11'h002, 32'h300, 32'h400, 6'b011_011);
    enqueue_instruction(7'd30, 11'h004, 32'h500, 32'h600, 6'b001_001);
    enqueue_instruction(7'd40, 11'h008, 32'h700, 32'h800, 6'b010_010);

    @(posedge clk);
    check_result(3, "Queue full after 4 enqueues", 1, queue_full);
    check_result(4, "Queue count is 4", 4, queue_count);

    // Verify first instruction
    check_result(5, "inst0_valid", 1, inst0_valid);
    check_result(6, "inst0_cmd", 7'd10, inst0_cmd);
    check_result(7, "inst0_modregrm", 6'b000_000, inst0_modregrm);

    // Verify second instruction
    check_result(8, "inst1_valid", 1, inst1_valid);
    check_result(9, "inst1_cmd", 7'd20, inst1_cmd);
    check_result(10, "inst1_modregrm", 6'b011_011, inst1_modregrm);

    // Dequeue 2 instructions (dual-issue)
    dequeue_instructions(2);

    @(posedge clk);
    check_result(11, "Queue count is 2 after dequeue", 2, queue_count);
    check_result(12, "New inst0_cmd", 7'd30, inst0_cmd);
    check_result(13, "New inst1_cmd", 7'd40, inst1_cmd);

    // Dequeue remaining 2
    dequeue_instructions(2);

    @(posedge clk);
    check_result(14, "Queue empty after all dequeued", 1, queue_empty);

    //--------------------------------------------------------------------------
    // Test 1.2: Queue Reset
    //--------------------------------------------------------------------------
    $display("\nTest 1.2: Queue Reset");
    reset_dut();

    // Fill queue with 3 instructions
    enqueue_instruction(7'd11, 11'h010, 32'h111, 32'h222, 6'b100_100);
    enqueue_instruction(7'd12, 11'h020, 32'h333, 32'h444, 6'b101_101);
    enqueue_instruction(7'd13, 11'h040, 32'h555, 32'h666, 6'b110_110);

    @(posedge clk);
    check_result(15, "Queue has 3 instructions", 3, queue_count);

    // Assert queue_reset
    @(posedge clk);
    queue_reset = 1;
    @(posedge clk);
    queue_reset = 0;

    @(posedge clk);
    check_result(16, "Queue empty after reset", 1, queue_empty);
    check_result(17, "inst0_valid is 0 after reset", 0, inst0_valid);
    check_result(18, "inst1_valid is 0 after reset", 0, inst1_valid);

    //--------------------------------------------------------------------------
    // Test 1.3: ModR/M Tracking
    //--------------------------------------------------------------------------
    $display("\nTest 1.3: ModR/M Tracking");
    reset_dut();

    // Enqueue with specific ModR/M values
    // MOV EAX, 1 (modregrm = 6'b000_000 for EAX)
    enqueue_instruction(7'd50, 11'h001, 32'h1, 32'h0, 6'b000_000);
    // MOV EBX, 2 (modregrm = 6'b011_011 for EBX)
    enqueue_instruction(7'd51, 11'h008, 32'h2, 32'h0, 6'b011_011);

    @(posedge clk);
    check_result(19, "inst0_modregrm tracks EAX", 6'b000_000, inst0_modregrm);
    check_result(20, "inst1_modregrm tracks EBX", 6'b011_011, inst1_modregrm);

    //--------------------------------------------------------------------------
    // Test 1.4: Queue Stall (Backpressure)
    //--------------------------------------------------------------------------
    $display("\nTest 1.4: Queue Stall");
    reset_dut();

    // Fill queue to capacity (4 instructions)
    enqueue_instruction(7'd60, 11'h001, 32'h0, 32'h0, 6'b000_000);
    enqueue_instruction(7'd61, 11'h002, 32'h0, 32'h0, 6'b001_001);
    enqueue_instruction(7'd62, 11'h004, 32'h0, 32'h0, 6'b010_010);
    enqueue_instruction(7'd63, 11'h008, 32'h0, 32'h0, 6'b011_011);

    @(posedge clk);
    check_result(21, "Queue full with 4 instructions", 1, queue_full);
    check_result(22, "Queue count is 4", 4, queue_count);

    // Try to enqueue 5th instruction (should not be accepted)
    enqueue_instruction(7'd64, 11'h010, 32'h0, 32'h0, 6'b100_100);

    @(posedge clk);
    check_result(23, "Queue still has 4 (5th rejected)", 4, queue_count);
    check_result(24, "Queue still full", 1, queue_full);

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
// Waveform Dumping (for GTKWave)
//------------------------------------------------------------------------------
initial begin
    $dumpfile("tb_instruction_queue.vcd");
    $dumpvars(0, tb_instruction_queue);
end

endmodule
