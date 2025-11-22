# Superscalar ao486 Synthesis Guide

## Overview
This guide provides recommendations for synthesizing the 2-way superscalar ao486 implementation on Intel/Altera FPGAs using Quartus Prime.

---

## Pre-Synthesis Checklist

### ✅ Verify All Files Use Correct Settings

The superscalar implementation uses SystemVerilog features (`automatic logic`), so ensure Quartus recognizes the file type:

```tcl
# In ao486.qip, verify:
set_global_assignment -name SYSTEMVERILOG_FILE [file join $::quartus(qip_path) pipeline/dual_execute.v]
```

**Files that MUST be SystemVerilog:**
- `rtl/ao486/pipeline/dual_execute.v`

### ✅ Check for Combinational Loop Warnings

After Bug #25 fix, there should be **NO** combinational loop warnings. If you see:
```
Warning: Found combinational loop of X nodes
```

This indicates a problem. The `alu_executing_r` registers should have broken all loops.

### ✅ Verify Multiplier Inference

Check synthesis messages for DSP block usage:
```
Info: Inferred 1 megafunctions from design logic
Info: Inferred multiplier megafunction ("lpm_mult") from...
```

The shared 32x32 multiplier in `dual_execute.v` should map to DSP blocks.

---

## Synthesis Settings

### Recommended Quartus Settings

**1. Optimization Goal**
```
Processing -> Compilation Process Settings
Optimization Technique: Balanced
```

**Why:** Balanced provides good area/speed tradeoff. The superscalar logic adds ~15-20% area, so aggressive speed optimization may not fit.

**2. Timing Analysis**
```
TimeQuest Timing Analyzer Settings:
- Enable multicorner timing analysis
- Report worst-case paths
- Check setup and hold times
```

**3. Resource Awareness**
```
Analysis & Synthesis Settings:
- Restructure Multiplexers: Auto
- Auto ROM Recognition: On
- Auto RAM Recognition: On
```

**4. Physical Synthesis**
```
Fitter Settings -> Physical Synthesis:
- Perform physical synthesis for combinational logic: On
- Perform register retiming: On (if timing closure difficult)
```

---

## Expected Resource Utilization

### Baseline (Single-Issue ao486)
Typical for Cyclone V:
- **ALMs:** ~15,000 - 18,000
- **Registers:** ~12,000 - 15,000
- **DSP Blocks:** 2-3 (for multiply/divide)
- **Memory Bits:** ~1-2 Mbits

### With Superscalar (Estimated Increase)

| Resource | Baseline | Superscalar | Increase |
|----------|----------|-------------|----------|
| **ALMs** | 15,000 | 17,500 - 18,500 | +15-20% |
| **Registers** | 12,000 | 14,000 - 15,000 | +15-20% |
| **DSP Blocks** | 2-3 | 3-4 | +1 block |
| **Memory** | 1-2 Mb | 1-2 Mb | Minimal |

**Added Components:**
- 2x ALU units (ALU0, ALU1): ~800-1000 ALMs
- Instruction queue (4 entries): ~200-300 ALMs
- Dispatch logic: ~300-400 ALMs
- Dual writeback ports: ~200-300 ALMs
- Flag tracking/mux: ~100-150 ALMs

### Resource Hotspots

**High logic utilization areas:**
1. `dual_execute.v` - dual ALU implementation
2. `dispatch.v` - dependency detection and routing
3. `pipeline.v` - writeback tracking and muxes
4. `write_register.v` - dual writeback priority logic

---

## Critical Timing Paths

### Identified Critical Paths

**1. Dispatch Decision to ALU Valid**
```
dispatch.v:can_dispatch_inst0
  → inst0_to_alu0
  → alu0_valid_dual (pipeline.v)
  → dual_execute.v:alu0_valid
  → ALU execution
```

**Estimated delay:** 3-4 logic levels
**Critical:** This is combinational and affects cycle time

**Mitigation:**
- Use `alu_executing_r` (registered) for busy signal (already done ✓)
- Consider registering dispatch decision if timing critical

**2. Flag Priority Mux to Write Stage**
```
alu0_flags_r, alu1_flags_r
  → inst1_flags_ready, inst0_flags_ready
  → exe_result_signals (3-input mux)
  → write stage flag update
```

**Estimated delay:** 2-3 logic levels
**Critical:** Moderate - mux is fairly shallow

**3. Register Writeback Priority**
```
w_write_regrm
  → wr0_valid && wr0_eax
  → wr1_valid && wr1_eax
  → eax <= (priority chain)
```

**Estimated delay:** 2-3 logic levels per register
**Critical:** Moderate - priority encoded as if-else chain

**Optimization:** If timing critical, could use explicit priority encoder.

**4. Multiply Arbitration**
```
mult_request_alu0, mult_request_alu1
  → mult_active decision
  → mult_for_alu0
  → alu0_busy / alu1_busy
```

**Estimated delay:** 2 logic levels
**Critical:** Low - not on critical path

---

## Timing Constraints

### Required Clock Frequency

**Original ao486:**
- Target: 50-75 MHz (typical MiSTer)
- Critical path: ~13-20 ns

**Superscalar ao486:**
- Target: 50-70 MHz (slightly lower due to added logic)
- Critical path estimate: ~14-20 ns (+1 ns worst case)

### SDC Constraints (Example)

```sdc
# Create base clock constraint
create_clock -name clk -period 20.0 [get_ports clk]

# Set input delay constraints
set_input_delay -clock clk -max 5.0 [get_ports {rst_n rd_*}]
set_input_delay -clock clk -min 1.0 [get_ports {rst_n rd_*}]

# Set output delay constraints
set_output_delay -clock clk -max 5.0 [get_ports {exe_* wr_*}]
set_output_delay -clock clk -min -1.0 [get_ports {exe_* wr_*}]

# False paths (if any - typically none for this design)

# Multi-cycle paths (if needed for difficult timing)
# Example: If multiply takes 3 cycles, could add:
# set_multicycle_path -setup 3 -from [get_registers mult_active] -to [get_registers alu*_result_r]
```

---

## Common Synthesis Warnings and Solutions

### Warning: Inferred Latches

```
Warning: Inferred latch for "signal_name"
```

**Cause:** Incomplete case statement or combinational always block

**Check:**
- All case statements have `default` clause
- All combinational logic assigns to all outputs in all paths

**Solution:** Add default assignments

### Warning: Tri-State Conflict

```
Warning: Tri-state node "signal_name" has multiple drivers
```

**Cause:** Shouldn't happen in this design (no tri-states)

**Solution:** Review code for multiple assignments to same signal

### Warning: Clock Multiplexing

```
Warning: Clock multiplexing detected
```

**Cause:** Shouldn't happen (single clock domain)

**Solution:** Verify no gated clocks in design

### Info: DSP Block Packing

```
Info: DSP block is packed with other DSP block
```

**Status:** Normal - multiplier mapped to DSP efficiently

### Warning: Timing Requirements Not Met

```
Critical Warning: Timing requirements not met
Setup slack: -0.5 ns
```

**Solutions (in order of preference):**
1. **Reduce clock frequency:** 75 MHz → 70 MHz → 65 MHz
2. **Enable physical synthesis optimizations**
3. **Add pipeline stage** (requires architectural change)
4. **Register high-fanout signals**
5. **Optimize critical path manually**

---

## Synthesis Flow

### Step-by-Step Process

**1. Clean Build**
```bash
cd ao486_MiSTer
# Remove previous build
rm -rf output_files/
```

**2. Run Analysis & Elaboration**
```
Quartus Prime -> Processing -> Start -> Start Analysis & Elaboration
```

**Expected messages:**
- ✅ No combinational loops
- ✅ Multiplier inferred
- ✅ All files parsed successfully

**3. Full Compilation**
```
Quartus Prime -> Processing -> Start Compilation
```

**Monitor:**
- Analysis & Synthesis phase: ~5-10 min
- Fitter phase: ~10-20 min
- Timing Analysis phase: ~2-5 min

**4. Review Reports**

**Compilation Report → Analysis & Synthesis:**
- Check "Analysis & Synthesis Resource Usage Summary"
- Verify ALM and Register counts match expectations

**Compilation Report → Fitter:**
- Check "Fitter Resource Usage Summary"
- Verify fit successful with margin

**Compilation Report → TimeQuest:**
- Check "Setup Summary"
- Verify all clocks meet timing
- Review worst-case slack (should be ≥ 0)

---

## Post-Synthesis Verification

### 1. Verify Critical Signals

Use Signal Tap Logic Analyzer to verify:

**Dispatch Signals:**
- `dispatch_inst0`
- `dispatch_inst1`
- `dual_issue`
- `stall_dependency`
- `stall_structural`

**ALU Busy/Ready:**
- `alu0_busy`, `alu0_ready`
- `alu1_busy`, `alu1_ready`
- `mult_active`, `mult_counter`

**Writeback:**
- `alu0_valid_r`, `alu0_result_r`
- `alu1_valid_r`, `alu1_result_r`
- `wr0_eax`, `wr1_eax` (example)

**Flags:**
- `alu0_flags_valid_r`
- `alu1_flags_valid_r`
- `exe_result_signals`

### 2. Check for X-Propagation

In simulation (if using ModelSim/QuestaSim):
```
vsim -novopt +notimingchecks ao486_top
```

Verify no 'X' or 'U' values propagate during normal operation.

### 3. Functional Testing on FPGA

**Boot test:**
1. Program FPGA with ao486 core
2. Boot DOS
3. Run simple test program
4. Verify correct execution

**Benchmark test:**
1. Run Dhrystone/CoreMark
2. Measure IPC (if instrumented)
3. Compare performance vs single-issue

---

## Troubleshooting

### Problem: Combinational Loop Warning

**Symptom:**
```
Warning: Found combinational loop of 5 nodes
```

**Diagnosis:**
- Check `alu0_busy` and `alu1_busy` implementation
- Verify they use `alu*_executing_r` (registered), not `alu*_valid` (combinational)

**Fix:**
- Verify Bug #25 fix is applied
- Confirm no accidental reversion

### Problem: Timing Failure on Dispatch Path

**Symptom:**
```
Setup slack: -1.2 ns
From: dispatch.v:inst0_to_alu0
To: dual_execute.v:alu0_arith_result
```

**Diagnosis:**
- Long combinational path from dispatch to execution

**Fixes:**
1. **Register dispatch decision:**
   ```verilog
   // Add pipeline stage
   reg inst0_to_alu0_r;
   always @(posedge clk) inst0_to_alu0_r <= inst0_to_alu0;
   ```

2. **Reduce clock frequency:** 70 MHz → 65 MHz

3. **Enable retiming:**
   ```
   Fitter Settings -> Physical Synthesis -> Register Retiming: On
   ```

### Problem: Resource Overflow

**Symptom:**
```
Error: Can't fit design in device
ALMs: 42,000 / 41,000 (102%)
```

**Diagnosis:**
- Design too large for target device

**Fixes:**
1. **Use larger device:** Cyclone V → Cyclone V GX
2. **Reduce other features:** Disable unused peripherals
3. **Optimize area:**
   ```
   Optimization Technique: Area
   ```

### Problem: DSP Block Shortage

**Symptom:**
```
Warning: Insufficient DSP blocks
Required: 5
Available: 4
```

**Diagnosis:**
- Multiplier not sharing DSP efficiently

**Fix:**
- Verify only ONE shared multiplier in `dual_execute.v`
- Check no duplicate multiply logic elsewhere

---

## Performance Tuning After Synthesis

### If Timing Met with Margin

**Slack > 2 ns?**
→ Can increase clock frequency
- 50 MHz → 60 MHz (test stability)
- Higher IPC × higher frequency = better performance

### If Barely Meeting Timing

**Slack < 0.5 ns?**
→ Risky, may fail on other devices
- Reduce frequency slightly for margin
- Enable more aggressive fitter optimizations

### Trade-offs

| Optimization | Area | Speed | Power |
|-------------|------|-------|-------|
| Balanced | 0 (baseline) | 0 (baseline) | 0 (baseline) |
| Speed | +5-10% | +10-15% | +5-10% |
| Area | -10-15% | -5-10% | -5-10% |

**Recommendation:** Start with Balanced, move to Speed only if timing fails.

---

## Recommended Workflow

```
1. Clean build
2. Synthesize with Balanced optimization
3. Check timing
   ├─ Met with margin (≥1ns) → Done ✓
   ├─ Met but tight (0.1-1ns) → Enable physical synthesis → Recheck
   └─ Failed → Reduce frequency OR enable Speed optimization
4. Verify resource usage < 90% of device
5. Generate bitstream
6. Test on hardware
7. Profile performance (IPC, benchmarks)
8. Iterate if needed
```

---

## Success Criteria

### Synthesis Complete ✓
- ✅ No errors
- ✅ No combinational loop warnings
- ✅ Resource usage < 95%
- ✅ Timing met with slack ≥ 0 ns
- ✅ DSP blocks utilized for multiply

### Functional Test ✓
- ✅ Boots to DOS
- ✅ Runs test programs correctly
- ✅ No crashes or lockups
- ✅ Dual-issue verified in SignalTap

### Performance Test ✓
- ✅ IPC > 1.2 on typical code
- ✅ Benchmark speedup ≥ 1.25x
- ✅ No regressions vs single-issue

---

## Quick Reference

### File Checklist
- ✅ `dual_execute.v` - SystemVerilog
- ✅ All modules compile without warnings
- ✅ Quartus project includes all modified files

### Synthesis Settings
- ✅ Optimization: Balanced
- ✅ Physical synthesis: On
- ✅ Timing analysis: Enabled

### Post-Synthesis
- ✅ Timing slack ≥ 0
- ✅ Resource usage acceptable
- ✅ SignalTap verification
- ✅ Hardware test successful

---

*Synthesis guide for 2-way superscalar ao486*
*Quartus Prime specific recommendations*
*Last updated: 2025-11-22*
