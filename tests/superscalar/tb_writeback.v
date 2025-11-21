//==============================================================================
// Test Bench for Dual Writeback
//
// Tests the dual write port capability of the register file
//
// Based on SUPERSCALAR_TEST_PLAN.md Section 4: Writeback Tests
//==============================================================================

`timescale 1ns/1ps

module tb_writeback;

//------------------------------------------------------------------------------
// Clock and Reset
//------------------------------------------------------------------------------
reg clk;
reg rst_n;

//------------------------------------------------------------------------------
// Write Port 0 (Primary - from ALU0)
//------------------------------------------------------------------------------
reg             w_write_regrm;
reg [2:0]       w_index;         // Which register (0-7)
reg [31:0]      w_result;

//------------------------------------------------------------------------------
// Write Port 1 (Secondary - from ALU1)
//------------------------------------------------------------------------------
reg             wr1_valid;
reg             wr1_eax;
reg             wr1_ecx;
reg             wr1_edx;
reg             wr1_ebx;
reg             wr1_esp;
reg             wr1_ebp;
reg             wr1_esi;
reg             wr1_edi;
reg [31:0]      wr1_result;

//------------------------------------------------------------------------------
// Exception Restore (for ESP)
//------------------------------------------------------------------------------
reg             exc_restore_esp;
reg [31:0]      wr_esp_prev;

//------------------------------------------------------------------------------
// Register File Outputs (for verification)
//------------------------------------------------------------------------------
wire [31:0]     eax;
wire [31:0]     ecx;
wire [31:0]     edx;
wire [31:0]     ebx;
wire [31:0]     esp;
wire [31:0]     ebp;
wire [31:0]     esi;
wire [31:0]     edi;

//------------------------------------------------------------------------------
// Register to Index
//------------------------------------------------------------------------------
wire [31:0]     eax_to_reg = eax;
wire [31:0]     ecx_to_reg = ecx;
wire [31:0]     edx_to_reg = edx;
wire [31:0]     ebx_to_reg = ebx;
wire [31:0]     esp_to_reg = esp;
wire [31:0]     ebp_to_reg = ebp;
wire [31:0]     esi_to_reg = esi;
wire [31:0]     edi_to_reg = edi;

//------------------------------------------------------------------------------
// DUT: write_register module
//------------------------------------------------------------------------------
write_register dut (
    .clk(clk),
    .rst_n(rst_n),

    // Port 0 (primary)
    .w_write_regrm(w_write_regrm),
    .w_index(w_index),
    .eax_value(w_result),      // For simplicity, using w_result for all
    .ecx_value(w_result),
    .edx_value(w_result),
    .ebx_value(w_result),
    .esp_value(w_result),
    .ebp_value(w_result),
    .esi_value(w_result),
    .edi_value(w_result),

    // Port 1 (secondary - dual writeback)
    .wr1_valid(wr1_valid),
    .wr1_result(wr1_result),
    .wr1_eax(wr1_eax),
    .wr1_ecx(wr1_ecx),
    .wr1_edx(wr1_edx),
    .wr1_ebx(wr1_ebx),
    .wr1_esp(wr1_esp),
    .wr1_ebp(wr1_ebp),
    .wr1_esi(wr1_esi),
    .wr1_edi(wr1_edi),

    // Exception restore
    .exc_restore_esp(exc_restore_esp),
    .wr_esp_prev(wr_esp_prev),

    // Register outputs
    .eax(eax),
    .ecx(ecx),
    .edx(edx),
    .ebx(ebx),
    .esp(esp),
    .ebp(ebp),
    .esi(esi),
    .edi(edi),

    // Feedthrough (for pipeline)
    .eax_to_reg(eax_to_reg),
    .ecx_to_reg(ecx_to_reg),
    .edx_to_reg(edx_to_reg),
    .ebx_to_reg(ebx_to_reg),
    .esp_to_reg(esp_to_reg),
    .ebp_to_reg(ebp_to_reg),
    .esi_to_reg(esi_to_reg),
    .edi_to_reg(edi_to_reg)
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
    w_write_regrm = 0;
    w_index = 0;
    w_result = 0;
    wr1_valid = 0;
    wr1_eax = 0;
    wr1_ecx = 0;
    wr1_edx = 0;
    wr1_ebx = 0;
    wr1_esp = 0;
    wr1_ebp = 0;
    wr1_esi = 0;
    wr1_edi = 0;
    wr1_result = 0;
    exc_restore_esp = 0;
    wr_esp_prev = 0;
    repeat(2) @(posedge clk);
    rst_n = 1;
    @(posedge clk);
end
endtask

task write_port0(
    input [2:0] index,
    input [31:0] value
);
begin
    @(posedge clk);
    w_write_regrm = 1;
    w_index = index;
    w_result = value;
    @(posedge clk);
    w_write_regrm = 0;
end
endtask

task write_port1_eax(input [31:0] value);
begin
    @(posedge clk);
    wr1_valid = 1;
    wr1_eax = 1;
    wr1_result = value;
    @(posedge clk);
    wr1_valid = 0;
    wr1_eax = 0;
end
endtask

task write_port1_ebx(input [31:0] value);
begin
    @(posedge clk);
    wr1_valid = 1;
    wr1_ebx = 1;
    wr1_result = value;
    @(posedge clk);
    wr1_valid = 0;
    wr1_ebx = 0;
end
endtask

task write_dual(
    input [2:0] p0_index,
    input [31:0] p0_value,
    input [2:0] p1_reg,    // 0=EAX, 1=ECX, 2=EDX, 3=EBX, etc.
    input [31:0] p1_value
);
begin
    @(posedge clk);
    // Port 0
    w_write_regrm = 1;
    w_index = p0_index;
    w_result = p0_value;
    // Port 1
    wr1_valid = 1;
    wr1_eax = (p1_reg == 0);
    wr1_ecx = (p1_reg == 1);
    wr1_edx = (p1_reg == 2);
    wr1_ebx = (p1_reg == 3);
    wr1_esp = (p1_reg == 4);
    wr1_ebp = (p1_reg == 5);
    wr1_esi = (p1_reg == 6);
    wr1_edi = (p1_reg == 7);
    wr1_result = p1_value;
    @(posedge clk);
    w_write_regrm = 0;
    wr1_valid = 0;
    wr1_eax = 0;
    wr1_ecx = 0;
    wr1_edx = 0;
    wr1_ebx = 0;
    wr1_esp = 0;
    wr1_ebp = 0;
    wr1_esi = 0;
    wr1_edi = 0;
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

//------------------------------------------------------------------------------
// Test Scenarios
//------------------------------------------------------------------------------

initial begin
    $display("========================================");
    $display("Dual Writeback Test Bench");
    $display("========================================");

    reset_dut();

    //--------------------------------------------------------------------------
    // Test 4.1: Dual Writeback - Different Registers
    //--------------------------------------------------------------------------
    $display("\nTest 4.1: Dual Writeback - Different Registers");
    reset_dut();

    // Write to EAX (index 0) and EBX (index 3) simultaneously
    write_dual(3'd0, 32'h1111_1111, 3'd3, 32'h2222_2222);

    @(posedge clk);
    check_result(1, "Port 0 writes EAX", 32'h1111_1111, eax);
    check_result(2, "Port 1 writes EBX", 32'h2222_2222, ebx);

    //--------------------------------------------------------------------------
    // Test 4.2: Write Priority (Port 0 > Port 1)
    //--------------------------------------------------------------------------
    $display("\nTest 4.2: Write Priority - Port 0 Wins");
    reset_dut();

    // Both ports try to write EAX (should never happen, but test safety)
    @(posedge clk);
    w_write_regrm = 1;
    w_index = 3'd0;  // EAX
    w_result = 32'h1000;
    wr1_valid = 1;
    wr1_eax = 1;
    wr1_result = 32'h2000;
    @(posedge clk);
    w_write_regrm = 0;
    wr1_valid = 0;
    wr1_eax = 0;

    @(posedge clk);
    check_result(3, "Port 0 takes priority", 32'h1000, eax);

    //--------------------------------------------------------------------------
    // Test 4.3: Port 0 Only
    //--------------------------------------------------------------------------
    $display("\nTest 4.3: Port 0 Only");
    reset_dut();

    write_port0(3'd1, 32'h3333_3333);  // ECX

    @(posedge clk);
    check_result(4, "Port 0 writes ECX", 32'h3333_3333, ecx);
    check_result(5, "EAX unchanged", 32'h0000_0000, eax);

    //--------------------------------------------------------------------------
    // Test 4.4: Port 1 Only
    //--------------------------------------------------------------------------
    $display("\nTest 4.4: Port 1 Only");
    reset_dut();

    write_port1_ebx(32'h4444_4444);

    @(posedge clk);
    check_result(6, "Port 1 writes EBX", 32'h4444_4444, ebx);
    check_result(7, "Other registers unchanged", 32'h0000_0000, eax);

    //--------------------------------------------------------------------------
    // Test 4.5: All 8 Registers via Port 1
    //--------------------------------------------------------------------------
    $display("\nTest 4.5: All Registers via Port 1");
    reset_dut();

    // EAX
    write_dual(3'd7, 32'hAAAA_0000, 3'd0, 32'hAAAA_AAAA);  // Also write EDI
    @(posedge clk);
    check_result(8, "EAX via Port 1", 32'hAAAA_AAAA, eax);

    // ECX
    write_dual(3'd7, 32'hBBBB_0000, 3'd1, 32'hBBBB_BBBB);
    @(posedge clk);
    check_result(9, "ECX via Port 1", 32'hBBBB_BBBB, ecx);

    // EDX
    write_dual(3'd7, 32'hCCCC_0000, 3'd2, 32'hCCCC_CCCC);
    @(posedge clk);
    check_result(10, "EDX via Port 1", 32'hCCCC_CCCC, edx);

    // EBX
    write_dual(3'd7, 32'hDDDD_0000, 3'd3, 32'hDDDD_DDDD);
    @(posedge clk);
    check_result(11, "EBX via Port 1", 32'hDDDD_DDDD, ebx);

    // ESP
    write_dual(3'd7, 32'hEEEE_0000, 3'd4, 32'hEEEE_EEEE);
    @(posedge clk);
    check_result(12, "ESP via Port 1", 32'hEEEE_EEEE, esp);

    // EBP
    write_dual(3'd7, 32'hFFFF_0000, 3'd5, 32'hFFFF_FFFF);
    @(posedge clk);
    check_result(13, "EBP via Port 1", 32'hFFFF_FFFF, ebp);

    // ESI
    write_dual(3'd0, 32'h1111_0000, 3'd6, 32'h1111_1111);
    @(posedge clk);
    check_result(14, "ESI via Port 1", 32'h1111_1111, esi);

    // EDI
    write_dual(3'd0, 32'h2222_0000, 3'd7, 32'h2222_2222);
    @(posedge clk);
    check_result(15, "EDI via Port 1", 32'h2222_2222, edi);

    //--------------------------------------------------------------------------
    // Test 4.6: ESP Exception Priority
    //--------------------------------------------------------------------------
    $display("\nTest 4.6: ESP Exception Restore Priority");
    reset_dut();

    // Set ESP to some value
    write_port0(3'd4, 32'h1000_0000);
    @(posedge clk);

    // Exception restore should override Port 1 write
    @(posedge clk);
    exc_restore_esp = 1;
    wr_esp_prev = 32'hFFFF_0000;
    wr1_valid = 1;
    wr1_esp = 1;
    wr1_result = 32'h2000_0000;
    @(posedge clk);
    exc_restore_esp = 0;
    wr1_valid = 0;
    wr1_esp = 0;

    @(posedge clk);
    check_result(16, "Exception restore takes priority", 32'hFFFF_0000, esp);

    //--------------------------------------------------------------------------
    // Test 4.7: Sequential Dual Writes
    //--------------------------------------------------------------------------
    $display("\nTest 4.7: Sequential Dual Writes");
    reset_dut();

    // Cycle 1: EAX and EBX
    write_dual(3'd0, 32'h0000_0001, 3'd3, 32'h0000_0002);
    @(posedge clk);

    // Cycle 2: ECX and EDX
    write_dual(3'd1, 32'h0000_0003, 3'd2, 32'h0000_0004);
    @(posedge clk);

    check_result(17, "EAX from cycle 1", 32'h0000_0001, eax);
    check_result(18, "EBX from cycle 1", 32'h0000_0002, ebx);
    check_result(19, "ECX from cycle 2", 32'h0000_0003, ecx);
    check_result(20, "EDX from cycle 2", 32'h0000_0004, edx);

    //--------------------------------------------------------------------------
    // Test 4.8: Overwrite Register
    //--------------------------------------------------------------------------
    $display("\nTest 4.8: Overwrite Register");
    reset_dut();

    // Write initial value
    write_port0(3'd0, 32'hDEAD_BEEF);
    @(posedge clk);
    check_result(21, "Initial value", 32'hDEAD_BEEF, eax);

    // Overwrite via Port 1
    write_port1_eax(32'hCAFE_BABE);
    @(posedge clk);
    check_result(22, "Overwritten value", 32'hCAFE_BABE, eax);

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
    $dumpfile("tb_writeback.vcd");
    $dumpvars(0, tb_writeback);
end

endmodule
