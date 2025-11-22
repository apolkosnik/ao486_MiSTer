/*
 * Copyright (c) 2025, Superscalar ao486 Enhancement
 * All rights reserved.
 *
 * Dual Execution Unit Wrapper for 2-way Superscalar ao486
 *
 * This module instantiates two parallel execution units (ALU0 and ALU1)
 * to enable dual-issue execution. The multiplier and divider are shared
 * between both units to save area.
 */

`include "defines.v"

module dual_execute(
    input               clk,
    input               rst_n,

    input               exe_reset,

    //------------------------------------------------------------------------------
    // Shared Resources (inputs to both ALUs)
    //------------------------------------------------------------------------------

    // General purpose registers
    input       [31:0]  eax,
    input       [31:0]  ecx,
    input       [31:0]  edx,
    input       [31:0]  ebp,
    input       [31:0]  esp,
    input       [31:0]  ebx,
    input       [31:0]  esi,
    input       [31:0]  edi,

    // Flags and control registers
    input               cflag,
    input               pflag,
    input               aflag,
    input               zflag,
    input               sflag,
    input               oflag,
    input               dflag,
    input               tflag,
    input               iflag,

    input       [1:0]   cpl,
    input               real_mode,
    input               v8086_mode,
    input               protected_mode,

    //------------------------------------------------------------------------------
    // ALU0 Interface (Primary execution unit)
    //------------------------------------------------------------------------------

    input               alu0_valid,
    input       [6:0]   alu0_cmd,
    input       [3:0]   alu0_cmdex,
    input       [31:0]  alu0_src,
    input       [31:0]  alu0_dst,
    input               alu0_is_8bit,
    input               alu0_uses_mult,
    input               alu0_uses_div,

    output              alu0_busy,
    output              alu0_ready,
    output      [31:0]  alu0_result,
    output      [31:0]  alu0_result2,
    output      [4:0]   alu0_result_signals, // {overflow, zero, sign, parity, carry}
    output              alu0_exception,

    //------------------------------------------------------------------------------
    // ALU1 Interface (Secondary execution unit)
    //------------------------------------------------------------------------------

    input               alu1_valid,
    input       [6:0]   alu1_cmd,
    input       [3:0]   alu1_cmdex,
    input       [31:0]  alu1_src,
    input       [31:0]  alu1_dst,
    input               alu1_is_8bit,
    input               alu1_uses_mult,
    input               alu1_uses_div,

    output              alu1_busy,
    output              alu1_ready,
    output      [31:0]  alu1_result,
    output      [31:0]  alu1_result2,
    output      [4:0]   alu1_result_signals,
    output              alu1_exception,

    //------------------------------------------------------------------------------
    // Shared Multiplier/Divider
    //------------------------------------------------------------------------------

    output              mult_div_busy,
    output      [31:0]  mult_div_result,
    output      [31:0]  mult_div_result2,
    output              mult_div_exception
);

//------------------------------------------------------------------------------
// Arithmetic and Logic Operations for ALU0
//------------------------------------------------------------------------------

reg [31:0]  alu0_arith_result;
reg [4:0]   alu0_flags;
reg         alu0_done;

always @(posedge clk) begin
    if (rst_n == 1'b0 || exe_reset) begin
        alu0_arith_result <= 32'h0;
        alu0_flags <= 5'h0;
        alu0_done <= 1'b0;
    end else if (alu0_valid && !alu0_uses_mult && !alu0_uses_div) begin
        // Simple ALU operations (1 cycle latency)
        case (alu0_cmd)
            `CMD_ADD, `CMD_ADC: begin
                automatic logic [32:0] add_result = alu0_dst + alu0_src + ((alu0_cmd == `CMD_ADC) ? {31'h0, cflag} : 32'h0);
                alu0_arith_result <= add_result[31:0];
                alu0_flags[0] <= alu0_is_8bit ? add_result[8] : add_result[32];  // CF
                alu0_flags[1] <= ~^add_result[7:0];  // PF (even parity)
                alu0_flags[2] <= alu0_is_8bit ? add_result[7] : add_result[31];  // SF
                alu0_flags[3] <= alu0_is_8bit ? (add_result[7:0] == 8'h0) : (add_result[31:0] == 32'h0);  // ZF
                alu0_flags[4] <= alu0_is_8bit ?
                                 ((alu0_dst[7] == alu0_src[7]) && (alu0_dst[7] != add_result[7])) :
                                 ((alu0_dst[31] == alu0_src[31]) && (alu0_dst[31] != add_result[31]));  // OF
                alu0_done <= 1'b1;
            end

            `CMD_SUB, `CMD_SBB, `CMD_CMP: begin
                automatic logic [32:0] sub_result = alu0_dst - alu0_src - ((alu0_cmd == `CMD_SBB) ? {31'h0, cflag} : 32'h0);
                alu0_arith_result <= sub_result[31:0];
                alu0_flags[0] <= alu0_is_8bit ? sub_result[8] : sub_result[32];  // CF (borrow)
                alu0_flags[1] <= ~^sub_result[7:0];  // PF (even parity)
                alu0_flags[2] <= alu0_is_8bit ? sub_result[7] : sub_result[31];  // SF
                alu0_flags[3] <= alu0_is_8bit ? (sub_result[7:0] == 8'h0) : (sub_result[31:0] == 32'h0);  // ZF
                alu0_flags[4] <= alu0_is_8bit ?
                                 ((alu0_dst[7] != alu0_src[7]) && (alu0_dst[7] != sub_result[7])) :
                                 ((alu0_dst[31] != alu0_src[31]) && (alu0_dst[31] != sub_result[31]));  // OF
                alu0_done <= 1'b1;
            end

            `CMD_AND, `CMD_TEST: begin
                automatic logic [31:0] and_result = alu0_dst & alu0_src;
                alu0_arith_result <= and_result;
                alu0_flags[0] <= 1'b0;  // CF = 0
                alu0_flags[1] <= ~^and_result[7:0];  // PF (even parity)
                alu0_flags[2] <= alu0_is_8bit ? and_result[7] : and_result[31];  // SF
                alu0_flags[3] <= alu0_is_8bit ? (and_result[7:0] == 8'h0) : (and_result == 32'h0);  // ZF
                alu0_flags[4] <= 1'b0;  // OF = 0
                alu0_done <= 1'b1;
            end

            `CMD_OR: begin
                automatic logic [31:0] or_result = alu0_dst | alu0_src;
                alu0_arith_result <= or_result;
                alu0_flags[0] <= 1'b0;
                alu0_flags[1] <= ~^or_result[7:0];  // PF (even parity)
                alu0_flags[2] <= alu0_is_8bit ? or_result[7] : or_result[31];  // SF
                alu0_flags[3] <= alu0_is_8bit ? (or_result[7:0] == 8'h0) : (or_result == 32'h0);  // ZF
                alu0_flags[4] <= 1'b0;
                alu0_done <= 1'b1;
            end

            `CMD_XOR: begin
                automatic logic [31:0] xor_result = alu0_dst ^ alu0_src;
                alu0_arith_result <= xor_result;
                alu0_flags[0] <= 1'b0;
                alu0_flags[1] <= ~^xor_result[7:0];  // PF (even parity)
                alu0_flags[2] <= alu0_is_8bit ? xor_result[7] : xor_result[31];  // SF
                alu0_flags[3] <= alu0_is_8bit ? (xor_result[7:0] == 8'h0) : (xor_result == 32'h0);  // ZF
                alu0_flags[4] <= 1'b0;
                alu0_done <= 1'b1;
            end

            `CMD_MOV: begin
                alu0_arith_result <= alu0_src;
                alu0_done <= 1'b1;
            end

            default: begin
                alu0_arith_result <= 32'h0;
                alu0_flags <= 5'h0;
                alu0_done <= 1'b0;
            end
        endcase
    end else begin
        alu0_done <= 1'b0;
    end
end

//------------------------------------------------------------------------------
// Arithmetic and Logic Operations for ALU1
//------------------------------------------------------------------------------

reg [31:0]  alu1_arith_result;
reg [4:0]   alu1_flags;
reg         alu1_done;

always @(posedge clk) begin
    if (rst_n == 1'b0 || exe_reset) begin
        alu1_arith_result <= 32'h0;
        alu1_flags <= 5'h0;
        alu1_done <= 1'b0;
    end else if (alu1_valid && !alu1_uses_mult && !alu1_uses_div) begin
        // Simple ALU operations (1 cycle latency)
        case (alu1_cmd)
            `CMD_ADD, `CMD_ADC: begin
                automatic logic [32:0] add_result = alu1_dst + alu1_src + ((alu1_cmd == `CMD_ADC) ? {31'h0, cflag} : 32'h0);
                alu1_arith_result <= add_result[31:0];
                alu1_flags[0] <= alu1_is_8bit ? add_result[8] : add_result[32];  // CF
                alu1_flags[1] <= ~^add_result[7:0];  // PF (even parity)
                alu1_flags[2] <= alu1_is_8bit ? add_result[7] : add_result[31];  // SF
                alu1_flags[3] <= alu1_is_8bit ? (add_result[7:0] == 8'h0) : (add_result[31:0] == 32'h0);  // ZF
                alu1_flags[4] <= alu1_is_8bit ?
                                 ((alu1_dst[7] == alu1_src[7]) && (alu1_dst[7] != add_result[7])) :
                                 ((alu1_dst[31] == alu1_src[31]) && (alu1_dst[31] != add_result[31]));  // OF
                alu1_done <= 1'b1;
            end

            `CMD_SUB, `CMD_SBB, `CMD_CMP: begin
                automatic logic [32:0] sub_result = alu1_dst - alu1_src - ((alu1_cmd == `CMD_SBB) ? {31'h0, cflag} : 32'h0);
                alu1_arith_result <= sub_result[31:0];
                alu1_flags[0] <= alu1_is_8bit ? sub_result[8] : sub_result[32];  // CF (borrow)
                alu1_flags[1] <= ~^sub_result[7:0];  // PF (even parity)
                alu1_flags[2] <= alu1_is_8bit ? sub_result[7] : sub_result[31];  // SF
                alu1_flags[3] <= alu1_is_8bit ? (sub_result[7:0] == 8'h0) : (sub_result[31:0] == 32'h0);  // ZF
                alu1_flags[4] <= alu1_is_8bit ?
                                 ((alu1_dst[7] != alu1_src[7]) && (alu1_dst[7] != sub_result[7])) :
                                 ((alu1_dst[31] != alu1_src[31]) && (alu1_dst[31] != sub_result[31]));  // OF
                alu1_done <= 1'b1;
            end

            `CMD_AND, `CMD_TEST: begin
                automatic logic [31:0] and_result = alu1_dst & alu1_src;
                alu1_arith_result <= and_result;
                alu1_flags[0] <= 1'b0;
                alu1_flags[1] <= ~^and_result[7:0];  // PF (even parity)
                alu1_flags[2] <= alu1_is_8bit ? and_result[7] : and_result[31];  // SF
                alu1_flags[3] <= alu1_is_8bit ? (and_result[7:0] == 8'h0) : (and_result == 32'h0);  // ZF
                alu1_flags[4] <= 1'b0;
                alu1_done <= 1'b1;
            end

            `CMD_OR: begin
                automatic logic [31:0] or_result = alu1_dst | alu1_src;
                alu1_arith_result <= or_result;
                alu1_flags[0] <= 1'b0;
                alu1_flags[1] <= ~^or_result[7:0];  // PF (even parity)
                alu1_flags[2] <= alu1_is_8bit ? or_result[7] : or_result[31];  // SF
                alu1_flags[3] <= alu1_is_8bit ? (or_result[7:0] == 8'h0) : (or_result == 32'h0);  // ZF
                alu1_flags[4] <= 1'b0;
                alu1_done <= 1'b1;
            end

            `CMD_XOR: begin
                automatic logic [31:0] xor_result = alu1_dst ^ alu1_src;
                alu1_arith_result <= xor_result;
                alu1_flags[0] <= 1'b0;
                alu1_flags[1] <= ~^xor_result[7:0];  // PF (even parity)
                alu1_flags[2] <= alu1_is_8bit ? xor_result[7] : xor_result[31];  // SF
                alu1_flags[3] <= alu1_is_8bit ? (xor_result[7:0] == 8'h0) : (xor_result == 32'h0);  // ZF
                alu1_flags[4] <= 1'b0;
                alu1_done <= 1'b1;
            end

            `CMD_MOV: begin
                alu1_arith_result <= alu1_src;
                alu1_done <= 1'b1;
            end

            default: begin
                alu1_arith_result <= 32'h0;
                alu1_flags <= 5'h0;
                alu1_done <= 1'b0;
            end
        endcase
    end else begin
        alu1_done <= 1'b0;
    end
end

//------------------------------------------------------------------------------
// Shared Multiplier (arbitrate between ALU0 and ALU1)
//------------------------------------------------------------------------------

reg         mult_active;
reg         mult_for_alu0;
reg [2:0]   mult_counter;
reg [63:0]  mult_result_full;

wire        mult_request_alu0 = alu0_valid && alu0_uses_mult;
wire        mult_request_alu1 = alu1_valid && alu1_uses_mult;

always @(posedge clk) begin
    if (rst_n == 1'b0 || exe_reset) begin
        mult_active <= 1'b0;
        mult_for_alu0 <= 1'b0;
        mult_counter <= 3'h0;
        mult_result_full <= 64'h0;
    end else if (!mult_active) begin
        // Arbitrate: ALU0 has priority
        if (mult_request_alu0) begin
            mult_active <= 1'b1;
            mult_for_alu0 <= 1'b1;
            mult_counter <= 3'h3;  // 3 cycle multiply
            mult_result_full <= $signed(alu0_dst) * $signed(alu0_src);
        end else if (mult_request_alu1) begin
            mult_active <= 1'b1;
            mult_for_alu0 <= 1'b0;
            mult_counter <= 3'h3;
            mult_result_full <= $signed(alu1_dst) * $signed(alu1_src);
        end
    end else if (mult_counter > 3'h0) begin
        mult_counter <= mult_counter - 3'h1;
    end else begin
        mult_active <= 1'b0;
    end
end

//------------------------------------------------------------------------------
// Output Assignments
//------------------------------------------------------------------------------

// ALU busy logic:
// - For ALU operations: busy while valid and not done (1 cycle)
// - For multiply: busy for entire multiply duration (3 cycles)
// CRITICAL: Don't depend on alu_valid for multiply - it goes low after dispatch!
assign alu0_busy = (alu0_valid && !alu0_done) || (mult_active && mult_for_alu0);
assign alu0_ready = alu0_done || (mult_active && mult_counter == 3'h0 && mult_for_alu0);
assign alu0_result = alu0_uses_mult ? mult_result_full[31:0] : alu0_arith_result;
assign alu0_result2 = alu0_uses_mult ? mult_result_full[63:32] : 32'h0;
assign alu0_result_signals = alu0_flags;
assign alu0_exception = 1'b0;

assign alu1_busy = (alu1_valid && !alu1_done) || (mult_active && !mult_for_alu0);
assign alu1_ready = alu1_done || (mult_active && mult_counter == 3'h0 && !mult_for_alu0);
assign alu1_result = alu1_uses_mult ? mult_result_full[31:0] : alu1_arith_result;
assign alu1_result2 = alu1_uses_mult ? mult_result_full[63:32] : 32'h0;
assign alu1_result_signals = alu1_flags;
assign alu1_exception = 1'b0;

assign mult_div_busy = mult_active;
assign mult_div_result = mult_result_full[31:0];
assign mult_div_result2 = mult_result_full[63:32];
assign mult_div_exception = 1'b0;

//------------------------------------------------------------------------------

endmodule
