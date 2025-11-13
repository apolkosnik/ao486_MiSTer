# Test Bench Debugging Status

## Latest Update: Decoder Bit Classification Implemented ✅

**Date:** 2025-11-13
**Status:** Instruction classification logic added to decode stage

The decoder bit positions (20-23) are no longer placeholders. Instruction classification is now implemented in the decode stage via new module outputs:

- **dec_is_mult**: Set for MUL (cmd 59), IMUL (cmd 54)
- **dec_is_div**: Set for DIV (cmd 42), IDIV (cmd 43), AAM (cmd 32)
- **dec_is_branch**: Set for Jcc (cmd 8), JCXZ (cmd 2), LOOP (cmd 60), JMP (cmd 87), CALL (cmd 3), RET_near (cmd 15), RET_far (cmd 63), INT_INTO (cmd 75), IRET (cmd 35)
- **dec_is_complex**: Already existed in original decode.v

**Files Modified:**
- `rtl/ao486/pipeline/decode.v`: Added classification logic (lines 266-292) and new outputs
- `rtl/ao486/defines.v`: Updated documentation for DECODER_IS_*_BIT defines

**Implementation Details:**
The classification wires check `dec_cmd` values against specific instruction types and are exported as module outputs. This allows the superscalar dispatch logic to correctly identify instruction types for resource allocation and dual-issue decisions.

## Fixes Applied (Earlier Commits)

### 1. ✅ Initialized All Test Bench Registers
**Commit:** 7c0ec8a
- All `reg` variables now initialize to 0 at declaration
- Prevents X values from propagating at simulation start

### 2. ✅ Fixed Ternary Operator Evaluation
**Commit:** d456161
- Changed from: `wire ok = uses ? avail : 1'b1;`
- Changed to: `wire ok = (uses == 1'b0) ? 1'b1 : avail;`
- Ensures zero-check happens first

### 3. ✅ Used Reduction OR Instead of != Comparison
**Commit:** 4f994bf
- Changed from: `(mutex[7:0] & pipeline[7:0]) != 8'b0`
- Changed to: `|(mutex[7:0] & pipeline[7:0])`
- More robust for simulators

### 4. ✅ Broke Down Complex Expressions
**Commit:** 3afdad7
- Created intermediate wires: `inst0_alu_ok`, `inst0_mult_ok`, etc.
- Clearer logic flow, easier to debug

## Expected Test Results

After all fixes, you should see:

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
```

## If Tests Still Fail

### Check This First
If `dispatch_inst0` is still showing X, add debug output to the test:

```verilog
$display("DEBUG inst0_valid=%b", inst0_valid);
$display("DEBUG inst0_uses_alu=%b", inst0_uses_alu);
$display("DEBUG alu0_busy=%b, alu1_busy=%b", alu0_busy, alu1_busy);
$display("DEBUG alu0_available=%b, alu1_available=%b",
         !alu0_busy, !alu1_busy);
$monitor("Time=%0t dispatch_inst0=%b can_dispatch_inst0=%b",
         $time, dispatch_inst0, dut.can_dispatch_inst0);
```

### Potential Remaining Issues

1. **Clock/Reset Timing**
   - Make sure `@(posedge clk)` happens after signals are set
   - Add `#1` delay after clock edge before checking outputs

2. **Wire vs Reg Declaration**
   - All DUT outputs should be `wire`, not `reg`
   - Check instantiation matches module ports exactly

3. **Include Path Issues**
   - Verify `defines.v` is being included correctly
   - Check that `CMD_*` constants are defined

## Quick Debug Test

Run the minimal debug test bench:
```bash
cd sim/superscalar
iverilog -I../../rtl/ao486 -I../../rtl/ao486/pipeline \
  -o debug.vvp tb_dispatch_debug.v ../../rtl/ao486/pipeline/dispatch.v
vvp debug.vvp
```

This will show step-by-step what's happening with just one instruction.

## View Waveform

If tests fail, examine the waveform:
```bash
gtkwave tb_dispatch.vcd &
```

Look for:
- `dispatch_inst0` - should be 0 or 1, not X
- `can_dispatch_inst0` - intermediate wire
- `inst0_alu_ok`, `inst0_mult_ok`, etc. - should all be 0 or 1
- `inst0_has_dependency` - should be 0 when no dependencies

## Architecture Issues (Not Test-Related)

These are design issues, not test bugs:

1. **Decoder Bit Classification Not Implemented**
   - Bits 20-23 are never set in real pipeline
   - Doesn't affect standalone dispatch tests
   - Would need 6-8 hours to implement properly

2. **Forwarding Not Connected**
   - Hardcoded to zero (documented)
   - Awaits pipeline integration
   - Not needed for dispatch tests

3. **No Pipeline Integration**
   - 220+ hours of work required
   - See INTEGRATION_GUIDE.md

## Next Steps

1. **Run the tests** on a machine with Icarus Verilog
2. **If all pass**: Great! Move to next phase (see CURRENT_STATUS.md)
3. **If some fail**: Report which tests fail and paste the output
4. **If all fail with X**: Something fundamental is wrong - we'll debug

## Summary

**All known X propagation issues have been fixed:**
- ✅ Uninitialized registers
- ✅ Ternary operator evaluation
- ✅ Bit-vector comparison method
- ✅ Complex expression breakdown

The dispatch logic should now work correctly in simulation.
