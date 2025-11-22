/*
 * Copyright (c) 2025, Superscalar ao486 Enhancement
 * All rights reserved.
 *
 * Instruction Dispatch Unit for 2-way Superscalar ao486
 *
 * This module handles:
 * - Dual instruction dispatch
 * - Dependency checking between instruction pairs
 * - Resource conflict detection
 * - Instruction steering to execution units
 */

`include "defines.v"

module dispatch(
    input               clk,
    input               rst_n,

    input               dispatch_reset,

    // Instruction 0 inputs (from READ stage)
    input               inst0_valid,
    input       [6:0]   inst0_cmd,
    input       [3:0]   inst0_cmdex,
    input       [10:0]  inst0_mutex,
    input               inst0_uses_alu,
    input               inst0_uses_mult,
    input               inst0_uses_div,
    input               inst0_uses_memory,
    input               inst0_is_branch,
    input               inst0_is_complex,

    // Instruction 1 inputs (from READ stage)
    input               inst1_valid,
    input       [6:0]   inst1_cmd,
    input       [3:0]   inst1_cmdex,
    input       [10:0]  inst1_mutex,
    input               inst1_uses_alu,
    input               inst1_uses_mult,
    input               inst1_uses_div,
    input               inst1_uses_memory,
    input               inst1_is_branch,
    input               inst1_is_complex,

    // Execution unit status
    input               alu0_busy,
    input               alu1_busy,
    input               mult_busy,
    input               div_busy,
    input               mem_busy,

    // Pipeline mutex state (combined from exe and wr stages)
    input       [10:0]  pipeline_mutex,

    // Dispatch outputs
    output              dispatch_inst0,      // Dispatch instruction 0
    output              dispatch_inst1,      // Dispatch instruction 1
    output              inst0_to_alu0,       // Route inst0 to ALU0
    output              inst0_to_alu1,       // Route inst0 to ALU1
    output              inst1_to_alu0,       // Route inst1 to ALU0
    output              inst1_to_alu1,       // Route inst1 to ALU1

    output              dual_issue,          // Both instructions issued
    output              stall_dependency,    // Stall due to data dependency
    output              stall_structural     // Stall due to resource conflict
);

//------------------------------------------------------------------------------
// Dependency Detection
//------------------------------------------------------------------------------

// Check RAW (Read-After-Write) dependencies between inst0 and inst1
wire raw_dependency_01;
assign raw_dependency_01 =
    inst0_valid && inst1_valid &&
    (|(inst0_mutex[7:0] & inst1_mutex[7:0]) ||      // Register overlap (reduction OR)
     (inst0_mutex[8] && inst1_mutex[8]) ||          // EFLAGS dependency
     (inst0_mutex[9] && inst1_mutex[9]) ||          // Memory dependency
     (inst0_mutex[10] && inst1_mutex[10]));         // I/O dependency

// pipeline_mutex is now an input port (combined exe_mutex | wr_mutex from pipeline.v)

// NOTE: Mutex ambiguity issue
// The ao486 mutex vector does not distinguish between registers/resources that
// an instruction READS vs WRITES. The mutex bit is set if the instruction
// accesses that resource in any way. This means we're detecting WAW (Write-After-Write)
// and potentially WAR (Write-After-Read) hazards, but the real hazard we care about
// is RAW (Read-After-Write).
//
// Ideally we would check: "Does inst0 READ something that pipeline is WRITING?"
// But we can only check: "Does inst0 ACCESS something that pipeline ACCESSES?"
//
// This is conservative (may cause unnecessary stalls) but safe (won't miss dependencies).
// A proper fix would require extending the mutex system to track read/write separately.

wire inst0_has_dependency;
assign inst0_has_dependency =
    inst0_valid &&
    (|(inst0_mutex[7:0] & pipeline_mutex[7:0]) ||   // Register dependency (reduction OR)
     (inst0_mutex[8] && pipeline_mutex[8]) ||       // EFLAGS dependency
     (inst0_mutex[9] && pipeline_mutex[9]) ||       // Memory dependency
     (inst0_mutex[10] && pipeline_mutex[10]));      // I/O dependency

wire inst1_has_dependency;
assign inst1_has_dependency =
    inst1_valid &&
    (|(inst1_mutex[7:0] & pipeline_mutex[7:0]) ||   // Register dependency (reduction OR)
     (inst1_mutex[8] && pipeline_mutex[8]) ||       // EFLAGS dependency
     (inst1_mutex[9] && pipeline_mutex[9]) ||       // Memory dependency
     (inst1_mutex[10] && pipeline_mutex[10]));      // I/O dependency

//------------------------------------------------------------------------------
// Resource Conflict Detection
//------------------------------------------------------------------------------

// Check if both instructions need the same execution unit
wire resource_conflict;
assign resource_conflict =
    inst0_valid && inst1_valid &&
    ((inst0_uses_mult && inst1_uses_mult) ||        // Both need multiplier
     (inst0_uses_div && inst1_uses_div) ||          // Both need divider
     (inst0_uses_memory && inst1_uses_memory));     // Both need memory

// Check if execution units are available
wire alu0_available = !alu0_busy;
wire alu1_available = !alu1_busy;
wire mult_available = !mult_busy;
wire div_available = !div_busy;
wire mem_available = !mem_busy;

//------------------------------------------------------------------------------
// Dispatch Policy
//------------------------------------------------------------------------------

// Complex instructions must execute alone (no dual-issue)
wire inst0_must_single_issue = inst0_is_complex || inst0_is_branch || inst0_uses_div;
wire inst1_must_single_issue = inst1_is_complex || inst1_is_branch || inst1_uses_div;

// Can we dispatch inst0?
// NOTE: Check for == 1'b0 first to handle any potential X/Z values safely
wire inst0_alu_ok;
wire inst0_mult_ok;
wire inst0_div_ok;
wire inst0_mem_ok;

// Only dispatch instructions that actually use these resources
// If instruction doesn't use the resource, it can't go through superscalar path
assign inst0_alu_ok = inst0_uses_alu ? (alu0_available || alu1_available) : 1'b0;
assign inst0_mult_ok = inst0_uses_mult ? mult_available : 1'b0;
assign inst0_div_ok = inst0_uses_div ? div_available : 1'b0;
assign inst0_mem_ok = 1'b0;  // Memory ops never dispatch - use original execute path

wire can_dispatch_inst0;
assign can_dispatch_inst0 =
    inst0_valid &&
    !inst0_has_dependency &&
    inst0_alu_ok &&
    inst0_mult_ok &&
    inst0_div_ok &&
    inst0_mem_ok;

// Can we dispatch inst1?
wire inst1_alu_ok;
wire inst1_mult_ok;
wire inst1_mem_ok;

// Same logic for inst1 - only dispatch if instruction uses the resource
assign inst1_alu_ok = inst1_uses_alu ? (alu0_available || alu1_available) : 1'b0;
assign inst1_mult_ok = inst1_uses_mult ? mult_available : 1'b0;
assign inst1_mem_ok = 1'b0;  // Memory ops never dispatch - use original execute path

wire can_dispatch_inst1;
assign can_dispatch_inst1 =
    inst1_valid &&
    !inst1_has_dependency &&
    !raw_dependency_01 &&
    !inst0_must_single_issue &&
    !inst1_must_single_issue &&
    !resource_conflict &&
    inst1_alu_ok &&
    inst1_mult_ok &&
    inst1_mem_ok;

// Dispatch decisions
assign dispatch_inst0 = can_dispatch_inst0;
assign dispatch_inst1 = can_dispatch_inst0 && can_dispatch_inst1;
assign dual_issue = dispatch_inst0 && dispatch_inst1;

//------------------------------------------------------------------------------
// Execution Unit Assignment
//------------------------------------------------------------------------------

// Default routing: inst0 -> ALU0, inst1 -> ALU1
// If ALU0 is busy, try to route inst0 to ALU1
assign inst0_to_alu0 = inst0_uses_alu && alu0_available && !inst1_valid;
assign inst0_to_alu1 = inst0_uses_alu && (!alu0_available || inst1_valid) && alu1_available;

assign inst1_to_alu0 = inst1_uses_alu && !inst0_uses_alu && alu0_available;
assign inst1_to_alu1 = inst1_uses_alu && (inst0_uses_alu || !alu0_available) && alu1_available;

//------------------------------------------------------------------------------
// Stall Signals
//------------------------------------------------------------------------------

assign stall_dependency = inst0_has_dependency ||
                         (inst1_valid && (inst1_has_dependency || raw_dependency_01));

assign stall_structural =
    (inst0_valid && inst0_uses_alu && !alu0_available && !alu1_available) ||
    (inst0_valid && inst0_uses_mult && !mult_available) ||
    (inst0_valid && inst0_uses_div && !div_available) ||
    (inst0_valid && inst0_uses_memory && !mem_available) ||
    resource_conflict;

//------------------------------------------------------------------------------

// synthesis translate_off
wire _unused_ok = &{ 1'b0, inst0_cmd, inst0_cmdex, inst1_cmd, inst1_cmdex, dispatch_reset, 1'b0 };
// synthesis translate_on

endmodule
