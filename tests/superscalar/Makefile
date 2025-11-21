#==============================================================================
# Makefile for Superscalar Test Suite
#
# Requires: Icarus Verilog (iverilog) and GTKWave
#==============================================================================

# Verilog compiler
IVERILOG = iverilog
VVP = vvp
GTKWAVE = gtkwave

# Source directories
RTL_DIR = ../../rtl/ao486/pipeline
TEST_DIR = .

# RTL source files
RTL_SOURCES = \
	$(RTL_DIR)/instruction_queue.v \
	$(RTL_DIR)/dispatch.v \
	$(RTL_DIR)/dual_execute.v

# Test benches
TB_QUEUE = tb_instruction_queue
TB_DISPATCH = tb_dispatch
TB_EXECUTE = tb_dual_execute
TB_WRITEBACK = tb_writeback

# Verilog include paths
INCLUDES = -I$(RTL_DIR) -I../../rtl/ao486/autogen

# Compiler flags
VFLAGS = -g2009 $(INCLUDES) -Wall

#==============================================================================
# Targets
#==============================================================================

.PHONY: all clean help test_queue test_dispatch test_execute test_writeback \
        view_queue view_dispatch view_execute view_writeback

# Default target
all: test_queue test_dispatch test_execute test_writeback

# Help
help:
	@echo "Superscalar Test Suite"
	@echo "======================"
	@echo ""
	@echo "Available targets:"
	@echo "  all            - Run all tests"
	@echo "  test_queue     - Run instruction queue tests"
	@echo "  test_dispatch  - Run dispatch logic tests"
	@echo "  test_execute   - Run dual execute tests"
	@echo "  test_writeback - Run dual writeback tests"
	@echo "  view_queue     - View queue test waveforms"
	@echo "  view_dispatch  - View dispatch test waveforms"
	@echo "  view_execute   - View execute test waveforms"
	@echo "  view_writeback - View writeback test waveforms"
	@echo "  clean          - Remove generated files"
	@echo "  help           - Show this help"
	@echo ""
	@echo "Requirements:"
	@echo "  - Icarus Verilog (iverilog)"
	@echo "  - GTKWave (for waveform viewing)"

#==============================================================================
# Instruction Queue Tests
#==============================================================================

$(TB_QUEUE).vvp: $(TB_QUEUE).v $(RTL_DIR)/instruction_queue.v
	@echo "Compiling instruction queue test..."
	$(IVERILOG) $(VFLAGS) -o $@ $^
	@echo "Compilation successful!"

test_queue: $(TB_QUEUE).vvp
	@echo ""
	@echo "Running instruction queue tests..."
	@echo "===================================="
	$(VVP) $(TB_QUEUE).vvp
	@echo ""

view_queue: $(TB_QUEUE).vcd
	$(GTKWAVE) $(TB_QUEUE).vcd &

#==============================================================================
# Dispatch Logic Tests
#==============================================================================

$(TB_DISPATCH).vvp: $(TB_DISPATCH).v $(RTL_DIR)/dispatch.v
	@echo "Compiling dispatch logic test..."
	$(IVERILOG) $(VFLAGS) -o $@ $^
	@echo "Compilation successful!"

test_dispatch: $(TB_DISPATCH).vvp
	@echo ""
	@echo "Running dispatch logic tests..."
	@echo "================================"
	$(VVP) $(TB_DISPATCH).vvp
	@echo ""

view_dispatch: $(TB_DISPATCH).vcd
	$(GTKWAVE) $(TB_DISPATCH).vcd &

#==============================================================================
# Dual Execute Tests
#==============================================================================

$(TB_EXECUTE).vvp: $(TB_EXECUTE).v $(RTL_DIR)/dual_execute.v
	@echo "Compiling dual execute test..."
	$(IVERILOG) $(VFLAGS) -o $@ $^
	@echo "Compilation successful!"

test_execute: $(TB_EXECUTE).vvp
	@echo ""
	@echo "Running dual execute tests..."
	@echo "=============================="
	$(VVP) $(TB_EXECUTE).vvp
	@echo ""

view_execute: $(TB_EXECUTE).vcd
	$(GTKWAVE) $(TB_EXECUTE).vcd &

#==============================================================================
# Writeback Tests
#==============================================================================

$(TB_WRITEBACK).vvp: $(TB_WRITEBACK).v $(RTL_DIR)/write_register.v
	@echo "Compiling dual writeback test..."
	$(IVERILOG) $(VFLAGS) -o $@ $^
	@echo "Compilation successful!"

test_writeback: $(TB_WRITEBACK).vvp
	@echo ""
	@echo "Running dual writeback tests..."
	@echo "================================"
	$(VVP) $(TB_WRITEBACK).vvp
	@echo ""

view_writeback: $(TB_WRITEBACK).vcd
	$(GTKWAVE) $(TB_WRITEBACK).vcd &

#==============================================================================
# Full Test Suite
#==============================================================================

test: all
	@echo ""
	@echo "=========================================="
	@echo "All Tests Complete!"
	@echo "=========================================="

#==============================================================================
# Cleanup
#==============================================================================

clean:
	@echo "Cleaning generated files..."
	rm -f *.vvp *.vcd
	@echo "Clean complete!"

#==============================================================================
# VCD Generation (automatic)
#==============================================================================

%.vcd: %.vvp
	$(VVP) $<
