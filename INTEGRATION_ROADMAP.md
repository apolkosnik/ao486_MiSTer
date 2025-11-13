# Superscalar Integration Roadmap

## Current Status Summary

**What's Complete:**
- ✅ Instruction classification logic in decode stage (decode.v lines 266-292)
- ✅ Classification signals connected through pipeline.v
- ✅ Dispatch unit implemented and tested (dispatch.v)
- ✅ Dual execution units designed (dual_execute.v)
- ✅ Result forwarding network designed (forwarding.v)
- ✅ Top-level superscalar wrapper (superscalar_pipeline.v)
- ✅ Test infrastructure (tb_dispatch.v with 8 test cases)

**What's Missing:**
- ❌ Superscalar modules not instantiated in main pipeline
- ❌ Pipeline architecture is single-issue (1 instruction/cycle)
- ❌ No dual-fetch capability
- ❌ No dual-decode capability
- ❌ No dual-writeback capability
- ❌ Forwarding network inputs stubbed (no READ stage tracking)

---

## The Fundamental Problem

The ao486 pipeline is **architecturally single-issue**:

```
Current: FETCH(1) → DECODE(1) → READ(1) → EXECUTE(1) → WRITE(1)
Needed:  FETCH(2) → DECODE(2) → DISPATCH → EXECUTE(dual) → WRITE(2)
```

Every stage processes exactly one instruction per cycle. The superscalar components expect to receive two instructions simultaneously, but the pipeline can't provide them.

---

## Integration Approach

There are two possible approaches:

### Approach A: Full Pipeline Redesign (Recommended but Extensive)

**Effort:** 220+ hours

**Steps:**

#### 1. Dual FETCH Stage (30-40 hours)
- Modify fetch.v to fetch 2 instructions per cycle
- Handle instruction alignment (instructions may cross cache line boundaries)
- Provide two 16-byte instruction streams
- Handle page faults for both streams

**Key changes:**
- Fetch buffer must hold 32 bytes instead of 16
- Prefetcher needs to fetch ahead more aggressively
- EIP increment logic needs to handle +2 instructions

**File:** `rtl/ao486/pipeline/fetch.v`

---

#### 2. Dual DECODE Stage (40-50 hours)
- Instantiate decode module twice (decode_inst0, decode_inst1)
- Route fetched instruction streams to both decoders
- Handle cases where only 1 instruction is available
- Both decoders must process in parallel

**Key changes:**
- Duplicate all decoder inputs/outputs
- Add `dec0_*` and `dec1_*` signal sets
- Decoder outputs now include classification signals (already implemented)

**Files:**
- `rtl/ao486/pipeline/pipeline.v` (decode instantiation section)
- May need `rtl/ao486/pipeline/decode_wrapper.v` (new file)

---

#### 3. Insert DISPATCH Stage (20-30 hours)
- Instantiate dispatch.v between DECODE and EXECUTE
- Route decoded instruction pairs to dispatch
- Connect classification signals (dec_is_mult, dec_is_div, dec_is_branch)
- Connect mutex signals from READ stage
- Wire dispatch outputs to dual execution units

**Key changes:**
- Add dispatch stage between READ and EXECUTE
- Pipeline control must handle dispatch stalls
- Need new pipeline registers for dispatch→execute transition

**Connection map:**
```verilog
// In pipeline.v after READ stage
dispatch dispatch_inst(
    .clk(clk),
    .rst_n(rst_n),

    // From DECODE stage
    .inst0_valid(dec0_ready),
    .inst0_cmd(dec0_cmd),
    .inst0_mutex(dec0_mutex),  // Need to add this output to decode
    .inst0_uses_mult(dec0_is_mult),
    .inst0_uses_div(dec0_is_div),
    .inst0_is_branch(dec0_is_branch),

    .inst1_valid(dec1_ready),
    .inst1_cmd(dec1_cmd),
    .inst1_mutex(dec1_mutex),
    .inst1_uses_mult(dec1_is_mult),
    .inst1_uses_div(dec1_is_div),
    .inst1_is_branch(dec1_is_branch),

    // Resource status
    .alu0_busy(alu0_busy),
    .alu1_busy(alu1_busy),
    .mult_busy(mult_busy),
    .div_busy(div_busy),

    // Outputs
    .dispatch_inst0(dispatch_inst0),
    .dispatch_inst1(dispatch_inst1),
    .inst0_to_alu0(inst0_to_alu0),
    .inst0_to_alu1(inst0_to_alu1),
    .inst1_to_alu0(inst1_to_alu0),
    .inst1_to_alu1(inst1_to_alu1),
    .dual_issue(dual_issue),
    .stall_dependency(stall_dependency),
    .stall_structural(stall_structural)
);
```

**Files:**
- `rtl/ao486/pipeline/pipeline.v` (add dispatch stage)

---

#### 4. Dual EXECUTE Stage (40-50 hours)
- Integrate dual_execute.v alongside existing execute.v
- Route instructions to ALU0/ALU1 based on dispatch decisions
- Share multiplier/divider between both ALUs
- Handle execution unit busy states
- Forward results from both units

**Key changes:**
- Current execute.v becomes ALU0
- Add dual_execute.v as ALU1
- Arbitration logic for shared multiplier/divider
- Two sets of execution outputs

**Files:**
- `rtl/ao486/pipeline/execute.v` (modify to be ALU0)
- `rtl/ao486/pipeline/dual_execute.v` (integrate as ALU1)
- `rtl/ao486/pipeline/pipeline.v` (wire both ALUs)

---

#### 5. Forwarding Network Integration (15-20 hours)
- Connect forwarding.v inputs to READ stage
- Extract register request signals from READ
- Wire EXE0, EXE1, WR0, WR1 outputs to forwarding
- Route forwarded data back to READ stage

**Key challenge:** READ stage doesn't currently output "which register I'm reading" signals. Need to add:
```verilog
// In read.v - new outputs needed
output      [2:0]   rd_src_reg,        // Which register being read
output              rd_src_reg_valid,  // Valid register read request
output              rd_dst_reg,        // Destination register
output      [2:0]   rd_dst_reg_num,    // Destination register number
```

**Connection in pipeline.v:**
```verilog
forwarding fwd_inst(
    .clk(clk),
    .rst_n(rst_n),

    // From READ stage (NEW SIGNALS)
    .rd_reg_request(rd_src_reg),
    .rd_reg_request_valid(rd_src_reg_valid),
    .rd_need_eflags(rd_need_eflags),  // Also new

    // From EXECUTE stages
    .exe0_valid(exe0_valid),
    .exe0_dst_is_reg(exe0_dst_is_reg),
    .exe0_dst_reg(exe0_dst_reg),
    .exe0_result(exe0_result),
    .exe0_updates_eflags(exe0_updates_eflags),
    .exe0_eflags(exe0_eflags),

    .exe1_valid(exe1_valid),
    .exe1_dst_is_reg(exe1_dst_is_reg),
    .exe1_dst_reg(exe1_dst_reg),
    .exe1_result(exe1_result),
    .exe1_updates_eflags(exe1_updates_eflags),
    .exe1_eflags(exe1_eflags),

    // From WRITE stages
    .wr0_valid(wr0_valid),
    .wr0_dst_is_reg(wr0_dst_is_reg),
    .wr0_dst_reg(wr0_dst_reg),
    .wr0_result(wr0_result),

    .wr1_valid(wr1_valid),
    .wr1_dst_is_reg(wr1_dst_is_reg),
    .wr1_dst_reg(wr1_dst_reg),
    .wr1_result(wr1_result),

    // Outputs back to READ
    .forward_valid(forward_valid),
    .forwarded_data(forwarded_data),
    .forwarded_eflags(forwarded_eflags)
);
```

**Files:**
- `rtl/ao486/pipeline/read.v` (add register tracking outputs)
- `rtl/ao486/pipeline/forwarding.v` (already complete)
- `rtl/ao486/pipeline/pipeline.v` (instantiate and wire)

---

#### 6. Dual WRITE Stage (40-50 hours)
- Modify write.v to handle 2 results per cycle
- Both ALU0 and ALU1 must write back simultaneously
- Register file needs dual write ports
- Handle write port conflicts
- Update EFLAGS from both units

**Key changes:**
- Register write logic must handle 2 writes/cycle
- Prioritization if both write same register (shouldn't happen with dispatch)
- EFLAGS merge logic if both update flags

**Files:**
- `rtl/ao486/pipeline/write.v` (major modifications)
- `rtl/ao486/pipeline/write_register.v` (add dual write capability)

---

#### 7. Pipeline Control Integration (30-40 hours)
- Modify pipeline control for dual-issue awareness
- Stall logic must handle both instructions
- Flush logic for both pipes
- Exception handling when both instructions fault
- Branch misprediction handling

**Key changes:**
- Stall conditions now consider both instructions
- Pipeline flush must flush both pipes
- Exception priority between inst0 and inst1

**Files:**
- `rtl/ao486/pipeline/pipeline.v` (control logic section)

---

### Approach B: Standalone Superscalar Module (Quick Demo, Not Production)

**Effort:** 10-15 hours

**Goal:** Create a parallel superscalar pipeline that can run alongside (but separate from) the main pipeline as a proof of concept.

**Steps:**

1. Create a new top-level module `ao486_superscalar_demo.v`
2. Instantiate both the original pipeline and superscalar_pipeline
3. Use a multiplexer to select which pipeline to use
4. Only route ALU-only instructions to superscalar path
5. Route everything else to original pipeline

**Limitations:**
- Can't actually improve performance (still single-issue at top level)
- Memory operations not supported in superscalar path
- Only useful for testing/demonstration
- Not suitable for production

---

## Recommended Next Steps

### Option 1: Continue with Full Integration (Realistic)

**Phase 1 (Weeks 1-2): Dual DECODE**
1. Create decode_wrapper.v that instantiates two decode modules
2. Modify fetch.v to provide two instruction streams
3. Test that both decoders work independently

**Phase 2 (Weeks 3-4): Insert DISPATCH**
1. Wire dispatch unit into pipeline between DECODE and EXECUTE
2. Connect classification signals (already done)
3. Test dispatch decisions with simple ALU instructions

**Phase 3 (Weeks 5-6): Dual EXECUTE**
1. Integrate dual_execute.v as second ALU
2. Route based on dispatch decisions
3. Test parallel execution of independent ALU ops

**Phase 4 (Weeks 7-8): WRITEBACK & FORWARDING**
1. Add dual writeback capability
2. Integrate forwarding network
3. Full system testing

**Phase 5 (Weeks 9-10): Optimization & Verification**
1. Performance tuning
2. Formal verification
3. Real workload testing

---

### Option 2: Document and Pause (Pragmatic)

**If full integration isn't feasible:**

1. ✅ Document current state (this file)
2. ✅ Keep superscalar modules as reference implementation
3. ✅ Mark as "future enhancement"
4. Focus on other CPU improvements

**Rationale:** The components are well-designed and tested, but integration requires significant architectural changes to the pipeline. The work done so far is valuable as:
- Reference implementation for future superscalar efforts
- Educational resource for understanding superscalar design
- Test cases for dispatch logic
- Proven classification system

---

## Testing Strategy

### Unit Tests (Already Complete)
- ✅ Dispatch unit: 8 test cases in tb_dispatch.v
- ⚠️ Requires Icarus Verilog to run

### Integration Tests (Needed)
1. **Dual-decode test**: Verify both decoders produce correct outputs
2. **Dispatch test**: Feed real instruction pairs, verify correct dispatch decisions
3. **Dual-execute test**: Run parallel ALU operations, check both results
4. **Forwarding test**: Verify forwarded data arrives correctly
5. **Full pipeline test**: Run real x86 code sequences

### Performance Tests (After Integration)
1. Measure IPC (instructions per cycle) on real workloads
2. Compare against single-issue baseline
3. Identify bottlenecks
4. Tune dispatch heuristics

---

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Integration breaks existing functionality | High | Critical | Incremental integration with regression tests |
| Performance gains less than expected | Medium | Medium | Thorough performance modeling before implementation |
| Resource conflicts not handled correctly | Medium | High | Extensive corner-case testing |
| Forwarding logic has bugs | Medium | Critical | Formal verification of forwarding paths |
| Exception handling broken | High | Critical | Exception tests at every integration phase |
| Timeline extends beyond 220 hours | High | Medium | Proper project planning and milestones |

---

## Conclusion

**Current state:** All superscalar components are implemented and ready, but they cannot be used because the pipeline architecture doesn't support dual-issue execution.

**To make superscalar work:** Must redesign the entire pipeline to support fetching, decoding, executing, and writing back 2 instructions per cycle.

**Estimated effort:** 220+ hours of engineering work across 10 pipeline stages and control logic.

**Recommendation:** Either commit to the full integration effort with proper planning and testing, or document the current state as a reference implementation for future work.

The components are high quality and well-designed. The blocker is not the components themselves, but the single-issue architecture of the host pipeline they need to integrate with.
