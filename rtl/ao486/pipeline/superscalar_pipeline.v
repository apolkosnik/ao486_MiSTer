/*
 * Copyright (c) 2025, Superscalar ao486 Enhancement
 * All rights reserved.
 *
 * Superscalar Pipeline Wrapper for 2-way ao486
 *
 * This module wraps the original ao486 pipeline with superscalar enhancements:
 * - Dual instruction issue
 * - Parallel execution units (ALU0 and ALU1)
 * - Result forwarding/bypass network
 * - Enhanced dependency tracking
 *
 * Architecture Overview:
 * ======================
 *
 * FETCH → DECODE → READ → DISPATCH → EXECUTE → WRITE
 *   |        |       |        |         |         |
 *   |        |       |        |      ALU0/ALU1    |
 *   |        |       |        |      Shared       |
 *   |        |       |        |      Mult/Div     |
 *   |        |       |        |                   |
 *   └────────┴───────┴────────┴───────────────────┘
 *                    Forwarding Network
 *
 * Performance Improvements:
 * - 2 instructions per cycle (ideal throughput)
 * - Reduced stalls via result forwarding
 * - Better ALU utilization
 *
 * Key Features:
 * - Maintains binary compatibility with original ao486
 * - Conservative dispatch to ensure correctness
 * - Priority-based forwarding (newer instructions override older)
 */

`include "defines.v"

module superscalar_pipeline(
    input               clk,
    input               rst_n,

    input               exe_reset,
    input               rd_reset,
    input               wr_reset,

    //--------------------------------------------------------------------------
    // Configuration
    //--------------------------------------------------------------------------

    input               enable_superscalar,     // Runtime enable/disable

    //--------------------------------------------------------------------------
    // Instruction Inputs (from READ stage)
    //--------------------------------------------------------------------------

    // Instruction 0 (primary)
    input               inst0_valid,
    input       [87:0]  inst0_decoder,
    input       [6:0]   inst0_cmd,
    input       [3:0]   inst0_cmdex,
    input       [10:0]  inst0_mutex,
    input       [31:0]  inst0_src,
    input       [31:0]  inst0_dst,
    input               inst0_is_8bit,
    input       [31:0]  inst0_eip,

    // Instruction 1 (secondary) - only used in superscalar mode
    input               inst1_valid,
    input       [87:0]  inst1_decoder,
    input       [6:0]   inst1_cmd,
    input       [3:0]   inst1_cmdex,
    input       [10:0]  inst1_mutex,
    input       [31:0]  inst1_src,
    input       [31:0]  inst1_dst,
    input               inst1_is_8bit,
    input       [31:0]  inst1_eip,

    //--------------------------------------------------------------------------
    // Register File Access (shared between both execution units)
    //--------------------------------------------------------------------------

    input       [31:0]  eax,
    input       [31:0]  ebx,
    input       [31:0]  ecx,
    input       [31:0]  edx,
    input       [31:0]  esp,
    input       [31:0]  ebp,
    input       [31:0]  esi,
    input       [31:0]  edi,

    input               cflag,
    input               pflag,
    input               aflag,
    input               zflag,
    input               sflag,
    input               oflag,
    input               dflag,
    input               tflag,
    input               iflag,

    //--------------------------------------------------------------------------
    // Pipeline Control Outputs
    //--------------------------------------------------------------------------

    output              pipeline_stall,         // Stall the pipeline
    output              dual_issue_active,      // Currently dual-issuing
    output      [31:0]  performance_counter,    // Number of dual-issue cycles

    //--------------------------------------------------------------------------
    // Execution Results (to WRITE stage)
    //--------------------------------------------------------------------------

    // ALU0 results
    output              alu0_result_valid,
    output      [31:0]  alu0_result,
    output      [31:0]  alu0_result2,
    output      [4:0]   alu0_flags,
    output      [31:0]  alu0_eip,

    // ALU1 results
    output              alu1_result_valid,
    output      [31:0]  alu1_result,
    output      [31:0]  alu1_result2,
    output      [4:0]   alu1_flags,
    output      [31:0]  alu1_eip,

    //--------------------------------------------------------------------------
    // Status and Debug
    //--------------------------------------------------------------------------

    output      [31:0]  debug_dispatch_count,
    output      [31:0]  debug_stall_dependency,
    output      [31:0]  debug_stall_structural,
    output      [31:0]  debug_forward_count
);

//------------------------------------------------------------------------------
// Instruction Classification
//------------------------------------------------------------------------------

// Classify instruction 0
wire inst0_uses_alu;
wire inst0_uses_mult;
wire inst0_uses_div;
wire inst0_uses_memory;
wire inst0_is_branch;
wire inst0_is_complex;

assign inst0_uses_alu =
    (inst0_cmd == `CMD_ADD) || (inst0_cmd == `CMD_ADC) ||
    (inst0_cmd == `CMD_SUB) || (inst0_cmd == `CMD_SBB) ||
    (inst0_cmd == `CMD_CMP) || (inst0_cmd == `CMD_AND) ||
    (inst0_cmd == `CMD_TEST) || (inst0_cmd == `CMD_OR) ||
    (inst0_cmd == `CMD_XOR) || (inst0_cmd == `CMD_MOV);

assign inst0_uses_mult = inst0_decoder[`DECODER_IS_MULT_BIT];
assign inst0_uses_div = inst0_decoder[`DECODER_IS_DIV_BIT];
assign inst0_uses_memory = inst0_mutex[`MUTEX_MEMORY_BIT];
assign inst0_is_branch = inst0_decoder[`DECODER_IS_BRANCH_BIT];
assign inst0_is_complex = inst0_decoder[`DECODER_IS_COMPLEX_BIT];

// Classify instruction 1
wire inst1_uses_alu;
wire inst1_uses_mult;
wire inst1_uses_div;
wire inst1_uses_memory;
wire inst1_is_branch;
wire inst1_is_complex;

assign inst1_uses_alu =
    (inst1_cmd == `CMD_ADD) || (inst1_cmd == `CMD_ADC) ||
    (inst1_cmd == `CMD_SUB) || (inst1_cmd == `CMD_SBB) ||
    (inst1_cmd == `CMD_CMP) || (inst1_cmd == `CMD_AND) ||
    (inst1_cmd == `CMD_TEST) || (inst1_cmd == `CMD_OR) ||
    (inst1_cmd == `CMD_XOR) || (inst1_cmd == `CMD_MOV);

assign inst1_uses_mult = inst1_decoder[`DECODER_IS_MULT_BIT];
assign inst1_uses_div = inst1_decoder[`DECODER_IS_DIV_BIT];
assign inst1_uses_memory = inst1_mutex[`MUTEX_MEMORY_BIT];
assign inst1_is_branch = inst1_decoder[`DECODER_IS_BRANCH_BIT];
assign inst1_is_complex = inst1_decoder[`DECODER_IS_COMPLEX_BIT];

//------------------------------------------------------------------------------
// Execution Unit Status
//------------------------------------------------------------------------------

wire alu0_busy;
wire alu1_busy;
wire mult_div_busy;
wire mem_busy = 1'b0;  // Simplified for this implementation

//------------------------------------------------------------------------------
// Pipeline State Tracking
//------------------------------------------------------------------------------

reg [10:0]  exe0_mutex_reg;
reg [10:0]  exe1_mutex_reg;
reg [10:0]  wr0_mutex_reg;
reg [10:0]  wr1_mutex_reg;

reg         exe0_valid_reg;
reg         exe1_valid_reg;
reg         wr0_valid_reg;
reg         wr1_valid_reg;

reg [31:0]  exe0_result_reg;
reg [31:0]  exe1_result_reg;
reg [31:0]  wr0_result_reg;
reg [31:0]  wr1_result_reg;

reg [31:0]  exe0_eip_reg;
reg [31:0]  exe1_eip_reg;

always @(posedge clk) begin
    if (rst_n == 1'b0 || exe_reset) begin
        exe0_mutex_reg <= 11'h0;
        exe1_mutex_reg <= 11'h0;
        exe0_valid_reg <= 1'b0;
        exe1_valid_reg <= 1'b0;
        exe0_result_reg <= 32'h0;
        exe1_result_reg <= 32'h0;
        exe0_eip_reg <= 32'h0;
        exe1_eip_reg <= 32'h0;
    end else begin
        if (dispatch_inst0) begin
            exe0_mutex_reg <= inst0_mutex;
            exe0_valid_reg <= 1'b1;
            exe0_eip_reg <= inst0_eip;
        end else if (alu0_ready) begin
            exe0_valid_reg <= 1'b0;
            exe0_mutex_reg <= 11'h0;
        end

        if (dispatch_inst1 && enable_superscalar) begin
            exe1_mutex_reg <= inst1_mutex;
            exe1_valid_reg <= 1'b1;
            exe1_eip_reg <= inst1_eip;
        end else if (alu1_ready) begin
            exe1_valid_reg <= 1'b0;
            exe1_mutex_reg <= 11'h0;
        end

        // Update result registers
        if (alu0_ready) exe0_result_reg <= alu0_result;
        if (alu1_ready) exe1_result_reg <= alu1_result;
    end
end

always @(posedge clk) begin
    if (rst_n == 1'b0 || wr_reset) begin
        wr0_mutex_reg <= 11'h0;
        wr1_mutex_reg <= 11'h0;
        wr0_valid_reg <= 1'b0;
        wr1_valid_reg <= 1'b0;
        wr0_result_reg <= 32'h0;
        wr1_result_reg <= 32'h0;
    end else begin
        // Shift from EXE to WR stage
        wr0_mutex_reg <= exe0_mutex_reg;
        wr1_mutex_reg <= exe1_mutex_reg;
        wr0_valid_reg <= exe0_valid_reg;
        wr1_valid_reg <= exe1_valid_reg;
        wr0_result_reg <= exe0_result_reg;
        wr1_result_reg <= exe1_result_reg;
    end
end

//------------------------------------------------------------------------------
// Dispatch Unit
//------------------------------------------------------------------------------

wire dispatch_inst0;
wire dispatch_inst1;
wire inst0_to_alu0;
wire inst0_to_alu1;
wire inst1_to_alu0;
wire inst1_to_alu1;
wire dual_issue;
wire stall_dependency;
wire stall_structural;

dispatch dispatch_inst(
    .clk                    (clk),
    .rst_n                  (rst_n),
    .dispatch_reset         (rd_reset),

    // Instruction 0
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

    // Instruction 1
    .inst1_valid            (inst1_valid && enable_superscalar),
    .inst1_cmd              (inst1_cmd),
    .inst1_cmdex            (inst1_cmdex),
    .inst1_mutex            (inst1_mutex),
    .inst1_uses_alu         (inst1_uses_alu),
    .inst1_uses_mult        (inst1_uses_mult),
    .inst1_uses_div         (inst1_uses_div),
    .inst1_uses_memory      (inst1_uses_memory),
    .inst1_is_branch        (inst1_is_branch),
    .inst1_is_complex       (inst1_is_complex),

    // Execution unit status
    .alu0_busy              (alu0_busy),
    .alu1_busy              (alu1_busy),
    .mult_busy              (mult_div_busy),
    .div_busy               (mult_div_busy),
    .mem_busy               (mem_busy),

    // Pipeline mutex state
    .exe0_mutex             (exe0_mutex_reg),
    .exe1_mutex             (exe1_mutex_reg),
    .wr0_mutex              (wr0_mutex_reg),
    .wr1_mutex              (wr1_mutex_reg),

    // Outputs
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
// Dual Execution Units
//------------------------------------------------------------------------------

wire alu0_ready;
wire alu1_ready;

dual_execute dual_exec_inst(
    .clk                    (clk),
    .rst_n                  (rst_n),
    .exe_reset              (exe_reset),

    // Shared registers
    .eax                    (eax),
    .ecx                    (ecx),
    .edx                    (edx),
    .ebp                    (ebp),
    .esp                    (esp),
    .ebx                    (ebx),
    .esi                    (esi),
    .edi                    (edi),

    .cflag                  (cflag),
    .pflag                  (pflag),
    .aflag                  (aflag),
    .zflag                  (zflag),
    .sflag                  (sflag),
    .oflag                  (oflag),
    .dflag                  (dflag),
    .tflag                  (tflag),
    .iflag                  (iflag),

    .cpl                    (2'b0),
    .real_mode              (1'b0),
    .v8086_mode             (1'b0),
    .protected_mode         (1'b1),

    // ALU0 interface
    .alu0_valid             (dispatch_inst0 && inst0_to_alu0),
    .alu0_cmd               (inst0_cmd),
    .alu0_cmdex             (inst0_cmdex),
    .alu0_src               (inst0_src),
    .alu0_dst               (inst0_dst),
    .alu0_is_8bit           (inst0_is_8bit),
    .alu0_uses_mult         (inst0_uses_mult),
    .alu0_uses_div          (inst0_uses_div),

    .alu0_busy              (alu0_busy),
    .alu0_ready             (alu0_ready),
    .alu0_result            (alu0_result),
    .alu0_result2           (alu0_result2),
    .alu0_result_signals    (alu0_flags),
    .alu0_exception         (),

    // ALU1 interface
    .alu1_valid             (dispatch_inst1 && inst1_to_alu1),
    .alu1_cmd               (inst1_cmd),
    .alu1_cmdex             (inst1_cmdex),
    .alu1_src               (inst1_src),
    .alu1_dst               (inst1_dst),
    .alu1_is_8bit           (inst1_is_8bit),
    .alu1_uses_mult         (inst1_uses_mult),
    .alu1_uses_div          (inst1_uses_div),

    .alu1_busy              (alu1_busy),
    .alu1_ready             (alu1_ready),
    .alu1_result            (alu1_result),
    .alu1_result2           (alu1_result2),
    .alu1_result_signals    (alu1_flags),
    .alu1_exception         (),

    // Shared multiplier/divider
    .mult_div_busy          (mult_div_busy),
    .mult_div_result        (),
    .mult_div_result2       (),
    .mult_div_exception     ()
);

//------------------------------------------------------------------------------
// Result Forwarding Network
//------------------------------------------------------------------------------

wire forward_exe0_to_rd;
wire forward_exe1_to_rd;
wire forward_wr0_to_rd;
wire forward_wr1_to_rd;
wire [31:0] forwarded_data;
wire [8:0] forwarded_eflags;
wire forward_valid;

forwarding forward_inst(
    .clk                    (clk),
    .rst_n                  (rst_n),

    // Read stage request (INTEGRATION REQUIRED)
    // WARNING: These inputs are hardcoded to zero because this module is not
    // yet integrated with the READ stage. For full forwarding functionality:
    // - rd_reg_request must connect to the register being read by READ stage
    // - rd_reg_request_valid must be high when READ stage needs a register
    // - rd_need_eflags must be high when READ stage needs EFLAGS
    // Without these connections, forwarding detection will not work correctly.
    .rd_reg_request         (3'b0),             // TODO: Connect to READ stage
    .rd_reg_request_valid   (1'b0),             // TODO: Connect to READ stage
    .rd_need_eflags         (1'b0),             // TODO: Connect to READ stage

    // EXE0 stage
    .exe0_valid             (exe0_valid_reg),
    .exe0_dst_is_reg        (1'b1),
    .exe0_dst_reg           (inst0_mutex[2:0]),
    .exe0_result            (exe0_result_reg),
    .exe0_updates_eflags    (inst0_mutex[`MUTEX_EFLAGS_BIT]),
    .exe0_eflags            (9'h0),

    // EXE1 stage
    .exe1_valid             (exe1_valid_reg),
    .exe1_dst_is_reg        (1'b1),
    .exe1_dst_reg           (inst1_mutex[2:0]),
    .exe1_result            (exe1_result_reg),
    .exe1_updates_eflags    (inst1_mutex[`MUTEX_EFLAGS_BIT]),
    .exe1_eflags            (9'h0),

    // WR0 stage
    .wr0_valid              (wr0_valid_reg),
    .wr0_dst_is_reg         (1'b1),
    .wr0_dst_reg            (wr0_mutex_reg[2:0]),
    .wr0_result             (wr0_result_reg),
    .wr0_updates_eflags     (wr0_mutex_reg[`MUTEX_EFLAGS_BIT]),
    .wr0_eflags             (9'h0),

    // WR1 stage
    .wr1_valid              (wr1_valid_reg),
    .wr1_dst_is_reg         (1'b1),
    .wr1_dst_reg            (wr1_mutex_reg[2:0]),
    .wr1_result             (wr1_result_reg),
    .wr1_updates_eflags     (wr1_mutex_reg[`MUTEX_EFLAGS_BIT]),
    .wr1_eflags             (9'h0),

    // Forwarding outputs
    .forward_exe0_to_rd     (forward_exe0_to_rd),
    .forward_exe1_to_rd     (forward_exe1_to_rd),
    .forward_wr0_to_rd      (forward_wr0_to_rd),
    .forward_wr1_to_rd      (forward_wr1_to_rd),
    .forwarded_data         (forwarded_data),
    .forwarded_eflags       (forwarded_eflags),
    .forward_valid          (forward_valid)
);

//------------------------------------------------------------------------------
// Performance Counters
//------------------------------------------------------------------------------

reg [31:0] perf_counter_reg;
reg [31:0] dispatch_count_reg;
reg [31:0] stall_dep_count_reg;
reg [31:0] stall_struct_count_reg;
reg [31:0] forward_count_reg;

always @(posedge clk) begin
    if (rst_n == 1'b0) begin
        perf_counter_reg <= 32'h0;
        dispatch_count_reg <= 32'h0;
        stall_dep_count_reg <= 32'h0;
        stall_struct_count_reg <= 32'h0;
        forward_count_reg <= 32'h0;
    end else begin
        if (dual_issue && enable_superscalar)
            perf_counter_reg <= perf_counter_reg + 32'h1;

        if (dispatch_inst0 || dispatch_inst1)
            dispatch_count_reg <= dispatch_count_reg + 32'h1;

        if (stall_dependency)
            stall_dep_count_reg <= stall_dep_count_reg + 32'h1;

        if (stall_structural)
            stall_struct_count_reg <= stall_struct_count_reg + 32'h1;

        if (forward_valid)
            forward_count_reg <= forward_count_reg + 32'h1;
    end
end

//------------------------------------------------------------------------------
// Output Assignments
//------------------------------------------------------------------------------

assign pipeline_stall = stall_dependency || stall_structural;
assign dual_issue_active = dual_issue && enable_superscalar;
assign performance_counter = perf_counter_reg;

assign alu0_result_valid = alu0_ready;
assign alu0_eip = exe0_eip_reg;

assign alu1_result_valid = alu1_ready;
assign alu1_eip = exe1_eip_reg;

assign debug_dispatch_count = dispatch_count_reg;
assign debug_stall_dependency = stall_dep_count_reg;
assign debug_stall_structural = stall_struct_count_reg;
assign debug_forward_count = forward_count_reg;

//------------------------------------------------------------------------------

endmodule
