# AO486 Superscalar Integration Analysis

## Executive Summary

The superscalar modules (dispatch.v, dual_execute.v, forwarding.v, and superscalar_pipeline.v) have been created but cannot be integrated into the current pipeline.v without significant architectural changes. The core issue is that **pipeline.v is a monolithic single-instruction-issue design**, while the superscalar modules expect a **dual-instruction interface**. This document identifies all integration blockers and incompatibilities.

---

## 1. ARCHITECTURE MISMATCH

### Current Pipeline Design
- **Single-issue architecture**: Processes one instruction per cycle through stages
- **Monolithic pipeline.v**: Contains all stages (fetch, decode, read, execute, write) as internal logic
- **No dual-instruction interface**: No capability to simultaneously process two instructions
- **Sequential instruction dependency resolution**: Relies on the write stage feeding back to earlier stages

### Superscalar Design Expectations
The superscalar_pipeline.v module expects:
```verilog
// Instruction 0 (primary)
input inst0_valid,
input [87:0] inst0_decoder,
input [6:0] inst0_cmd,
input [3:0] inst0_cmdex,
input [10:0] inst0_mutex,
input [31:0] inst0_src,
input [31:0] inst0_dst,
...

// Instruction 1 (secondary) - only used in superscalar mode
input inst1_valid,
input [87:0] inst1_decoder,
input [6:0] inst1_cmd,
input [3:0] inst1_cmdex,
input [10:0] inst1_mutex,
input [31:0] inst1_src,
input [31:0] inst1_dst,
```

**Problem**: pipeline.v provides NO such dual-instruction interface. It only provides single instruction data.

---

## 2. CRITICAL INTEGRATION BLOCKERS

### 2.1 Dual-Instruction Input Interface (BLOCKER)

**Issue**: The superscalar_pipeline.v expects to receive TWO decoded instructions simultaneously from the READ stage.

**Current Reality**:
- `pipeline.v` outputs single instruction signals:
  - `rd_cmd` (7 bits)
  - `rd_cmdex` (4 bits)
  - `rd_mutex_next` (11 bits)
  - `rd_decoder` (88 bits)
  - Various single instruction properties (src, dst, eax, flags)

**What's Needed**:
1. Dual decode stage that produces TWO instructions from the instruction stream
2. Dual register read that performs TWO register lookups simultaneously
3. Separate inst0_* and inst1_* signal bundles from READ stage
4. Instruction validity tracking for both slots

### 2.2 Missing Dual Register File Interface (BLOCKER)

**Issue**: The superscalar pipeline assumes independent register read for each instruction.

**Current Architecture**:
- Single register file read in the READ stage
- All registers (EAX, EBX, etc.) are read as single signals
- No concurrent multi-port reads for different instructions

**What's Needed**:
1. Multi-port register file with 4+ read ports (2 per instruction × 2 operands)
2. Separate `inst0_src`, `inst0_dst`, `inst1_src`, `inst1_dst` values
3. Proper register forwarding to handle same-register reads

### 2.3 Missing Dual Write-Back Interface (BLOCKER)

**Issue**: The WRITE stage is single-issue; cannot handle results from two execution units simultaneously.

**Current Architecture**:
- `write.v` is a 73KB single-issue write stage
- Handles only one register write per cycle
- Memory write operations are serialized

**What's Needed**:
1. Dual-port register file write capability
2. Separate write logic for ALU0 and ALU1 results
3. Write arbitration for register conflicts
4. Exception handling for dual-issue failures

### 2.4 Exception Handling for Dual-Issue (BLOCKER)

**Issue**: The current exception system assumes single-instruction state.

**Problems with Dual-Issue**:
1. What if ALU0 raises an exception while ALU1 completes successfully?
2. How to handle exceptions mid-dual-issue?
3. Register write ordering for exception recovery?
4. Task switches interrupt dual-issue - need coordination

---

## 3. SPECIFIC IMPLEMENTATION ISSUES

### 3.1 Hardcoded Zero Inputs in Forwarding

**File**: `superscalar_pipeline.v` (line 431-433)
```verilog
forwarding forward_inst(
    ...
    .rd_reg_request         (3'b0),          // ← ALWAYS ZERO!
    .rd_reg_request_valid   (1'b0),          // ← ALWAYS ZERO!
    .rd_need_eflags         (1'b0),          // ← ALWAYS ZERO!
```

**Impact**: The forwarding unit will never forward anything because all request signals are tied to zero.

### 3.2 Magic Bit Numbers for Instruction Classification

**File**: `superscalar_pipeline.v` (line 156-160)
```verilog
assign inst0_uses_mult = inst0_decoder[20];  // Magic bit!
assign inst0_uses_div = inst0_decoder[21];   // Magic bit!
```

**Problem**: These decoder bit positions are not defined anywhere. They are placeholder numbers that won't work.

### 3.3 MUTEX_IO_BIT Not Checked

**File**: `dispatch.v` (lines 78-82)
```verilog
assign raw_dependency_01 =
    inst0_valid && inst1_valid &&
    ((inst0_mutex[7:0] & inst1_mutex[7:0]) != 8'b0 ||
     (inst0_mutex[8] && inst1_mutex[8]) ||
     (inst0_mutex[9] && inst1_mutex[9]));
     // ↑ Only checks bits 9, missing MUTEX_IO_BIT (bit 11)!
```

### 3.4 Wrong Mutex Source for Dependency Analysis

**File**: `dispatch.v` (lines 88-100)

The dispatch module checks `inst0_mutex` (what inst0 WILL SET) against `pipeline_mutex` (what's currently in flight). But it should check what inst0 will READ against what's being written by in-flight instructions.

---

## 4. MISSING ARCHITECTURAL COMPONENTS

| Component | Status | Impact |
|-----------|--------|--------|
| Dual instruction decode | Not implemented | Cannot extract two instructions from stream |
| Dual register read stage | Not implemented | Cannot read operands for both instructions |
| Dispatch stage between DECODE and READ | Not in pipeline.v | Dependency checking too late in pipeline |
| Dual write-back logic | Not in write.v | Cannot commit two results per cycle |
| Forwarding network implementation | Stubbed out | All inputs tied to zero |
| Memory dual-issue support | Not implemented | Both instructions cannot touch memory |
| Exception coordination | Not designed | No handling for dual exceptions |
| Test benches for superscalar | Not created | Cannot validate functionality |

---

## 5. COMMAND DEFINITIONS VERIFICATION

### Status: ✓ PASS (With Caveat)

The CMD_* defines are correctly included. The autogen/defines.v file (auto-generated) redefines CMD_* with correct values that take precedence:

```verilog
// In autogen/defines.v (takes precedence)
`define CMD_ADD 7'd64
`define CMD_MOV 7'd90
`define CMD_SUB 7'd69
```

**Caveat**: If someone accidentally includes only defines.v without autogen, or caches preprocessing results, it would break. But as currently configured: ✓ PASS

---

## 6. INTEGRATION PATHS

### Option 1: Full Architectural Redesign (Recommended)
- Refactor pipeline.v for dual-instruction flow
- Implement dual decode, dual read, dual dispatch
- Extend write.v for dual write-back
- Effort: ~2000+ lines, 4-6 weeks

### Option 2: Performance Enhancement Path (Faster)
- Keep single-issue as default
- Add speculative dual-issue when safe
- Use superscalar_pipeline as optional accelerator
- Effort: ~500 lines, 1-2 weeks
- Risk: Lower performance gains

### Option 3: Simulation-Only Validation (Fastest)
- Validate dispatch/forwarding logic in simulation
- Profile dual-issue potential
- Guide actual implementation
- Effort: ~300 lines, 2-3 days

---

## 7. SUMMARY OF REAL ISSUES

| Issue | Severity | Category | File(s) |
|-------|----------|----------|---------|
| No dual-instruction interface from READ | CRITICAL | Architecture | pipeline.v |
| Dual register file read not implemented | CRITICAL | Architecture | pipeline.v |
| Dual write-back not supported | CRITICAL | Architecture | write.v |
| Dispatch placed after READ, needs before | CRITICAL | Architecture | Overall |
| Forwarding inputs hardcoded to zero | HIGH | Configuration | superscalar_pipeline.v:431-433 |
| Instruction classification magic bits | HIGH | Implementation | superscalar_pipeline.v:156-160 |
| MUTEX_IO_BIT not checked | HIGH | Logic | dispatch.v:78-82 |
| Wrong mutex source for dependencies | HIGH | Logic | dispatch.v:88-100 |
| Memory dual-issue not implemented | HIGH | Feature | dual_execute.v |
| Exception handling for dual-issue missing | HIGH | Feature | Overall |
| No test benches for superscalar | MEDIUM | Testing | sim/iverilog/ |
| Pipeline state tracking incomplete | MEDIUM | Implementation | superscalar_pipeline.v:194-266 |

---

## 8. IMMEDIATE ACTIONS REQUIRED

Before any integration attempt:

1. **Fix Forwarding Module** (2 hours)
   - Remove hardcoded zero assignments
   - Wire rd_reg_request from READ stage
   - Add rd_need_eflags detection

2. **Document Decoder Format** (4 hours)
   - Identify which decoder bits indicate mult/div/memory
   - Replace magic numbers [20], [21] with named constants
   - Define instruction classification rules

3. **Create Test Benches** (8 hours)
   - Test dispatch RAW dependency detection
   - Test dual execute arithmetic operations
   - Test result forwarding correctness

4. **Fix MUTEX Checking** (2 hours)
   - Add MUTEX_IO_BIT to dependency checks
   - Clarify what mutex values represent (read vs write set)

---

## Files Analyzed

**Superscalar Modules Created** (~1240 lines):
- `/home/user/ao486_MiSTer/rtl/ao486/pipeline/superscalar_pipeline.v` (533 lines)
- `/home/user/ao486_MiSTer/rtl/ao486/pipeline/dual_execute.v` (318 lines)
- `/home/user/ao486_MiSTer/rtl/ao486/pipeline/dispatch.v` (200+ lines)
- `/home/user/ao486_MiSTer/rtl/ao486/pipeline/forwarding.v` (200+ lines)

**Critical System Files**:
- `/home/user/ao486_MiSTer/rtl/ao486/pipeline/pipeline.v` (1437 lines)
- `/home/user/ao486_MiSTer/rtl/ao486/pipeline/execute.v` (39KB)
- `/home/user/ao486_MiSTer/rtl/ao486/pipeline/write.v` (73KB)
- `/home/user/ao486_MiSTer/rtl/ao486/pipeline/read.v` (49KB)
- `/home/user/ao486_MiSTer/rtl/ao486/defines.v` - Verified correct

---

**Report Generated**: 2025-11-07
**Analysis Focus**: Integration feasibility and compatibility issues
