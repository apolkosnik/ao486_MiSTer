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

# Verilog include paths
INCLUDES = -I$(RTL_DIR) -I../../rtl/ao486/autogen

# Compiler flags
VFLAGS = -g2009 $(INCLUDES) -Wall

#==============================================================================
# Targets
#==============================================================================

.PHONY: all clean help test_queue test_dispatch view_queue view_dispatch

# Default target
all: test_queue test_dispatch

# Help
help:
	@echo "Superscalar Test Suite"
	@echo "======================"
	@echo ""
	@echo "Available targets:"
	@echo "  all           - Run all tests"
	@echo "  test_queue    - Run instruction queue tests"
	@echo "  test_dispatch - Run dispatch logic tests"
	@echo "  view_queue    - View queue test waveforms"
	@echo "  view_dispatch - View dispatch test waveforms"
	@echo "  clean         - Remove generated files"
	@echo "  help          - Show this help"
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
