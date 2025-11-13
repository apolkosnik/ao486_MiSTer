# Dual-Issue Pipeline: Technical Implementation Specification

## Document Purpose

This document provides **exact code-level specifications** for converting the ao486 from single-issue to dual-issue execution. Each section includes:
- File paths and line numbers
- Specific signal additions
- Code snippets showing before/after
- Module interface changes

**Target audience:** Engineers implementing the dual-issue pipeline

**Status:** Specification only - implementation requires 220+ hours

---

## Executive Summary

**Challenge:** The ao486 pipeline is fundamentally single-issue. Every stage assumes exactly one instruction flows through per cycle.

**Solution:** Three architectural changes required:
1. **Instruction Buffering:** Queue instructions after READ to enable look-ahead
2. **Dispatch Logic:** Select up to 2 instructions for parallel execution
3. **Dual Execution:** Route to ALU0/ALU1 in parallel

**Key Insight:** We don't need dual-FETCH or dual-DECODE initially. Single-issue decode feeding an instruction queue can achieve dual-issue execution.

---

## Architecture Overview

### Current Single-Issue Pipeline
```
FETCH(1) → DECODE(1) → MICROCODE → READ(1) → EXECUTE(1) → WRITE(1)
                                                  │
                                                  └─ Single ALU
```

### Target Dual-Issue Pipeline
```
FETCH(1) → DECODE(1) → MICROCODE → READ(1) → QUEUE(4) → DISPATCH → EXECUTE(2) → WRITE(2)
                                                            │           │
                                                            │           ├─ ALU0
                                                            │           └─ ALU1
                                                            │
                                                            └─ Dependency Check
```

**Key Points:**
- FETCH/DECODE remain single-issue (simpler initial implementation)
- Instruction queue buffers 4 decoded instructions
- Dispatch examines next 2 instructions and decides: dual-issue or single-issue
- Two ALUs execute in parallel when dispatch allows
- WRITE stage handles up to 2 results per cycle

---

## Phase 1: Instruction Queue (Week 1-2)

### 1.1 Create Instruction Queue Module

**File:** `rtl/ao486/pipeline/instruction_queue.v` (NEW FILE)

**Purpose:** Buffer 4 decoded instructions to enable look-ahead dispatch

**Interface:**
```verilog
module instruction_queue(
    input               clk,
    input               rst_n,
    input               queue_reset,

    // Input from READ stage (enqueue)
    input               rd_ready,           // Instruction valid
    input       [6:0]   rd_cmd,
    input       [3:0]   rd_cmdex,
    input       [10:0]  rd_mutex_next,     // Resource usage bits
    input       [31:0]  src_wire,          // Source operand
    input       [31:0]  dst_wire,          // Destination operand
    input               rd_is_8bit,
    input               rd_dst_is_reg,

    // Output to DISPATCH (head of queue)
    output              inst0_valid,
    output      [6:0]   inst0_cmd,
    output      [3:0]   inst0_cmdex,
    output      [10:0]  inst0_mutex,
    output      [31:0]  inst0_src,
    output      [31:0]  inst0_dst,
    output              inst0_is_8bit,

    // Output to DISPATCH (second in queue)
    output              inst1_valid,
    output      [6:0]   inst1_cmd,
    output      [3:0]   inst1_cmdex,
    output      [10:0]  inst1_mutex,
    output      [31:0]  inst1_src,
    output      [31:0]  inst1_dst,
    output              inst1_is_8bit,

    // Control from DISPATCH
    input               dispatch_inst0,    // Consumed inst0
    input               dispatch_inst1,    // Consumed inst1

    output              queue_full,
    output              queue_empty,
    output      [2:0]   queue_count
);
```

**Implementation:** See `/home/user/ao486_MiSTer/rtl/ao486/pipeline/instruction_queue.v` (already created)

---

### 1.2 Wire Queue into Pipeline.v

**File:** `rtl/ao486/pipeline/pipeline.v`

**Location:** After READ stage (around line 872)

**Step 1:** Add wire declarations (after line 872):
```verilog
//------------------------------------------------------------------------------
// Instruction Queue for Dual-Issue Dispatch
//------------------------------------------------------------------------------

wire        queue_reset;
wire        inst0_valid;
wire [6:0]  inst0_cmd_q;
wire [3:0]  inst0_cmdex_q;
wire [10:0] inst0_mutex_q;
wire [31:0] inst0_src_q;
wire [31:0] inst0_dst_q;
wire        inst0_is_8bit_q;

wire        inst1_valid;
wire [6:0]  inst1_cmd_q;
wire [3:0]  inst1_cmdex_q;
wire [10:0] inst1_mutex_q;
wire [31:0] inst1_src_q;
wire [31:0] inst1_dst_q;
wire        inst1_is_8bit_q;

wire        dispatch_inst0;
wire        dispatch_inst1;
wire        queue_full;
wire        queue_empty;
wire [2:0]  queue_count;

assign queue_reset = exe_reset;  // Reset queue when pipeline resets
```

**Step 2:** Instantiate instruction_queue (after line ~873):
```verilog
instruction_queue iq_inst(
    .clk                (clk),
    .rst_n              (rst_n),
    .queue_reset        (queue_reset),

    // From READ stage
    .rd_ready           (rd_ready),
    .rd_cmd             (rd_cmd),
    .rd_cmdex           (rd_cmdex),
    .rd_mutex_next      (rd_mutex_next),
    .src_wire           (src_wire),
    .dst_wire           (dst_wire),
    .rd_is_8bit         (rd_is_8bit),
    .rd_dst_is_reg      (rd_dst_is_reg),

    // To DISPATCH
    .inst0_valid        (inst0_valid),
    .inst0_cmd          (inst0_cmd_q),
    .inst0_cmdex        (inst0_cmdex_q),
    .inst0_mutex        (inst0_mutex_q),
    .inst0_src          (inst0_src_q),
    .inst0_dst          (inst0_dst_q),
    .inst0_is_8bit      (inst0_is_8bit_q),

    .inst1_valid        (inst1_valid),
    .inst1_cmd          (inst1_cmd_q),
    .inst1_cmdex        (inst1_cmdex_q),
    .inst1_mutex        (inst1_mutex_q),
    .inst1_src          (inst1_src_q),
    .inst1_dst          (inst1_dst_q),
    .inst1_is_8bit      (inst1_is_8bit_q),

    // From DISPATCH
    .dispatch_inst0     (dispatch_inst0),
    .dispatch_inst1     (dispatch_inst1),

    .queue_full         (queue_full),
    .queue_empty        (queue_empty),
    .queue_count        (queue_count)
);
```

**Step 3:** Modify pipeline control to handle queue fullness:

Find the `rd_busy` assignment (around line 668) and modify:
```verilog
// Before:
wire rd_busy;

// After:
wire rd_busy_original;
wire rd_busy;
assign rd_busy = rd_busy_original || queue_full;  // Stall READ if queue is full
```

---

## Phase 2: Dispatch Integration (Week 3-4)

### 2.1 Add Resource Tracking

**File:** `rtl/ao486/pipeline/pipeline.v`

**Location:** After EXECUTE stage instantiation (around line 1200)

**Purpose:** Track which execution units are busy

```verilog
//------------------------------------------------------------------------------
// Execution Unit Status Tracking
//------------------------------------------------------------------------------

reg alu0_busy_reg;
reg alu1_busy_reg;
reg mult_busy_reg;
reg div_busy_reg;
reg mem_busy_reg;

wire alu0_available = !alu0_busy_reg;
wire alu1_available = !alu1_busy_reg;
wire mult_available = !mult_busy_reg;
wire div_available = !div_busy_reg;
wire mem_available = !mem_busy_reg;

// Update busy status based on what's currently executing
// (Implementation depends on execute stage modifications in Phase 4)
always @(posedge clk) begin
    if (rst_n == 1'b0) begin
        alu0_busy_reg <= 1'b0;
        alu1_busy_reg <= 1'b0;
        mult_busy_reg <= 1'b0;
        div_busy_reg <= 1'b0;
        mem_busy_reg <= 1'b0;
    end
    else begin
        // ALUs are busy for 1 cycle (simple ops)
        alu0_busy_reg <= dispatch_inst0 && inst0_to_alu0;
        alu1_busy_reg <= (dispatch_inst0 && inst0_to_alu1) ||
                        (dispatch_inst1 && inst1_to_alu1);

        // Mult/Div stay busy for multiple cycles
        // (Needs integration with execute_multiply.v and execute_divide.v)
        mult_busy_reg <= mult_busy_reg;  // Placeholder
        div_busy_reg <= div_busy_reg;    // Placeholder
        mem_busy_reg <= mem_busy_reg;    // Placeholder
    end
end
```

---

### 2.2 Instantiate Dispatch Module

**File:** `rtl/ao486/pipeline/pipeline.v`

**Location:** After instruction_queue instantiation

```verilog
//------------------------------------------------------------------------------
// Dispatch Logic - Decides which instructions to issue
//------------------------------------------------------------------------------

wire        inst0_to_alu0;
wire        inst0_to_alu1;
wire        inst1_to_alu0;
wire        inst1_to_alu1;
wire        dual_issue;
wire        stall_dependency;
wire        stall_structural;

// Pipeline mutex tracking (already exists but may need aggregation)
wire [10:0] pipeline_mutex;
assign pipeline_mutex = exe_mutex | wr_mutex;

dispatch dispatch_inst(
    .clk                (clk),
    .rst_n              (rst_n),
    .dispatch_reset     (exe_reset),

    // Instruction 0 from queue
    .inst0_valid        (inst0_valid),
    .inst0_cmd          (inst0_cmd_q),
    .inst0_cmdex        (inst0_cmdex_q),
    .inst0_mutex        (inst0_mutex_q),
    .inst0_uses_alu     (inst0_uses_alu_w),     // Derived from cmd
    .inst0_uses_mult    (inst0_uses_mult_w),    // Derived from cmd
    .inst0_uses_div     (inst0_uses_div_w),     // Derived from cmd
    .inst0_uses_memory  (inst0_uses_memory_w),  // Derived from cmd
    .inst0_is_branch    (inst0_is_branch_w),    // Derived from cmd
    .inst0_is_complex   (inst0_is_complex_w),   // Derived from cmd

    // Instruction 1 from queue
    .inst1_valid        (inst1_valid),
    .inst1_cmd          (inst1_cmd_q),
    .inst1_cmdex        (inst1_cmdex_q),
    .inst1_mutex        (inst1_mutex_q),
    .inst1_uses_alu     (inst1_uses_alu_w),
    .inst1_uses_mult    (inst1_uses_mult_w),
    .inst1_uses_div     (inst1_uses_div_w),
    .inst1_uses_memory  (inst1_uses_memory_w),
    .inst1_is_branch    (inst1_is_branch_w),
    .inst1_is_complex   (inst1_is_complex_w),

    // Resource availability
    .alu0_busy          (!alu0_available),
    .alu1_busy          (!alu1_available),
    .mult_busy          (!mult_available),
    .div_busy           (!div_available),
    .mem_busy           (!mem_available),

    // Pipeline state
    .pipeline_mutex     (pipeline_mutex),

    // Dispatch decisions (outputs)
    .dispatch_inst0     (dispatch_inst0),
    .dispatch_inst1     (dispatch_inst1),
    .inst0_to_alu0      (inst0_to_alu0),
    .inst0_to_alu1      (inst0_to_alu1),
    .inst1_to_alu0      (inst1_to_alu0),
    .inst1_to_alu1      (inst1_to_alu1),
    .dual_issue         (dual_issue),
    .stall_dependency   (stall_dependency),
    .stall_structural   (stall_structural)
);
```

---

### 2.3 Add Instruction Classification Helper Logic

**File:** `rtl/ao486/pipeline/pipeline.v`

**Location:** Before dispatch instantiation

**Purpose:** Determine resource usage from cmd (since these signals aren't in READ stage)

```verilog
//------------------------------------------------------------------------------
// Instruction Classification for Dispatch
// Determine resource usage based on cmd value
//------------------------------------------------------------------------------

// Instruction 0 classification
wire inst0_uses_alu_w;
wire inst0_uses_mult_w;
wire inst0_uses_div_w;
wire inst0_uses_memory_w;
wire inst0_is_branch_w;
wire inst0_is_complex_w;

assign inst0_uses_mult_w = (inst0_cmd_q == 7'd59) ||  // MUL
                           (inst0_cmd_q == 7'd54);     // IMUL

assign inst0_uses_div_w  = (inst0_cmd_q == 7'd42) ||  // DIV
                           (inst0_cmd_q == 7'd43) ||  // IDIV
                           (inst0_cmd_q == 7'd32);    // AAM

assign inst0_is_branch_w = (inst0_cmd_q == 7'd8)  ||  // Jcc
                           (inst0_cmd_q == 7'd2)  ||  // JCXZ
                           (inst0_cmd_q == 7'd60) ||  // LOOP
                           (inst0_cmd_q == 7'd87) ||  // JMP
                           (inst0_cmd_q == 7'd3)  ||  // CALL
                           (inst0_cmd_q == 7'd15) ||  // RET_near
                           (inst0_cmd_q == 7'd63) ||  // RET_far
                           (inst0_cmd_q == 7'd75) ||  // INT_INTO
                           (inst0_cmd_q == 7'd35);    // IRET

// Most ALU operations
assign inst0_uses_alu_w = inst0_valid &&
                          !inst0_uses_mult_w &&
                          !inst0_uses_div_w &&
                          !inst0_uses_memory_w &&
                          !inst0_is_complex_w;

assign inst0_uses_memory_w = (inst0_mutex_q[`MUTEX_MEMORY_BIT] == 1'b1);
assign inst0_is_complex_w = 1'b0;  // Would need to propagate from READ stage

// Instruction 1 classification (same logic)
wire inst1_uses_alu_w;
wire inst1_uses_mult_w;
wire inst1_uses_div_w;
wire inst1_uses_memory_w;
wire inst1_is_branch_w;
wire inst1_is_complex_w;

assign inst1_uses_mult_w = (inst1_cmd_q == 7'd59) || (inst1_cmd_q == 7'd54);
assign inst1_uses_div_w  = (inst1_cmd_q == 7'd42) || (inst1_cmd_q == 7'd43) || (inst1_cmd_q == 7'd32);
assign inst1_is_branch_w = (inst1_cmd_q == 7'd8) || (inst1_cmd_q == 7'd2) || (inst1_cmd_q == 7'd60) ||
                           (inst1_cmd_q == 7'd87) || (inst1_cmd_q == 7'd3) || (inst1_cmd_q == 7'd15) ||
                           (inst1_cmd_q == 7'd63) || (inst1_cmd_q == 7'd75) || (inst1_cmd_q == 7'd35);
assign inst1_uses_alu_w = inst1_valid && !inst1_uses_mult_w && !inst1_uses_div_w &&
                          !inst1_uses_memory_w && !inst1_is_complex_w;
assign inst1_uses_memory_w = (inst1_mutex_q[`MUTEX_MEMORY_BIT] == 1'b1);
assign inst1_is_complex_w = 1'b0;
```

---

## Phase 3: Dual Execution (Week 5-6)

### 3.1 Integrate dual_execute.v as ALU1

**File:** `rtl/ao486/pipeline/pipeline.v`

**Location:** After existing execute instantiation (around line 1200)

**Current execute becomes ALU0, dual_execute becomes ALU1**

```verilog
//------------------------------------------------------------------------------
// ALU1 - Second Execution Unit
//------------------------------------------------------------------------------

wire        alu1_valid;
wire [6:0]  alu1_cmd;
wire [3:0]  alu1_cmdex;
wire [31:0] alu1_src;
wire [31:0] alu1_dst;
wire        alu1_is_8bit;
wire [31:0] alu1_result;
wire        alu1_done;
wire [8:0]  alu1_flags;    // {OF, DF, IF, TF, SF, ZF, AF, PF, CF}

// Route instruction to ALU1 based on dispatch decision
assign alu1_valid = (dispatch_inst0 && inst0_to_alu1) ||
                    (dispatch_inst1 && inst1_to_alu1);

assign alu1_cmd = (dispatch_inst0 && inst0_to_alu1) ? inst0_cmd_q :
                  (dispatch_inst1 && inst1_to_alu1) ? inst1_cmd_q : 7'd0;

assign alu1_cmdex = (dispatch_inst0 && inst0_to_alu1) ? inst0_cmdex_q :
                    (dispatch_inst1 && inst1_to_alu1) ? inst1_cmdex_q : 4'd0;

assign alu1_src = (dispatch_inst0 && inst0_to_alu1) ? inst0_src_q :
                  (dispatch_inst1 && inst1_to_alu1) ? inst1_src_q : 32'd0;

assign alu1_dst = (dispatch_inst0 && inst0_to_alu1) ? inst0_dst_q :
                  (dispatch_inst1 && inst1_to_alu1) ? inst1_dst_q : 32'd0;

assign alu1_is_8bit = (dispatch_inst0 && inst0_to_alu1) ? inst0_is_8bit_q :
                      (dispatch_inst1 && inst1_to_alu1) ? inst1_is_8bit_q : 1'b0;

dual_execute alu1_inst(
    .clk                (clk),
    .rst_n              (rst_n),

    // ALU0 inputs
    .alu0_valid         (dispatch_inst0 && inst0_to_alu1),  // Only if routed to ALU1
    .alu0_cmd           (alu1_cmd),
    .alu0_dst           (alu1_dst),
    .alu0_src           (alu1_src),
    .alu0_is_8bit       (alu1_is_8bit),
    .alu0_uses_mult     (1'b0),  // Multiplier is shared with main execute
    .alu0_uses_div      (1'b0),  // Divider is shared with main execute

    // ALU1 inputs
    .alu1_valid         (dispatch_inst1 && inst1_to_alu1),
    .alu1_cmd           (inst1_cmd_q),
    .alu1_dst           (inst1_dst_q),
    .alu1_src           (inst1_src_q),
    .alu1_is_8bit       (inst1_is_8bit_q),
    .alu1_uses_mult     (1'b0),
    .alu1_uses_div      (1'b0),

    // Shared multiplier/divider control (not implemented yet)
    .mult_available     (mult_available),
    .div_available      (div_available),

    // Outputs
    .alu0_result        (alu1_result),     // Result from whichever ALU processed
    .alu0_done          (alu1_done),
    .alu0_flags         (alu1_flags),

    .alu1_result        (),  // Second result (if both ALUs active)
    .alu1_done          (),
    .alu1_flags         ()
);
```

**Note:** dual_execute.v has both ALU0 and ALU1 internally. We're using it as "ALU1" from the pipeline perspective.

---

### 3.2 Modify Existing execute.v (ALU0)

**File:** `rtl/ao486/pipeline/execute.v`

**No changes required initially** - The existing execute module becomes ALU0 automatically.

However, need to **add input to indicate whether this is a dual-issue cycle**:

Around line 30, add input:
```verilog
input               dual_issue_active,  // Another instruction executing in parallel
```

This can be used later for:
- Multiplier/divider arbitration
- Ensuring atomic memory operations don't happen in parallel

Connect in pipeline.v:
```verilog
execute execute_inst(
    // ... existing connections ...
    .dual_issue_active  (dual_issue),    // From dispatch
    // ... rest of connections ...
);
```

---

## Phase 4: Dual Writeback (Week 7-8)

### 4.1 Modify WRITE Stage for Dual Results

**File:** `rtl/ao486/pipeline/write_register.v`

**Location:** Around line 100 (register write logic)

**Current:** Single result written per cycle
**Target:** Up to 2 results written per cycle

**Challenge:** Register file needs dual write ports

**Changes needed:**

1. **Add second set of write inputs** (around line 30):
```verilog
// Existing write port 0
input               wr_eax,
input               wr_ecx,
// ... etc

// NEW: Write port 1 (from ALU1)
input               wr1_eax,
input               wr1_ecx,
input               wr1_edx,
input               wr1_ebx,
input               wr1_esp,
input               wr1_ebp,
input               wr1_esi,
input               wr1_edi,

input       [31:0]  wr1_result,
input               wr1_valid,
```

2. **Modify register write logic** (around line 150):
```verilog
// Before (single write):
always @(posedge clk) begin
    if (rst_n == 1'b0)
        eax <= 32'd0;
    else if (wr_eax)
        eax <= wr_result;
end

// After (dual write with priority):
always @(posedge clk) begin
    if (rst_n == 1'b0)
        eax <= 32'd0;
    else if (wr_eax && wr1_eax) begin
        // Both trying to write EAX - ERROR (shouldn't happen with correct dispatch)
        eax <= wr_result;  // Port 0 wins
    end
    else if (wr_eax)
        eax <= wr_result;
    else if (wr1_eax)
        eax <= wr1_result;
end
```

**Repeat for all 8 registers (EAX, ECX, EDX, EBX, ESP, EBP, ESI, EDI)**

---

### 4.2 Wire ALU1 Results to WRITE Stage

**File:** `rtl/ao486/pipeline/pipeline.v`

**Location:** In write_register instantiation (around line 1400)

```verilog
write_register write_register_inst(
    .clk                (clk),
    .rst_n              (rst_n),

    // ... existing port 0 connections ...

    // NEW: Port 1 connections from ALU1
    .wr1_valid          (alu1_done),
    .wr1_result         (alu1_result),

    // Determine which register ALU1 is writing
    // (This requires tracking destination register through dispatch)
    .wr1_eax            (alu1_dst_is_eax),    // Need to add this signal
    .wr1_ecx            (alu1_dst_is_ecx),
    .wr1_edx            (alu1_dst_is_edx),
    .wr1_ebx            (alu1_dst_is_ebx),
    .wr1_esp            (alu1_dst_is_esp),
    .wr1_ebp            (alu1_dst_is_ebp),
    .wr1_esi            (alu1_dst_is_esi),
    .wr1_edi            (alu1_dst_is_edi),

    // ... rest of connections ...
);
```

**Note:** Need to track destination register identity through execution. Add pipeline registers:

```verilog
// After dispatch, track which register ALU1 will write
reg [2:0] alu1_dst_reg_r;
reg       alu1_dst_is_reg_r;

always @(posedge clk) begin
    if (rst_n == 1'b0) begin
        alu1_dst_reg_r <= 3'd0;
        alu1_dst_is_reg_r <= 1'b0;
    end
    else if (alu1_valid) begin
        alu1_dst_reg_r <= alu1_dst_reg;       // From queue
        alu1_dst_is_reg_r <= alu1_dst_is_reg;
    end
end

// Decode which register based on 3-bit encoding
wire alu1_dst_is_eax = alu1_dst_is_reg_r && (alu1_dst_reg_r == 3'd0);
wire alu1_dst_is_ecx = alu1_dst_is_reg_r && (alu1_dst_reg_r == 3'd1);
wire alu1_dst_is_edx = alu1_dst_is_reg_r && (alu1_dst_reg_r == 3'd2);
wire alu1_dst_is_ebx = alu1_dst_is_reg_r && (alu1_dst_reg_r == 3'd3);
wire alu1_dst_is_esp = alu1_dst_is_reg_r && (alu1_dst_reg_r == 3'd4);
wire alu1_dst_is_ebp = alu1_dst_is_reg_r && (alu1_dst_reg_r == 3'd5);
wire alu1_dst_is_esi = alu1_dst_is_reg_r && (alu1_dst_reg_r == 3'd6);
wire alu1_dst_is_edi = alu1_dst_is_reg_r && (alu1_dst_reg_r == 3'd7);
```

---

## Phase 5: Pipeline Control (Week 9-10)

### 5.1 Modify Stall Logic

**File:** `rtl/ao486/pipeline/pipeline.v`

**Location:** Pipeline control section (search for "dec_reset", "rd_reset", "exe_reset")

**Current stall conditions:**
- `exe_busy` stalls everything upstream
- `rd_busy` stalls decode
- `micro_busy` stalls decode

**New stall conditions:**
- Queue full → stall READ stage
- Dispatch dependency stall → don't dequeue from instruction queue
- Dispatch structural hazard → don't dequeue from instruction queue

**Modifications:**

Find `rd_reset` generation (around line 440):
```verilog
// Before:
assign rd_reset = /* existing conditions */;

// After:
assign rd_reset = /* existing conditions */ || queue_full;
```

Find `exe_reset` generation:
```verilog
// Before:
assign exe_reset = /* existing conditions */;

// After:
assign exe_reset = /* existing conditions */ || (stall_dependency && inst0_valid);
```

---

### 5.2 Handle Branch Mispredictions

**File:** `rtl/ao486/pipeline/pipeline.v`

**Challenge:** If instruction 0 is a branch, instruction 1 may be speculative

**Solution:** Don't dual-issue if inst0 is a branch (already handled by dispatch.v)

**Verify in dispatch.v** (line 177-185):
```verilog
// Branch serialization - inst0 branch prevents dual issue
wire inst0_serializes = inst0_is_branch || inst0_is_complex || inst0_uses_memory;
wire inst1_blocked_by_inst0 = inst0_serializes && inst1_valid;

assign can_dispatch_inst1 =
    inst1_valid &&
    !inst1_has_dependency &&
    !raw_dependency_01 &&
    !inst1_blocked_by_inst0 &&  // <-- Prevents dual-issue with branches
    inst1_alu_ok &&
    inst1_mult_ok &&
    inst1_div_ok &&
    inst1_mem_ok;
```

This already exists in dispatch.v, so no changes needed here.

---

### 5.3 Exception Handling

**File:** `rtl/ao486/pipeline/pipeline.v`

**Challenge:** What if both ALU0 and ALU1 generate exceptions?

**Solution:** Exception priority

**Rule:** ALU0 (program-order first instruction) has priority

```verilog
// Exception handling for dual-issue
wire alu0_exception = exe_exception;  // From existing execute
wire alu1_exception = alu1_exception_signal;  // From dual_execute

wire exception_occurred = alu0_exception || alu1_exception;
wire exception_vector_final = alu0_exception ? exe_exception_vector : alu1_exception_vector;

// If ALU0 exceptions, flush ALU1 result
wire alu1_result_valid = alu1_done && !alu0_exception;
```

Use `alu1_result_valid` instead of `alu1_done` when writing back ALU1 results.

---

## Phase 6: Testing & Verification (Week 11-12)

### 6.1 Unit Tests

**Test 1: Instruction Queue**
- Verify enqueue/dequeue logic
- Test queue full/empty conditions
- Verify head/tail pointer wraparound

**Test 2: Dispatch Logic**
- Test dependency detection (RAW, WAW, WAR)
- Test resource conflict detection
- Verify dual-issue decisions
- **Existing:** `sim/superscalar/tb_dispatch.v` (8 test cases)

**Test 3: Dual Execute**
- Verify both ALUs produce correct results
- Test parallel execution of independent instructions
- Verify multiplier/divider sharing (when implemented)

---

### 6.2 Integration Tests

**Test Sequence 1: Simple Dual-Issue**
```assembly
MOV EAX, 1    ; inst0 - ALU operation
MOV EBX, 2    ; inst1 - ALU operation, no dependency
; Both should issue in parallel
```

**Expected:**
- Both instructions in queue
- `dual_issue = 1`
- ALU0 executes MOV EAX
- ALU1 executes MOV EBX
- Both write back in same cycle

**Test Sequence 2: Dependency Stall**
```assembly
MOV EAX, 1    ; inst0
ADD EAX, 2    ; inst1 - depends on EAX from inst0
; Should NOT dual-issue (RAW dependency)
```

**Expected:**
- `dual_issue = 0`
- Only inst0 dispatches
- inst1 waits in queue
- inst1 dispatches next cycle after inst0 completes

**Test Sequence 3: Resource Conflict**
```assembly
MUL EBX       ; inst0 - uses multiplier
IMUL ECX      ; inst1 - also needs multiplier
; Should NOT dual-issue (structural hazard)
```

**Expected:**
- `stall_structural = 1`
- Only inst0 dispatches
- inst1 waits until multiplier free

---

### 6.3 Performance Measurement

**Metric: Instructions Per Cycle (IPC)**

**Measurement Points:**
1. Total cycles elapsed
2. Total instructions dispatched
3. Dual-issue rate (% of cycles with 2 instructions)

**Example Counter Logic:**
```verilog
reg [31:0] total_cycles;
reg [31:0] total_inst_dispatched;
reg [31:0] dual_issue_cycles;

always @(posedge clk) begin
    if (rst_n == 1'b0) begin
        total_cycles <= 32'd0;
        total_inst_dispatched <= 32'd0;
        dual_issue_cycles <= 32'd0;
    end
    else begin
        total_cycles <= total_cycles + 32'd1;
        total_inst_dispatched <= total_inst_dispatched +
                                 {31'd0, dispatch_inst0} +
                                 {31'd0, dispatch_inst1};
        if (dual_issue)
            dual_issue_cycles <= dual_issue_cycles + 32'd1;
    end
end

wire [31:0] ipc_times_100 = (total_inst_dispatched * 100) / total_cycles;
wire [31:0] dual_issue_percent = (dual_issue_cycles * 100) / total_cycles;
```

**Target Performance:**
- Baseline single-issue: IPC = 1.0 (100)
- Dual-issue target: IPC = 1.3-1.5 (130-150)
- Dual-issue rate: 30-50% of cycles

---

## Critical Path Analysis

### Timing Concerns

**Potential Critical Paths:**
1. **Dispatch decision logic** - Complex dependency checking
2. **Instruction queue dequeue logic** - Pointer arithmetic
3. **Dual register writeback** - Two sources to one register file

**Mitigation:**
- Pipeline dispatch decision if needed (adds 1 cycle latency)
- Pre-compute queue pointers
- Ensure register file has dual-port capability

---

## Known Limitations & Future Work

### Current Limitations

1. **No dual-FETCH:** Still fetches 1 instruction/cycle
   - Limits sustained dual-issue rate
   - Future: Implement fetch buffer for 2 instructions

2. **No dual-DECODE:** Still decodes 1 instruction/cycle
   - Instruction queue can become bottleneck
   - Future: Instantiate decode module twice

3. **Memory operations serialized:** Can't dual-issue loads/stores
   - Dispatch prevents this (inst_uses_memory check)
   - Future: Add dual-port data cache

4. **No speculation:** Branches always serialize
   - Conservative but correct
   - Future: Add branch prediction

5. **No out-of-order execution:** Instructions issue in program order
   - Simpler but lower performance
   - Future: Add reservation stations

---

## Estimated Effort Breakdown

| Phase | Task | Hours |
|-------|------|-------|
| 1 | Instruction Queue | 20 |
| 1 | Wire into Pipeline | 10 |
| 2 | Resource Tracking | 15 |
| 2 | Dispatch Integration | 25 |
| 3 | Dual Execute Integration | 30 |
| 3 | ALU Routing Logic | 20 |
| 4 | Dual Writeback | 35 |
| 4 | Destination Tracking | 15 |
| 5 | Pipeline Control | 25 |
| 5 | Exception Handling | 15 |
| 6 | Unit Testing | 20 |
| 6 | Integration Testing | 30 |
| 6 | Performance Tuning | 10 |
| **TOTAL** | | **270 hours** |

(Updated from 220 hours to account for detailed implementation)

---

## Conclusion

This specification provides a **concrete implementation path** for dual-issue execution without requiring dual-FETCH or dual-DECODE initially. The approach:

✅ **Preserves existing single-issue pipeline**
✅ **Adds dual-issue capability incrementally**
✅ **Tests at each phase**
✅ **Provides measurable performance improvement**

**Next Steps:**
1. Implement Phase 1 (Instruction Queue)
2. Verify queue operation in isolation
3. Proceed to Phase 2 (Dispatch)
4. Continue through phases sequentially

**Success Criteria:**
- IPC improvement from 1.0 to 1.3+
- No functional regressions
- All existing tests pass
- New dual-issue tests pass

The design is conservative (in-order, no speculation) but achieves meaningful performance improvement with manageable complexity.
