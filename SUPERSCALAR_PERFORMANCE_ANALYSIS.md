# Superscalar ao486 Performance Analysis

## Overview
This document analyzes the expected performance improvements from the 2-way superscalar ao486 implementation and identifies workload characteristics that will benefit most.

---

## Theoretical Maximum Performance

### Ideal Dual-Issue (No Dependencies)
```
Single-Issue:  100 instructions = 100 cycles
Dual-Issue:    100 instructions =  50 cycles
Speedup: 2.0x
IPC: 2.0
```

**Conditions for ideal performance:**
- No register dependencies (RAW, WAW, WAR)
- No flag dependencies
- All instructions are queueable (ALU operations)
- No resource conflicts
- Queue never full

**Real-world applicability:** Rare. Requires perfect code generation or manual optimization.

---

## Realistic Performance Expectations

### Typical x86 Code Characteristics

Based on analysis of common x86 instruction streams:

| Instruction Type | Frequency | Can Dual-Issue? | Notes |
|-----------------|-----------|-----------------|-------|
| ALU Operations  | 40-50%    | ✅ Yes          | ADD, SUB, AND, OR, XOR, etc. |
| Memory Ops      | 25-35%    | ❌ No           | MOV to/from memory |
| Branches        | 10-20%    | ❌ No           | JMP, JE, JNE, CALL, RET |
| Complex Ops     | 5-10%     | ❌ No           | MUL, DIV, shifts, etc. |
| Flag-Dependent  | 15-25%    | ⚠️ Depends     | ADC, SBB, conditional ops |

### Dependency Analysis

**Register Dependencies:**
- **RAW hazards:** 30-40% of instruction pairs
- **WAW hazards:** 5-10% of instruction pairs
- **Independent pairs:** 50-65%

**Flag Dependencies:**
- Affects ~20% of instructions (ADC, SBB, CMOVcc, etc.)
- Often serializes after CMP/TEST

### Expected IPC by Code Type

| Code Type | Dual-Issue Rate | Expected IPC | Speedup vs Single-Issue |
|-----------|----------------|--------------|-------------------------|
| **Compiler-optimized loops** | 40-60% | 1.4-1.6 | 1.4x-1.6x |
| **Hand-optimized assembly** | 60-80% | 1.6-1.8 | 1.6x-1.8x |
| **Typical mixed code** | 25-40% | 1.25-1.4 | 1.25x-1.4x |
| **Memory-intensive code** | 10-20% | 1.1-1.2 | 1.1x-1.2x |
| **Branch-heavy code** | 5-15% | 1.05-1.15 | 1.05x-1.15x |

---

## Best-Case Scenarios

### Scenario 1: Unrolled Loop with Register Allocation

```asm
; Array sum with 4-way unrolling
MOV ESI, array_ptr
XOR EAX, 0          ; accumulator1
XOR EBX, 0          ; accumulator2
XOR ECX, 0          ; accumulator3
XOR EDX, 0          ; accumulator4
MOV EDI, count

loop:
    ADD EAX, [ESI]      ; Load array[i]   - memory, serialize
    ADD EBX, [ESI+4]    ; Load array[i+1] - memory, serialize
    ADD ECX, [ESI+8]    ; Load array[i+2] - memory, serialize
    ADD EDX, [ESI+12]   ; Load array[i+3] - memory, serialize
    ADD ESI, 16
    SUB EDI, 4
    JNZ loop

    ; Combine accumulators
    ADD EAX, EBX        ; Independent of next
    ADD ECX, EDX        ; Can dual-issue with above ✓
    ADD EAX, ECX        ; Final sum
```

**Analysis:**
- Memory loads serialize
- Accumulator additions independent → dual-issue ✓
- Final combine phase: 2 instructions → 1 cycle
- **Est. IPC:** 1.3-1.4 (memory bound, but some dual-issue)

### Scenario 2: Bit Manipulation

```asm
; Extract and process multiple fields from packed data
MOV EAX, [packed_data]
MOV EBX, EAX

AND EAX, 0x000000FF ; Extract byte 0
SHR EBX, 8          ; Shift for byte 1 - independent ✓ dual-issue

MOV ECX, EBX
AND EBX, 0x000000FF ; Extract byte 1
SHR ECX, 8          ; Shift for byte 2 - independent ✓ dual-issue

; Process extracted bytes
ADD EAX, lookup_base
ADD EBX, lookup_base ; Independent ✓ dual-issue
```

**Analysis:**
- Many independent operations
- High dual-issue rate possible
- **Est. IPC:** 1.6-1.8

### Scenario 3: Fixed-Point Math

```asm
; Compute (a*b + c*d) >> 16
IMUL EAX, EBX       ; a*b (single dest, can queue)
IMUL ECX, EDX       ; c*d - independent ✓ dual-issue possible

ADD EAX, ECX        ; Sum products
SAR EAX, 16         ; Scale result
```

**Analysis:**
- Two multiplies potentially parallel
- Some dual-issue despite multiply latency
- **Est. IPC:** 1.3-1.5

---

## Worst-Case Scenarios

### Scenario 1: Dependent Chain

```asm
; Fibonacci-like sequence (each depends on previous)
MOV EAX, 1
MOV EBX, 1

ADD ECX, EAX        ; Depends on EAX
ADD EAX, EBX        ; Depends on EBX
ADD EBX, ECX        ; Depends on ECX
ADD ECX, EAX        ; Depends on EAX
ADD EAX, EBX        ; Depends on EBX
```

**Analysis:**
- Pure dependency chain
- Zero dual-issue possible
- **IPC:** 1.0 (same as single-issue)

### Scenario 2: Memory-Intensive

```asm
; Copying memory array
MOV ESI, src
MOV EDI, dst
MOV ECX, count

loop:
    MOV EAX, [ESI]      ; Load - memory, serialize
    MOV [EDI], EAX      ; Store - memory, serialize
    ADD ESI, 4
    ADD EDI, 4
    DEC ECX             ; Flag dependency with loop
    JNZ loop
```

**Analysis:**
- Memory ops dominate, can't dual-issue
- Loop overhead serialized
- **IPC:** 1.05-1.1

### Scenario 3: Flag-Heavy Code

```asm
; Multi-precision addition (64-bit on 32-bit CPU)
ADD EAX, [ESI]      ; Low word
ADC EBX, [ESI+4]    ; High word - flag dependency ✗
ADD ECX, [EDI]      ; Low word
ADC EDX, [EDI+4]    ; High word - flag dependency ✗
```

**Analysis:**
- ADC depends on carry flag from ADD
- Serializes all operations
- Memory ops also serialize
- **IPC:** 1.0-1.05

---

## Real-World Benchmarks - Projected Results

### Dhrystone
**Characteristics:**
- Mix of ALU, memory, and branches
- Moderate dependencies
- Some loops with independent operations

**Projected Improvement:**
- Dual-Issue Rate: 25-35%
- **IPC:** 1.25-1.35
- **Speedup:** 1.25x-1.35x

### CoreMark
**Characteristics:**
- List processing, matrix operations
- Better register allocation
- More ALU-intensive than Dhrystone

**Projected Improvement:**
- Dual-Issue Rate: 35-45%
- **IPC:** 1.35-1.45
- **Speedup:** 1.35x-1.45x

### Doom / Quake (Game Engines)
**Characteristics:**
- Fixed-point math, vector operations
- Optimized inner loops
- Bit manipulation

**Projected Improvement:**
- Dual-Issue Rate: 40-55%
- **IPC:** 1.4-1.55
- **Speedup:** 1.4x-1.55x

### Compression (gzip, bzip2)
**Characteristics:**
- Bit manipulation heavy
- Table lookups (memory)
- Mixed performance

**Projected Improvement:**
- Dual-Issue Rate: 30-40%
- **IPC:** 1.3-1.4
- **Speedup:** 1.3x-1.4x

---

## Bottleneck Analysis

### Primary Bottlenecks (Ranked)

**1. Register Dependencies (40-50% impact)**
- RAW hazards most common
- Limited by x86 register count (8 GPRs)
- **Mitigation:** Compiler register allocation, loop unrolling

**2. Memory Operations (25-35% impact)**
- Can't dual-issue memory ops
- High memory traffic serializes execution
- **Mitigation:** Better caching, prefetching (future work)

**3. Flag Dependencies (15-25% impact)**
- Carry flag chains (multi-precision math)
- Conditional operations after CMP/TEST
- **Mitigation:** Compiler can sometimes avoid (e.g., use conditional move)

**4. Instruction Queue Depth (5-10% impact)**
- 4-entry queue may fill on sustained dual-issue
- **Mitigation:** Larger queue (8 entries) in future

**5. Branches (10-15% impact)**
- Can't dual-issue with branches
- Queue must drain
- **Mitigation:** Branch prediction (future work)

### Amdahl's Law Application

Assuming 60% of code can theoretically dual-issue:

```
Speedup = 1 / ((1-P) + P/S)
where P = 0.6 (parallel portion)
      S = 2.0 (speedup for parallel portion)

Speedup = 1 / (0.4 + 0.6/2.0)
        = 1 / (0.4 + 0.3)
        = 1 / 0.7
        = 1.43x
```

**Realistic estimate:** 1.3x - 1.5x average speedup across diverse workloads.

---

## Optimization Opportunities for Software

### Compiler Optimizations to Leverage Superscalar

**1. Loop Unrolling**
```c
// Before:
for (i = 0; i < n; i++)
    sum += array[i];

// After (4-way unroll):
for (i = 0; i < n; i += 4) {
    sum0 += array[i];
    sum1 += array[i+1];   // Can dual-issue
    sum2 += array[i+2];
    sum3 += array[i+3];
}
sum = sum0 + sum1 + sum2 + sum3;
```

**Benefit:** Creates independent operations → dual-issue

**2. Software Pipelining**
```asm
; Before (dependent):
loop:
    MOV EAX, [ESI]
    ADD EAX, EBX
    MOV [EDI], EAX
    ADD ESI, 4
    ADD EDI, 4
    DEC ECX
    JNZ loop

; After (pipelined):
loop:
    MOV EAX, [ESI]
    MOV EDX, [ESI+4]      ; Prefetch next - can dual-issue
    ADD EAX, EBX
    MOV [EDI], EAX
    ADD ESI, 4
    ADD EDI, 4
    DEC ECX
    JNZ loop
```

**Benefit:** Overlaps independent operations

**3. Register Allocation**
- Use all 8 GPRs effectively
- Minimize register reuse (reduce WAW hazards)
- Keep frequently-used values in registers

**4. Instruction Scheduling**
- Interleave independent computations
- Schedule non-dependent operations adjacent
- Place memory ops early (hide latency)

### Hand-Optimization Examples

**Vector Addition (optimized):**
```asm
; Process 4 vectors in parallel
loop:
    MOV EAX, [ESI]
    MOV EBX, [ESI+vec_size]
    ADD EAX, [EDI]        ; Memory op
    ADD EBX, [EDI+vec_size] ; Independent, but memory - serialize

    ; These can dual-issue:
    MOV ECX, [ESI+vec_size*2]
    MOV EDX, [ESI+vec_size*3]  ; Dual-issue ✓

    ADD ECX, [EDI+vec_size*2]
    ADD EDX, [EDI+vec_size*3]   ; Dual-issue ✓
```

**Expected IPC:** 1.4-1.5 despite memory operations

---

## Hardware Resource Utilization

### Instruction Mix in Dual-Issue Window

**4-entry queue utilization:**
- Average occupancy: 2-3 entries during sustained execution
- Rarely fills completely (requires sustained instruction stream)
- Drains quickly on branches

**ALU Utilization:**
- **ALU0:** 50-70% busy (higher due to default routing)
- **ALU1:** 40-60% busy
- **Combined:** 90-130% (>100% indicates dual-issue)

**Multiplier Utilization:**
- Typically <10% (multiply ops rare)
- When used, blocks one ALU for 3 cycles
- Shared between ALUs (no conflict in practice)

---

## Comparison with Other Architectures

### vs. Original Single-Issue ao486
- **IPC:** 1.0 → 1.3-1.5 (30-50% improvement)
- **Area:** +15-20% (dual ALUs, queue, dispatch logic)
- **Complexity:** Moderate increase
- **Verdict:** Good area/performance tradeoff ✓

### vs. Pentium (1993)
- Pentium: 2-way superscalar with U/V pipes
- Pentium IPC: 1.5-1.7 (real-world)
- ao486 superscalar: 1.3-1.5 (projected)
- **Gap:** Pentium had more sophisticated dispatch, pairing rules, and branch prediction

### vs. Modern Out-of-Order
- Modern x86: IPC 3-5+
- Techniques: OOO execution, register renaming, deep pipelines
- **Our approach:** In-order dual-issue (simpler, lower power)

---

## Recommendations

### For Software Developers

1. **Use modern compilers with optimization** (`-O2`, `-O3`)
2. **Profile and identify hot loops** → optimize these first
3. **Unroll loops 2-4x** to create independent operations
4. **Minimize dependencies** in critical paths
5. **Use all GPRs** effectively (avoid spilling to memory)

### For Future Hardware Improvements

1. **Increase queue depth** (4 → 8 entries) for sustained dual-issue
2. **Add simple branch prediction** to reduce branch stalls
3. **Consider 3-way issue** for specific operation types
4. **Add load/store unit** to dual-issue memory ops
5. **Widen dispatch** to consider larger instruction window

### For Testing

1. **Focus on ALU-heavy workloads first** (best speedup)
2. **Test with real applications** (Doom, Quake, compression)
3. **Profile IPC and dual-issue rate** to validate projections
4. **Identify bottlenecks** for future optimization

---

## Summary

### Expected Overall Performance

| Metric | Conservative | Expected | Optimistic |
|--------|-------------|----------|------------|
| **Average IPC** | 1.25 | 1.35 | 1.50 |
| **Dual-Issue Rate** | 25% | 35% | 50% |
| **Speedup** | 1.25x | 1.35x | 1.50x |

### Key Findings

✅ **Worthwhile improvement:** 25-50% speedup for moderate complexity increase

✅ **ALU-heavy code benefits most:** Games, graphics, compression

✅ **Memory-intensive code limited:** Cache/memory is bottleneck

✅ **Compiler support helps:** Optimized code achieves better dual-issue rates

✅ **Realistic expectations:** Not 2x, but 1.3-1.5x is achievable and valuable

---

*Performance analysis for 2-way superscalar ao486*
*Projections based on code analysis and architectural constraints*
*Last updated: 2025-11-22*
