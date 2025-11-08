# Superscalar ao486 Test Benches

This directory contains test benches for validating the superscalar ao486 components.

## Test Files

### `tb_dispatch.v`
Tests the instruction dispatch unit:
- ✅ Independent instruction dual-issue
- ✅ RAW dependency detection (register, EFLAGS, memory, I/O)
- ✅ Resource conflict detection (multiplier, divider, memory)
- ✅ Branch instruction handling (no dual-issue)
- ✅ Complex instruction handling (no dual-issue)
- ✅ Pipeline dependency checking (in-flight instructions)
- ✅ Structural hazard detection (ALU busy)

**Test Coverage:** 8 test cases covering all major dispatch scenarios

## Requirements

### Software
- **Icarus Verilog** (`iverilog`): Open-source Verilog simulator
  - Install: `sudo apt-get install iverilog` (Ubuntu/Debian)
  - Install: `brew install icarus-verilog` (macOS)

- **GTKWave** (optional): Waveform viewer
  - Install: `sudo apt-get install gtkwave` (Ubuntu/Debian)
  - Install: `brew install gtkwave` (macOS)

## Running Tests

### Quick Start
```bash
cd sim/superscalar
make test_dispatch
```

### View Waveforms
```bash
make wave_dispatch
```

### Clean Up
```bash
make clean
```

## Test Output

### Successful Run
```
========================================
Dispatch Unit Test Bench
========================================

Test 1: Independent ALU operations
  PASS: Both instructions dispatched

Test 2: Register dependency (RAW hazard)
  PASS: Only inst0 dispatched (dependency detected)

Test 3: Resource conflict (both need multiplier)
  PASS: Only inst0 dispatched (resource conflict)

Test 4: Branch instruction (no dual-issue)
  PASS: Only branch dispatched

Test 5: Pipeline dependency (in-flight writes EAX)
  PASS: Instruction stalled (pipeline dependency)

Test 6: Memory operations (no dual-issue)
  PASS: Only one memory op dispatched

Test 7: I/O dependency (both access I/O)
  PASS: I/O dependency detected

Test 8: ALU busy (structural hazard)
  PASS: Stalled due to ALU busy

========================================
Test Summary
========================================
Total tests: 8
Passed:      8
Failed:      0

ALL TESTS PASSED!
========================================
```

## Test Cases Explained

### Test 1: Independent Instructions
```assembly
ADD EAX, EBX    ; Writes EAX
XOR ECX, EDX    ; Writes ECX (no conflict)
```
**Expected:** Dual-issue (both instructions dispatch)

### Test 2: Register Dependency
```assembly
ADD EAX, EBX    ; Writes EAX
SUB EAX, ECX    ; Reads/writes EAX (dependency!)
```
**Expected:** Single-issue (only first instruction dispatches)

### Test 3: Resource Conflict
```assembly
MUL EAX, EBX    ; Needs multiplier
MUL ECX, EDX    ; Also needs multiplier (conflict!)
```
**Expected:** Single-issue (shared resource)

### Test 4: Branch Serialization
```assembly
JMP target      ; Branch (must execute alone)
ADD EAX, EBX    ; Cannot dual-issue with branch
```
**Expected:** Single-issue (branch policy)

### Test 5: Pipeline Dependency
```
Pipeline: inst writes EAX (in-flight)
New inst: ADD EAX, EBX (also writes EAX)
```
**Expected:** Stall until in-flight instruction completes

### Test 6: Memory Serialization
```assembly
MOV [EAX], EBX  ; Store to memory
MOV ECX, [EDX]  ; Load from memory
```
**Expected:** Single-issue (memory operations serialized)

### Test 7: I/O Dependency
```assembly
IN AL, DX       ; I/O read
OUT DX, AL      ; I/O write (conflict!)
```
**Expected:** Single-issue (I/O must serialize)

### Test 8: Structural Hazard
```
ALU0: Busy
ALU1: Busy
New inst: ADD EAX, EBX (needs ALU)
```
**Expected:** Stall until ALU available

## Waveform Analysis

After running tests, view the waveform:
```bash
make wave_dispatch
```

**Key Signals to Observe:**
- `dual_issue`: High when both instructions dispatch
- `dispatch_inst0`, `dispatch_inst1`: Individual dispatch decisions
- `stall_dependency`: High when data dependency detected
- `stall_structural`: High when resource unavailable
- `inst0_mutex`, `inst1_mutex`: Resource usage vectors

## Adding More Tests

To add additional test cases:

1. Edit `tb_dispatch.v`
2. Add a new test section following the pattern:
```verilog
test_num = test_num + 1;
$display("\nTest %0d: Your test description", test_num);
reset_inputs();
// Setup instructions
setup_instruction(0, cmd, mutex, ...);
setup_instruction(1, cmd, mutex, ...);
@(posedge clk);
#1;
// Check results
if (expected_condition) begin
    $display("  PASS: ...");
    pass_count = pass_count + 1;
end else begin
    $display("  FAIL: ...");
    fail_count = fail_count + 1;
end
```

## Known Limitations

1. **Mutex Ambiguity:** The ao486 mutex system doesn't distinguish READ vs WRITE, so dependency detection is conservative (may stall unnecessarily but won't miss real dependencies)

2. **Simplified Execution Units:** Tests assume idealized ALU behavior. Real ao486 execution has more complexity (variable latencies, exceptions, etc.)

3. **No Integration Testing:** These are unit tests for individual modules. Full integration with the ao486 pipeline is not tested here.

## Future Test Benches

Planned test benches:
- `tb_forwarding.v`: Result forwarding network validation
- `tb_dual_execute.v`: Dual ALU correctness testing
- `tb_superscalar_pipeline.v`: Full pipeline integration tests

## Troubleshooting

### "command not found: iverilog"
Install Icarus Verilog (see Requirements section)

### Test failures
Check the waveform to debug:
```bash
make wave_dispatch
```

Look for:
- Signal transitions at unexpected times
- Mutex conflicts
- Incorrect resource availability

### Compilation errors
Ensure you're in the correct directory:
```bash
cd /home/user/ao486_MiSTer/sim/superscalar
```

## References

- [Dispatch Module](../../rtl/ao486/pipeline/dispatch.v)
- [Superscalar Architecture Documentation](../../SUPERSCALAR_ARCHITECTURE.md)
- [Integration Guide](../../INTEGRATION_GUIDE.md)
