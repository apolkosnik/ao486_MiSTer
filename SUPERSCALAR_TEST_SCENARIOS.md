# Superscalar ao486 Test Scenarios

## Overview
This document provides comprehensive test scenarios to validate the 2-way superscalar ao486 implementation after bug fixes. Tests are organized by complexity and coverage area.

---

## Basic Functional Tests

### Test 1: Simple Dual-Issue ALU Operations
**Objective:** Verify both ALUs execute independently and write results correctly

```asm
; Test dual-issue with independent operations
MOV EAX, 0x1000      ; inst0 → ALU0 or ALU1
MOV EBX, 0x2000      ; inst1 → ALU0 or ALU1 (independent)

ADD EAX, 0x0100      ; inst0
SUB EBX, 0x0200      ; inst1 (should dual-issue if no dependency)

; Expected results:
; EAX = 0x1100
; EBX = 0x1E00
```

**Validation:**
- ✓ Both register writes complete
- ✓ Results are correct
- ✓ Both instructions execute in same cycle (dual-issue)

### Test 2: Register Dependency Serialization
**Objective:** Verify RAW dependencies prevent dual-issue

```asm
MOV EAX, 0x1000      ; inst0
ADD EBX, EAX         ; inst1 - reads EAX written by inst0 (RAW dependency)

; Expected behavior:
; - inst1 stalls until inst0 completes
; - Executes serially (not dual-issue)
; EBX = EBX_old + 0x1000
```

**Validation:**
- ✓ inst1 doesn't execute until inst0 completes
- ✓ EBX gets correct value (includes inst0's write to EAX)
- ✓ No dual-issue occurs

### Test 3: WAW (Write-After-Write) Hazard
**Objective:** Verify writing to same register serializes

```asm
ADD EAX, 0x10        ; inst0 writes EAX
SUB EAX, 0x05        ; inst1 writes EAX (WAW hazard)

; Expected behavior:
; - Mutex dependency detected
; - Serialized execution
; - Final EAX = (EAX_old + 0x10) - 0x05
```

**Validation:**
- ✓ Both operations execute serially
- ✓ Final result reflects program order (inst1's result)

---

## Flag Handling Tests

### Test 4: Flag Writeback Priority (Dual-Issue)
**Objective:** Verify younger instruction's flags win in dual-issue

```asm
; Both instructions set flags
ADD EAX, 0x01        ; inst0 → sets ZF=0, CF=0
SUB EBX, EBX         ; inst1 → sets ZF=1, CF=0 (result = 0)

; Expected architectural flags: inst1's flags (ZF=1)
JZ target            ; Should jump (inst1 set ZF)

target:
NOP
```

**Validation:**
- ✓ ZF reflects inst1's result (ZF=1)
- ✓ Jump is taken
- ✓ Program order respected

### Test 5: CMP/TEST Don't Writeback Registers
**Objective:** Verify CMP/TEST set flags but don't write destination

```asm
MOV EAX, 0x1000
CMP EAX, 0x1000      ; Should set ZF=1 but NOT modify EAX

; Expected:
; EAX = 0x1000 (unchanged)
; ZF = 1
```

**Validation:**
- ✓ EAX unchanged
- ✓ ZF set correctly

### Test 6: Flag Dependencies
**Objective:** Verify flag-dependent instructions serialize

```asm
ADD EAX, EBX         ; Sets flags
ADC ECX, EDX         ; Uses CF from ADD (flag dependency)

; Expected behavior:
; - ADC waits for ADD to complete
; - Serialized execution
```

**Validation:**
- ✓ ADC uses correct carry flag from ADD
- ✓ Serialized execution

---

## Multiply Operation Tests

### Test 7: Single-Operand IMUL (Can Dual-Issue)
**Objective:** Verify single-operand IMUL works in dual-issue queue

```asm
MOV EAX, 0x10
MOV EBX, 0x20
IMUL EAX, EBX        ; inst0: EAX = EAX * EBX (single destination)
ADD ECX, 0x100       ; inst1: Independent operation

; Expected:
; - Both can dual-issue (IMUL single destination)
; - EAX = 0x200
; - ECX = ECX_old + 0x100
```

**Validation:**
- ✓ IMUL completes in ~3 cycles
- ✓ ADD can execute in parallel
- ✓ EAX result correct

### Test 8: MUL/IMUL with EDX:EAX (Must NOT Dual-Issue)
**Objective:** Verify EDX:EAX multiply uses single-issue path

```asm
MOV EAX, 0x80000000
MOV EBX, 0x2
MUL EBX              ; EDX:EAX = EAX * EBX (dual destination)

; Expected:
; - Instruction NOT queued for dual-issue
; - Uses original execute path
; - EDX = 0x00000001
; - EAX = 0x00000000
```

**Validation:**
- ✓ Instruction not in dual-issue queue
- ✓ Both EDX and EAX written correctly
- ✓ 64-bit result accurate

### Test 9: Multiply Busy Signal Duration
**Objective:** Verify ALU stays busy for full 3 cycles during multiply

```asm
IMUL EAX, EBX        ; 3-cycle multiply on ALU0
NOP
NOP
ADD ECX, EDX         ; Can only dispatch after multiply completes

; Expected:
; - ADD waits until cycle 3 of IMUL
; - No premature dispatch
```

**Validation:**
- ✓ Multiply holds ALU busy for full duration
- ✓ No conflicting dispatch during multiply

---

## Edge Cases and Corner Cases

### Test 10: Queue Full Scenario
**Objective:** Verify correct stalling when instruction queue fills

```asm
; Generate 5+ consecutive queueable instructions
ADD EAX, 0x1
ADD EBX, 0x2
ADD ECX, 0x3
ADD EDX, 0x4
ADD ESI, 0x5    ; Should stall if queue full (max 4 entries)
ADD EDI, 0x6

; Expected:
; - First 4 queue successfully
; - 5th stalls until space available
; - All execute in order
```

**Validation:**
- ✓ Queue doesn't overflow
- ✓ Stalling mechanism works
- ✓ All results correct

### Test 11: Pipeline Flush (Exception/Branch)
**Objective:** Verify pipeline flush clears dual-issue state

```asm
ADD EAX, EBX         ; inst0 in ALU0
SUB ECX, EDX         ; inst1 in ALU1
INT 3                ; Trigger exception mid-execution

; Expected:
; - Both instructions flushed
; - No stale writebacks
; - Clean state after exception handler
```

**Validation:**
- ✓ No partial register updates
- ✓ Exception handled correctly
- ✓ Clean pipeline state

### Test 12: Memory Operations (Must NOT Dual-Issue)
**Objective:** Verify memory ops use original execute path

```asm
MOV [ESI], EAX       ; Memory write
ADD EBX, ECX         ; ALU op (independent)

; Expected:
; - Memory op NOT queued for dual-issue
; - ADD may execute independently
; - Memory write completes correctly
```

**Validation:**
- ✓ Memory operation not in dual-issue queue
- ✓ Memory write successful
- ✓ Program order maintained

### Test 13: Branch Instructions (Must NOT Dual-Issue)
**Objective:** Verify branches serialize execution

```asm
CMP EAX, EBX
JE target            ; Branch (must not dual-issue)
ADD ECX, EDX

target:
NOP
```

**Validation:**
- ✓ Branch not in dual-issue queue
- ✓ Queue drains before branch
- ✓ Correct branch behavior

---

## Stress Tests

### Test 14: Maximum Dual-Issue Throughput
**Objective:** Measure sustained dual-issue rate

```asm
; 100 independent ADD operations
ADD EAX, 0x1
ADD EBX, 0x1
ADD ECX, 0x1
ADD EDX, 0x1
ADD ESI, 0x1
ADD EDI, 0x1
ADD EBP, 0x1
ADD ESP, 0x1
; ... repeat 92 more times

; Expected:
; - ~50 cycles for 100 instructions (ideal IPC = 2.0)
; - All results correct
```

**Validation:**
- ✓ High dual-issue rate achieved
- ✓ No data corruption
- ✓ Performance improvement measurable

### Test 15: Alternating Dependencies
**Objective:** Test worst-case dependency pattern

```asm
MOV EAX, 0x1000
ADD EBX, EAX         ; Depends on EAX (serialize)
ADD EAX, EBX         ; Depends on EBX (serialize)
ADD EBX, EAX         ; Depends on EAX (serialize)
ADD EAX, EBX         ; Depends on EBX (serialize)
; ...

; Expected:
; - All serialize (no dual-issue possible)
; - Results chain correctly
```

**Validation:**
- ✓ Serialized execution
- ✓ Dependency chain respected
- ✓ Final values correct

### Test 16: Mixed Operation Types
**Objective:** Test various operations in dual-issue

```asm
ADD EAX, 0x10        ; Arithmetic
XOR EBX, 0xFF        ; Logic
SUB ECX, 0x20        ; Arithmetic
OR  EDX, 0x0F        ; Logic
AND ESI, 0xF0        ; Logic

; Expected:
; - Dual-issue where possible
; - All results correct
; - Flags from younger instructions
```

**Validation:**
- ✓ Mixed operations execute correctly
- ✓ No interference between operation types

---

## Real-World Code Patterns

### Test 17: Loop Unrolling
**Objective:** Test common compiler optimization

```asm
; Unrolled loop: sum array elements
MOV ESI, array_base
MOV EAX, 0           ; accumulator

ADD EAX, [ESI]       ; Load and add (memory op - serialize)
ADD EAX, [ESI+4]     ; Load and add
ADD EAX, [ESI+8]
ADD EAX, [ESI+12]

; Expected:
; - Memory ops serialize but ALU can dual-issue between loads
; - Correct sum in EAX
```

**Validation:**
- ✓ Correct accumulation
- ✓ Performance better than fully serial

### Test 18: Register Renaming Pattern
**Objective:** Test code with good register allocation

```asm
; Independent computation chains
ADD EAX, 0x10        ; Chain 1
ADD EBX, 0x20        ; Chain 2 (independent)
ADD EAX, 0x30        ; Chain 1
ADD EBX, 0x40        ; Chain 2 (independent)

; Expected:
; - Pairs dual-issue: (inst0,inst1), (inst2,inst3)
; - IPC ≈ 2.0
; - EAX = EAX_old + 0x40
; - EBX = EBX_old + 0x60
```

**Validation:**
- ✓ High dual-issue rate
- ✓ Both chains correct

---

## Automated Test Suite Structure

### Recommended Test Organization

```
tests/
├── unit/
│   ├── alu_operations.asm
│   ├── flag_handling.asm
│   ├── multiply.asm
│   └── dependencies.asm
├── integration/
│   ├── queue_management.asm
│   ├── exception_handling.asm
│   └── mixed_operations.asm
├── stress/
│   ├── throughput_test.asm
│   ├── dependency_chain.asm
│   └── random_operations.asm
└── benchmarks/
    ├── dhrystone.c
    ├── coremark.c
    └── synthetic_ipc.asm
```

### Test Harness Requirements

1. **Cycle Counter:** Measure execution time
2. **Register Dump:** Capture final register state
3. **Flag Verification:** Check EFLAGS after each test
4. **Comparison:** Golden reference vs actual results
5. **Coverage:** Track dual-issue rate, IPC, stall reasons

---

## Expected Performance Metrics

### Ideal Case (100% Dual-Issue)
- **IPC:** 2.0 instructions per cycle
- **Speedup:** 2x vs single-issue

### Realistic Case (With Dependencies)
- **IPC:** 1.3 - 1.7 instructions per cycle
- **Speedup:** 1.3x - 1.7x vs single-issue
- **Dual-Issue Rate:** 30-70% depending on code

### Limiting Factors
- Register dependencies (RAW, WAW)
- Flag dependencies
- Memory operations (not dual-issued)
- Branches (not dual-issued)
- Queue full stalls

---

## Pass/Fail Criteria

### Must Pass (Critical)
- ✅ All register writebacks correct
- ✅ All flag calculations correct
- ✅ Flag priority respects program order
- ✅ EDX:EAX multiply writes both registers
- ✅ CMP/TEST don't modify registers
- ✅ No combinational loop synthesis warnings
- ✅ Dependencies correctly detected and serialized
- ✅ Pipeline flushes clear dual-issue state

### Should Pass (Important)
- ✅ IPC improvement measurable (≥1.2x)
- ✅ Dual-issue rate >20% on typical code
- ✅ No timing violations in synthesis
- ✅ Resource usage acceptable

### Nice to Have (Optimization)
- ✅ IPC >1.5 on optimized code
- ✅ Dual-issue rate >50% on unrolled loops
- ✅ Clean synthesis reports

---

## Debugging Checklist

If tests fail, check:
1. Register writeback signals (wr0_*, wr1_*)
2. Flag mux priority logic
3. Dependency detection (mutex)
4. Queue management (enqueue/dequeue counts)
5. ALU busy signals (registered state)
6. Multiply counter (3-cycle duration)
7. Pipeline flush (exe_reset, wr_reset)
8. Command tracking (CMP/TEST vs normal ops)

---

## Next Steps After Testing

1. **Synthesis:** Run Quartus synthesis, check for warnings
2. **Timing:** Verify timing closure at target frequency
3. **FPGA Test:** Deploy to MiSTer FPGA
4. **Software Test:** Boot DOS, run benchmarks
5. **Performance:** Measure real-world IPC improvement
6. **Optimization:** Identify bottlenecks, tune dispatch policy

---

*Test scenarios for superscalar ao486 validation*
*Last updated: 2025-11-22*
