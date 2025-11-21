# Superscalar Test Suite

Comprehensive test suite for validating the ao486 dual-issue superscalar implementation.

## Overview

This directory contains unit tests and integration tests for the superscalar components:

- **tb_instruction_queue.v** - Tests for 4-entry instruction FIFO queue
- **tb_dispatch.v** - Tests for dual-issue dispatch logic
- More tests coming soon...

## Requirements

### Software
- **Icarus Verilog** (iverilog) - Open source Verilog simulator
  - Ubuntu/Debian: `sudo apt-get install iverilog`
  - macOS: `brew install icarus-verilog`
  - Windows: Download from http://bleyer.org/icarus/

- **GTKWave** (optional) - Waveform viewer
  - Ubuntu/Debian: `sudo apt-get install gtkwave`
  - macOS: `brew install gtkwave`
  - Windows: Download from http://gtkwave.sourceforge.net/

### Alternative: ModelSim
If you prefer ModelSim (commercial simulator):
```bash
vlog tb_instruction_queue.v ../../rtl/ao486/pipeline/instruction_queue.v
vsim -c tb_instruction_queue -do "run -all; quit"
```

## Running Tests

### Quick Start
Run all tests:
```bash
make all
```

### Individual Tests

**Instruction Queue:**
```bash
make test_queue
```

**Dispatch Logic:**
```bash
make test_dispatch
```

### View Waveforms

After running tests, view waveforms in GTKWave:
```bash
make view_queue     # View instruction queue waveforms
make view_dispatch  # View dispatch waveforms
```

Or manually:
```bash
gtkwave tb_instruction_queue.vcd &
```

## Test Coverage

### Phase 6 Unit Tests

#### ✅ Instruction Queue (tb_instruction_queue.v)
- [x] Test 1.1: Basic enqueue/dequeue operations
- [x] Test 1.2: Queue reset/flush behavior
- [x] Test 1.3: ModR/M destination tracking
- [x] Test 1.4: Backpressure when queue full

#### ✅ Dispatch Logic (tb_dispatch.v)
- [x] Test 2.1: RAW dependency detection
- [x] Test 2.2: No dependency → dual-issue
- [x] Test 2.3: Resource conflicts (multiplier)
- [x] Test 2.4: Branch serialization
- [x] Test 2.5: ALU routing decisions
- [x] Test 2.6: Structural hazards (ALU busy)
- [x] Test 2.7: WAW hazard detection

#### 🔄 Coming Soon
- [ ] Dual Execute Tests (tb_dual_execute.v)
- [ ] Writeback Tests (tb_writeback.v)
- [ ] Integration Tests (tb_integration.v)
- [ ] Exception Handling Tests
- [ ] Performance Measurement Tests

## Test Results Format

Each test outputs:
```
PASS: Test N - Test description
FAIL: Test N - Test description (Expected: X, Got: Y)
```

Final summary:
```
========================================
Test Summary
========================================
Total Tests: 24
Passed:      24
Failed:      0

ALL TESTS PASSED!
========================================
```

## Debugging Failed Tests

1. **Check waveforms**:
   ```bash
   make view_queue
   ```
   Look for signal transitions around the failure point

2. **Add debug prints**:
   Edit the testbench and add `$display` statements

3. **Increase verbosity**:
   Uncomment monitor statements in the testbench

4. **Single-step**:
   Use ModelSim for interactive debugging

## Expected Results

### Instruction Queue
- All 24 tests should pass
- Queue should properly handle enqueue/dequeue
- Reset should clear all entries
- Full queue should reject new entries

### Dispatch Logic
- All 27 tests should pass
- Dependencies should prevent dual-issue
- Independent instructions should dual-issue
- Branches should serialize (no dual-issue)

## File Structure

```
tests/superscalar/
├── README.md                  # This file
├── Makefile                   # Test automation
├── tb_instruction_queue.v     # Queue unit tests
├── tb_dispatch.v              # Dispatch unit tests
├── tb_dual_execute.v          # (Coming soon)
├── tb_writeback.v             # (Coming soon)
└── tb_integration.v           # (Coming soon)
```

## Continuous Integration

To run tests in CI/CD:
```bash
cd tests/superscalar
make clean
make all > test_results.log 2>&1
grep "ALL TESTS PASSED" test_results.log
```

## Performance Testing

Performance metrics (IPC, dual-issue rate) require integration with full pipeline. See `SUPERSCALAR_TEST_PLAN.md` for details.

## Troubleshooting

**Error: "instruction_queue.v: No such file"**
- Check that RTL files exist in `../../rtl/ao486/pipeline/`
- Verify Makefile RTL_DIR path is correct

**Error: "Undefined macro `CMD_MUL`"**
- Ensure `defines.v` is in include path
- Check that autogen/defines.v exists

**Test hangs or timeout:**
- Check for missing `#1` delays before checking combinational logic
- Ensure clock is running (`forever #5 clk = ~clk`)

## Contributing

When adding new tests:
1. Follow existing test structure
2. Use `check_result()` for assertions
3. Add descriptive test names
4. Document expected behavior
5. Update Makefile with new test targets
6. Update this README

## References

- **Test Plan**: `../../SUPERSCALAR_TEST_PLAN.md`
- **Architecture**: `../../SUPERSCALAR_SUMMARY.md`
- **Progress**: `../../INTEGRATION_PROGRESS.md`

## Status

**Last Updated**: 2025-11-21
**Status**: Unit tests for Queue and Dispatch complete
**Next**: Dual execute and writeback tests
