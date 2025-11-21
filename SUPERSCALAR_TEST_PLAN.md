# Superscalar ao486 Test Plan

**Date:** 2025-11-21
**Status:** Phase 1-5 Complete, Phase 6 Testing In Progress
**Branch:** claude/analyze-cpu-performance-011CUsmq155WnsaN7CoBPWvu

---

## Test Plan Overview

This document provides comprehensive test scenarios to validate the dual-issue superscalar implementation. Tests are organized by component and functionality.

**Testing Goals:**
1. ✅ Verify functional correctness (no architectural violations)
2. ✅ Validate exception handling and priority
3. ✅ Confirm branch and control flow handling
4. ✅ Measure performance (IPC, dual-issue rate)
5. ✅ Identify and fix any bugs

**Testing Phases:**
- **Unit Tests:** Individual component validation
- **Integration Tests:** End-to-end scenarios
- **Edge Case Tests:** Corner cases and error conditions
- **Performance Tests:** IPC measurement and profiling

---

## Unit Tests

### 1. Instruction Queue Tests

**Location:** `rtl/ao486/pipeline/instruction_queue.v`

#### Test 1.1: Basic Enqueue/Dequeue
```verilog
// Test basic FIFO behavior
Scenario:
1. Enqueue 4 instructions sequentially
2. Verify queue_full asserts
3. Dequeue 2 instructions (dual-issue)
4. Verify queue_count = 2
5. Dequeue remaining 2 instructions
6. Verify queue_empty asserts

Expected: Queue fills, empties correctly with proper counts
```

#### Test 1.2: Queue Reset
```verilog
// Test queue flush on reset
Scenario:
1. Fill queue with 3 instructions
2. Assert queue_reset
3. Check all outputs invalid next cycle

Expected: Queue clears immediately, queue_empty=1
```

#### Test 1.3: ModR/M Tracking
```verilog
// Test destination register tracking
Scenario:
1. Enqueue: MOV EAX, 1 (modregrm = 6'b000_000)
2. Enqueue: MOV EBX, 2 (modregrm = 6'b011_011)
3. Read inst0_modregrm and inst1_modregrm

Expected:
- inst0_modregrm = 6'b000_000 (EAX)
- inst1_modregrm = 6'b011_011 (EBX)
```

#### Test 1.4: Queue Stall
```verilog
// Test backpressure when queue full
Scenario:
1. Fill queue (4 instructions)
2. Try to enqueue 5th instruction
3. Verify queue_full prevents enqueue

Expected: 5th instruction waits, queue_count stays at 4
```

---

### 2. Dispatch Logic Tests

**Location:** `rtl/ao486/pipeline/dispatch.v`

#### Test 2.1: Dependency Detection - RAW
```verilog
// Read-After-Write dependency
Scenario:
Inst0: MOV EAX, 1    (writes EAX, mutex[0]=1)
Inst1: ADD EBX, EAX  (reads EAX, mutex[0]=1)

Expected:
- stall_dependency = 1
- dispatch_inst0 = 1
- dispatch_inst1 = 0  (stalled due to dependency)
- dual_issue = 0
```

#### Test 2.2: No Dependency
```verilog
// Independent instructions
Scenario:
Inst0: MOV EAX, 1    (writes EAX, mutex[0]=1)
Inst1: MOV EBX, 2    (writes EBX, mutex[3]=1)

Expected:
- stall_dependency = 0
- dispatch_inst0 = 1
- dispatch_inst1 = 1  (no conflict)
- dual_issue = 1      ← KEY TEST
```

#### Test 2.3: Resource Conflict
```verilog
// Both need multiplier
Scenario:
Inst0: IMUL EAX, EBX  (uses_mult=1)
Inst1: IMUL ECX, EDX  (uses_mult=1)

Expected:
- resource_conflict = 1
- dispatch_inst0 = 1
- dispatch_inst1 = 0  (structural hazard)
- dual_issue = 0
```

#### Test 2.4: Branch Serialization
```verilog
// Branches force single-issue
Scenario:
Inst0: JNZ label     (is_branch=1, must_single_issue=1)
Inst1: MOV EAX, 1    (normal ALU op)

Expected:
- dispatch_inst0 = 1
- dispatch_inst1 = 0  (branch serializes)
- dual_issue = 0
```

#### Test 2.5: ALU Routing
```verilog
// Verify proper ALU assignment
Scenario:
Inst0: ADD EAX, EBX  (uses_alu=1)
Inst1: SUB ECX, EDX  (uses_alu=1)
Both: No dependencies, ALU0 and ALU1 available

Expected:
- inst0_to_alu0 = 1
- inst0_to_alu1 = 0
- inst1_to_alu0 = 0
- inst1_to_alu1 = 1  ← Inst1 goes to ALU1
- dual_issue = 1
```

---

### 3. Dual Execute Tests

**Location:** `rtl/ao486/pipeline/dual_execute.v`

#### Test 3.1: Dual ALU Operations
```verilog
// Both ALUs execute simultaneously
Scenario:
Cycle N:
  ALU0: ADD EAX, 5    (input: EAX=10)
  ALU1: SUB EBX, 3    (input: EBX=20)

Expected (Cycle N+1):
- alu0_ready = 1, alu0_result = 15
- alu1_ready = 1, alu1_result = 17
- Both results available same cycle
```

#### Test 3.2: Shared Multiplier
```verilog
// Multiplier used by ALU0
Scenario:
Cycle N:
  ALU0: IMUL EAX, 5   (uses multiplier)
  ALU1: ADD EBX, 1    (uses ALU only)

Expected:
- ALU0 uses mult_div unit (multi-cycle)
- ALU1 completes in 1 cycle
- mult_div_busy = 1 while IMUL executes
```

#### Test 3.3: ALU Busy States
```verilog
// Resource tracking
Scenario:
Cycle N: Both ALUs idle
  alu0_busy = 0, alu1_busy = 0

Cycle N+1: Issue to both
  alu0_valid = 1, alu1_valid = 1

Cycle N+2: Executing
  alu0_busy = 1, alu1_busy = 1

Expected: Busy states prevent re-issue until complete
```

---

### 4. Writeback Tests

**Location:** `rtl/ao486/pipeline/write_register.v`

#### Test 4.1: Dual Writeback
```verilog
// Both ports write different registers
Scenario:
Cycle N: ALU0 writes EAX=15, ALU1 writes EBX=20
  w_write_regrm = 1, w_index = 0 (EAX)
  wr1_valid = 1, wr1_eax = 0, wr1_ebx = 1

Expected (Cycle N+1):
- EAX = 15  (from Port 0)
- EBX = 20  (from Port 1)
- Both update in same cycle
```

#### Test 4.2: Write Priority
```verilog
// Port 0 takes priority over Port 1
Scenario:
Cycle N: Both try to write EAX (should never happen, but test safety)
  w_write_regrm = 1, w_index = 0, result = 100
  wr1_valid = 1, wr1_eax = 1, wr1_result = 200

Expected (Cycle N+1):
- EAX = 100  (Port 0 wins)
```

#### Test 4.3: ESP Exception Priority
```verilog
// ESP write with exception restore
Scenario:
Cycle N:
  w_write_regrm = 0
  exc_restore_esp = 1, wr_esp_prev = 0x1000
  wr1_valid = 1, wr1_esp = 1, wr1_result = 0x2000

Expected (Cycle N+1):
- ESP = 0x1000  (Exception restore takes priority)
```

---

## Integration Tests

### 5. End-to-End Dual-Issue Tests

#### Test 5.1: Simple Dual-Issue
```asm
; Test basic dual-issue execution
MOV EAX, 1      ; Cycle 1: READ, enqueue
MOV EBX, 2      ; Cycle 2: READ, enqueue
                ; Cycle 3: Dispatch both (dual-issue)
                ;   ALU0: MOV EAX, 1
                ;   ALU1: MOV EBX, 2
                ; Cycle 4: Writeback both
                ;   EAX = 1, EBX = 2

Expected:
- 2 instructions complete in ~4 cycles
- Both writebacks occur in cycle 4
- IPC = 2/4 = 0.5 (limited by single-issue fetch/decode)
```

#### Test 5.2: Dependency Stall
```asm
; Test RAW dependency detection
MOV EAX, 10     ; Cycle 1-3: Execute
ADD EAX, 5      ; Cycle 4: Stalls (depends on EAX)
                ; Cycle 5: Execute (EAX=15)

Expected:
- ADD stalls until MOV completes
- No dual-issue (dependency)
- IPC ≈ 1.0
```

#### Test 5.3: Mixed Independent/Dependent
```asm
; Test selective dual-issue
MOV EAX, 1      ; Inst 0
MOV EBX, 2      ; Inst 1 - Can dual-issue with 0
ADD ECX, EDX    ; Inst 2 - Can dual-issue with 1
ADD EAX, EBX    ; Inst 3 - Depends on 0 and 1, stalls

Expected:
- Cycle 1: Inst 0 + 1 dual-issue
- Cycle 2: Inst 2 single-issue (Inst 3 stalls)
- Cycle 3: Inst 3 single-issue
- IPC = 4/3 = 1.33
```

#### Test 5.4: Resource Conflict
```asm
; Test structural hazard
IMUL EAX, 5     ; Uses multiplier
IMUL EBX, 3     ; Also needs multiplier - conflict!

Expected:
- Inst 0 executes (multi-cycle)
- Inst 1 stalls (multiplier busy)
- No dual-issue
```

---

### 6. Exception and Control Flow Tests

#### Test 6.1: Exception During Dual-Issue
```asm
; Test exception priority
DIV EBX         ; Inst 0: Divide by zero (EBX=0)
MOV ECX, 5      ; Inst 1: Dual-issued with Inst 0

Scenario:
- Cycle N: Both dispatch (dual-issue)
- Cycle N+1: DIV causes exception
  - exe_reset = 1
  - alu1_valid_r cleared
- Cycle N+2: Exception handler

Expected:
- DIV exception handled
- MOV ECX result DISCARDED (alu1_valid_r=0)
- ECX unchanged
- Only Inst 0's exception visible
```

#### Test 6.2: Branch Serialization
```asm
; Branches don't dual-issue
JNZ label       ; Branch instruction
MOV EAX, 1      ; Following instruction

Expected:
- JNZ forces single-issue (inst0_must_single_issue=1)
- MOV dispatched after JNZ completes
- No dual-issue
```

#### Test 6.3: Pipeline Flush
```asm
; Test queue flush on misprediction
JZ label        ; Branch (predicted not taken, actually taken)
MOV EAX, 1      ; Speculatively fetched
MOV EBX, 2      ; Speculatively fetched

Scenario:
- Queue fills with MOV instructions
- JZ mispredicts → exe_reset
- queue_reset flushes queue

Expected:
- Both MOV instructions discarded
- Queue empty after flush
- Fetch resumes at 'label'
```

---

### 7. Performance Tests

#### Test 7.1: IPC Measurement
```asm
; Ideal case: All independent ALU ops
MOV EAX, 1
MOV EBX, 2
MOV ECX, 3
MOV EDX, 4
ADD ESI, 1
ADD EDI, 2
SUB EBP, 3
AND ESP, 0xFFF0

Expected:
- 8 instructions
- Pairs: (MOV EAX, MOV EBX), (MOV ECX, MOV EDX),
         (ADD ESI, ADD EDI), (SUB EBP, AND ESP)
- ~8-10 cycles total (fetch/decode limits)
- IPC ≈ 0.8-1.0
```

#### Test 7.2: Dual-Issue Rate
```asm
; Mixed workload
MOV EAX, 1      ; Can dual-issue
MOV EBX, 2      ; with previous
ADD EAX, EBX    ; Depends on both, stalls
MOV ECX, 3      ; Can dual-issue
MOV EDX, 4      ; with previous
IMUL EAX, 5     ; Single-issue (complex)

Expected:
- 6 instructions total
- 2 dual-issue pairs (Inst 0+1, Inst 3+4)
- Dual-issue rate = 4/6 = 66%
```

#### Test 7.3: Worst Case (Serial)
```asm
; All dependent
MOV EAX, 1
ADD EAX, 2      ; Depends on prev
ADD EAX, 3      ; Depends on prev
ADD EAX, 4      ; Depends on prev

Expected:
- 4 instructions
- No dual-issue (all dependencies)
- IPC = 1.0 (no better than single-issue)
```

---

## Edge Case Tests

### 8. Corner Cases

#### Test 8.1: Queue Overflow Prevention
```verilog
// Queue full with rapid dispatch
Scenario:
- Fill queue (4 instructions)
- Dispatch stalls (dependencies)
- READ tries to add 5th instruction

Expected:
- queue_full = 1
- rd_busy asserts
- READ stage stalls
- No queue overflow
```

#### Test 8.2: Simultaneous Exception and Branch
```asm
; Exception in branch delay slot (x86 doesn't have delay slots,
; but test exception during branch execution)
JZ label
DIV EBX         ; Divide by zero

Scenario:
- JZ single-issues (branches serialize)
- DIV executes after JZ
- DIV causes exception

Expected:
- JZ completes first
- DIV exception handled separately
- No dual-issue confusion
```

#### Test 8.3: Write After Exception
```asm
; Pending writeback during exception
ADD EAX, 1      ; In writeback stage
DIV EBX         ; In execute, causes exception

Scenario:
- ADD result in alu1_valid_r
- DIV causes exe_reset
- alu1_valid_r cleared

Expected:
- ADD result discarded if from ALU1
- Only committed results preserved
```

---

## Validation Checklist

### Functional Correctness
- [ ] All unit tests pass
- [ ] Dual-issue executes two instructions correctly
- [ ] Dependencies detected and handled
- [ ] Writebacks occur in same cycle
- [ ] No register corruption

### Exception Handling
- [ ] Exception priority (inst0 > inst1) enforced
- [ ] ALU1 writeback invalidated on exe_reset
- [ ] ALU1 writeback invalidated on wr_reset
- [ ] Queue flushes on pipeline reset
- [ ] No committed state from faulting inst1

### Control Flow
- [ ] Branches serialize (no dual-issue with branches)
- [ ] Pipeline flushes correctly on misprediction
- [ ] Queue clears on flush
- [ ] Complex instructions serialize

### Resource Management
- [ ] Multiplier sharing works correctly
- [ ] Divider operations serialize
- [ ] ALU0/ALU1 availability tracked
- [ ] Resource conflicts prevent dual-issue
- [ ] Memory operations serialize

### Performance
- [ ] Dual-issue rate > 0% (some parallelism)
- [ ] IPC > 1.0 on parallelizable code
- [ ] Queue utilization reasonable
- [ ] No unnecessary stalls

---

## Testing Methodology

### Simulation Setup

**Required Tools:**
- Icarus Verilog (iverilog) or ModelSim
- VCD waveform viewer (GTKWave)
- Test harness from original ao486

**Test Harness:**
```verilog
module tb_superscalar;
    reg clk;
    reg rst_n;

    // Instantiate ao486 pipeline
    pipeline dut (
        .clk(clk),
        .rst_n(rst_n),
        // ... other signals
    );

    // Clock generation
    initial begin
        clk = 0;
        forever #5 clk = ~clk;  // 100MHz
    end

    // Test sequence
    initial begin
        rst_n = 0;
        #20 rst_n = 1;

        // Load test program into memory
        // Run simulation
        // Check results

        #10000 $finish;
    end

    // Monitors
    always @(posedge clk) begin
        if (dual_issue)
            $display("DUAL-ISSUE: inst0=%h inst1=%h", inst0_cmd_q, inst1_cmd_q);
    end
endmodule
```

### Signal Monitoring

**Key signals to monitor:**
```verilog
// Dispatch
$monitor("queue_count=%d dual_issue=%b stall=%b",
         queue_count, dual_issue, stall_dependency);

// Execution
$monitor("ALU0: valid=%b busy=%b result=%h",
         alu0_valid_dual, alu0_busy_dual, alu0_result_dual);
$monitor("ALU1: valid=%b busy=%b result=%h",
         alu1_valid_dual, alu1_busy_dual, alu1_result_dual);

// Writeback
$monitor("WB: Port0=%b Port1=%b EAX=%h EBX=%h",
         w_write_regrm, wr1_valid, eax, ebx);

// Exceptions
$monitor("exe_reset=%b alu1_valid_r=%b",
         exe_reset, alu1_valid_r);
```

### Performance Metrics

**IPC Calculation:**
```verilog
reg [31:0] total_instructions;
reg [31:0] total_cycles;

always @(posedge clk) begin
    if (dispatch_inst0) total_instructions++;
    if (dispatch_inst1) total_instructions++;
    total_cycles++;
end

// IPC = total_instructions / total_cycles
```

**Dual-Issue Rate:**
```verilog
reg [31:0] dual_issue_count;
reg [31:0] dispatch_count;

always @(posedge clk) begin
    if (dispatch_inst0) dispatch_count++;
    if (dual_issue) dual_issue_count++;
end

// Rate = dual_issue_count / dispatch_count
```

---

## Expected Results

### Performance Targets

**IPC (Instructions Per Cycle):**
- Ideal parallelizable code: 1.5 - 2.0
- Typical x86 code: 1.2 - 1.4
- Serial code: 1.0

**Dual-Issue Rate:**
- Aggressive: 30-40% of dispatch cycles
- Conservative: 20-30%
- Worst case: 0-10%

**Bottlenecks:**
- Single fetch/decode limits input to 1 inst/cycle
- Queue depth limits look-ahead to 4 instructions
- Dependencies reduce dual-issue opportunities
- Shared resources (mult/div) serialize operations

### Success Criteria

**Minimum Requirements:**
✅ No functional bugs (all tests pass)
✅ Exception priority correct (inst0 > inst1)
✅ No architectural state corruption
✅ IPC ≥ 1.0 on parallel code

**Target Goals:**
🎯 IPC ≥ 1.3 on typical code
🎯 Dual-issue rate ≥ 25%
🎯 Zero pipeline violations
🎯 Correct exception handling in all cases

---

## Test Execution Plan

### Phase 1: Unit Tests (Week 1)
- Day 1-2: Instruction queue tests
- Day 3-4: Dispatch logic tests
- Day 5: Dual execute tests
- Day 6-7: Writeback tests

### Phase 2: Integration Tests (Week 2)
- Day 1-3: End-to-end dual-issue scenarios
- Day 4-5: Exception handling tests
- Day 6-7: Performance measurements

### Phase 3: Edge Cases (Week 3)
- Day 1-3: Corner case testing
- Day 4-5: Stress testing
- Day 6-7: Bug fixes

### Phase 4: Validation (Week 4)
- Day 1-3: Full regression suite
- Day 4-5: Performance tuning
- Day 6-7: Final verification

---

## Bug Tracking Template

```markdown
### Bug #N: [Title]

**Severity:** Critical | High | Medium | Low
**Component:** Queue | Dispatch | Execute | Writeback | Control

**Description:**
[What goes wrong]

**Reproduction:**
[Test case that triggers it]

**Expected:**
[What should happen]

**Actual:**
[What actually happens]

**Root Cause:**
[Analysis of the problem]

**Fix:**
[Solution implemented]

**Verification:**
[Test that confirms fix]
```

---

## Next Steps

1. **Set up simulation environment**
   - Install Icarus Verilog or ModelSim
   - Create test harness
   - Configure waveform viewer

2. **Run unit tests**
   - Start with instruction queue
   - Progress through each component
   - Fix bugs as found

3. **Run integration tests**
   - Test end-to-end scenarios
   - Validate exception handling
   - Measure performance

4. **Optimize and tune**
   - Adjust queue depth if needed
   - Tune dispatch policy
   - Improve IPC

5. **Final validation**
   - Run full test suite
   - Document results
   - Create performance report

---

**Test Plan Version:** 1.0
**Last Updated:** 2025-11-21
**Status:** Ready for execution
