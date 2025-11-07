/*
 * Copyright (c) 2025, Superscalar ao486 Enhancement
 * All rights reserved.
 *
 * Result Forwarding Unit for 2-way Superscalar ao486
 *
 * This module implements data forwarding (bypass paths) to reduce pipeline stalls:
 * - EXE -> READ forwarding (1 cycle delay)
 * - WR -> READ forwarding (2 cycle delay)
 * - Handles dual-issue forwarding from both execution units
 */

`include "defines.v"

module forwarding(
    input               clk,
    input               rst_n,

    // READ stage inputs (requesting data)
    input       [2:0]   rd_reg_request,     // Which register is being read
    input               rd_reg_request_valid,
    input               rd_need_eflags,

    // EXE0 stage outputs (potential forward source)
    input               exe0_valid,
    input               exe0_dst_is_reg,
    input       [2:0]   exe0_dst_reg,
    input       [31:0]  exe0_result,
    input               exe0_updates_eflags,
    input       [8:0]   exe0_eflags,        // {OF, DF, IF, TF, SF, ZF, AF, PF, CF}

    // EXE1 stage outputs (potential forward source)
    input               exe1_valid,
    input               exe1_dst_is_reg,
    input       [2:0]   exe1_dst_reg,
    input       [31:0]  exe1_result,
    input               exe1_updates_eflags,
    input       [8:0]   exe1_eflags,

    // WR0 stage outputs (potential forward source)
    input               wr0_valid,
    input               wr0_dst_is_reg,
    input       [2:0]   wr0_dst_reg,
    input       [31:0]  wr0_result,
    input               wr0_updates_eflags,
    input       [8:0]   wr0_eflags,

    // WR1 stage outputs (potential forward source)
    input               wr1_valid,
    input               wr1_dst_is_reg,
    input       [2:0]   wr1_dst_reg,
    input       [31:0]  wr1_result,
    input               wr1_updates_eflags,
    input       [8:0]   wr1_eflags,

    // Forwarding outputs
    output              forward_exe0_to_rd, // Forward from EXE0 to READ
    output              forward_exe1_to_rd, // Forward from EXE1 to READ
    output              forward_wr0_to_rd,  // Forward from WR0 to READ
    output              forward_wr1_to_rd,  // Forward from WR1 to READ

    output      [31:0]  forwarded_data,     // The forwarded data value
    output      [8:0]   forwarded_eflags,   // The forwarded EFLAGS

    output              forward_valid       // Forwarding is happening
);

//------------------------------------------------------------------------------
// Register Forwarding Detection
//------------------------------------------------------------------------------

// Check if EXE0 can forward to READ
wire exe0_matches_reg;
assign exe0_matches_reg =
    exe0_valid &&
    exe0_dst_is_reg &&
    rd_reg_request_valid &&
    (exe0_dst_reg == rd_reg_request);

// Check if EXE1 can forward to READ
wire exe1_matches_reg;
assign exe1_matches_reg =
    exe1_valid &&
    exe1_dst_is_reg &&
    rd_reg_request_valid &&
    (exe1_dst_reg == rd_reg_request);

// Check if WR0 can forward to READ
wire wr0_matches_reg;
assign wr0_matches_reg =
    wr0_valid &&
    wr0_dst_is_reg &&
    rd_reg_request_valid &&
    (wr0_dst_reg == rd_reg_request);

// Check if WR1 can forward to READ
wire wr1_matches_reg;
assign wr1_matches_reg =
    wr1_valid &&
    wr1_dst_is_reg &&
    rd_reg_request_valid &&
    (wr1_dst_reg == rd_reg_request);

//------------------------------------------------------------------------------
// EFLAGS Forwarding Detection
//------------------------------------------------------------------------------

wire exe0_matches_eflags;
assign exe0_matches_eflags =
    exe0_valid &&
    exe0_updates_eflags &&
    rd_need_eflags;

wire exe1_matches_eflags;
assign exe1_matches_eflags =
    exe1_valid &&
    exe1_updates_eflags &&
    rd_need_eflags;

wire wr0_matches_eflags;
assign wr0_matches_eflags =
    wr0_valid &&
    wr0_updates_eflags &&
    rd_need_eflags;

wire wr1_matches_eflags;
assign wr1_matches_eflags =
    wr1_valid &&
    wr1_updates_eflags &&
    rd_need_eflags;

//------------------------------------------------------------------------------
// Forwarding Priority (most recent instruction has priority)
// Priority: EXE1 > EXE0 > WR1 > WR0 (newer instructions override older)
//------------------------------------------------------------------------------

wire forward_from_exe0;
wire forward_from_exe1;
wire forward_from_wr0;
wire forward_from_wr1;

// EXE1 has highest priority (most recent)
assign forward_from_exe1 =
    (exe1_matches_reg || exe1_matches_eflags);

// EXE0 has priority if EXE1 doesn't match
assign forward_from_exe0 =
    (exe0_matches_reg || exe0_matches_eflags) &&
    !forward_from_exe1;

// WR1 has priority if no EXE stage matches
assign forward_from_wr1 =
    (wr1_matches_reg || wr1_matches_eflags) &&
    !forward_from_exe1 &&
    !forward_from_exe0;

// WR0 has lowest priority
assign forward_from_wr0 =
    (wr0_matches_reg || wr0_matches_eflags) &&
    !forward_from_exe1 &&
    !forward_from_exe0 &&
    !forward_from_wr1;

//------------------------------------------------------------------------------
// Output Assignments
//------------------------------------------------------------------------------

assign forward_exe0_to_rd = forward_from_exe0;
assign forward_exe1_to_rd = forward_from_exe1;
assign forward_wr0_to_rd = forward_from_wr0;
assign forward_wr1_to_rd = forward_from_wr1;

assign forward_valid =
    forward_from_exe0 ||
    forward_from_exe1 ||
    forward_from_wr0 ||
    forward_from_wr1;

// Mux forwarded data based on priority
assign forwarded_data =
    forward_from_exe1 ? exe1_result :
    forward_from_exe0 ? exe0_result :
    forward_from_wr1 ? wr1_result :
    forward_from_wr0 ? wr0_result :
    32'h0;

// Mux forwarded EFLAGS based on priority
assign forwarded_eflags =
    forward_from_exe1 ? exe1_eflags :
    forward_from_exe0 ? exe0_eflags :
    forward_from_wr1 ? wr1_eflags :
    forward_from_wr0 ? wr0_eflags :
    9'h0;

//------------------------------------------------------------------------------

// synthesis translate_off
wire _unused_ok = &{ 1'b0, clk, rst_n, 1'b0 };
// synthesis translate_on

endmodule
