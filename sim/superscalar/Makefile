# Makefile for Superscalar Test Benches
#
# Requirements:
# - Icarus Verilog (iverilog)
# - GTKWave (for viewing waveforms)
#
# Usage:
#   make test_dispatch   - Run dispatch test bench
#   make wave_dispatch   - View dispatch waveform
#   make clean           - Remove generated files
#   make all             - Run all tests

IVERILOG = iverilog
VVP = vvp
GTKWAVE = gtkwave

# Include paths
INCLUDES = -I../../rtl/ao486 -I../../rtl/ao486/pipeline

# Source files
DISPATCH_SRC = ../../rtl/ao486/pipeline/dispatch.v
FORWARDING_SRC = ../../rtl/ao486/pipeline/forwarding.v
DUAL_EXECUTE_SRC = ../../rtl/ao486/pipeline/dual_execute.v

# Test benches
TB_DISPATCH = tb_dispatch.v

# Output files
DISPATCH_OUT = dispatch_test.vvp
DISPATCH_VCD = tb_dispatch.vcd

.PHONY: all test_dispatch wave_dispatch clean help

all: test_dispatch

#------------------------------------------------------------------------------
# Dispatch Unit Tests
#------------------------------------------------------------------------------

test_dispatch: $(DISPATCH_OUT)
	@echo "========================================="
	@echo "Running Dispatch Unit Tests"
	@echo "========================================="
	$(VVP) $(DISPATCH_OUT)
	@echo ""
	@echo "Waveform saved to: $(DISPATCH_VCD)"
	@echo "View with: make wave_dispatch"

$(DISPATCH_OUT): $(TB_DISPATCH) $(DISPATCH_SRC)
	$(IVERILOG) $(INCLUDES) -o $(DISPATCH_OUT) $(TB_DISPATCH) $(DISPATCH_SRC)

wave_dispatch: $(DISPATCH_VCD)
	$(GTKWAVE) $(DISPATCH_VCD) &

#------------------------------------------------------------------------------
# Clean
#------------------------------------------------------------------------------

clean:
	rm -f *.vvp *.vcd *.log
	@echo "Cleaned up generated files"

#------------------------------------------------------------------------------
# Help
#------------------------------------------------------------------------------

help:
	@echo "Superscalar Test Bench Makefile"
	@echo ""
	@echo "Targets:"
	@echo "  test_dispatch   - Run dispatch unit tests"
	@echo "  wave_dispatch   - View dispatch waveform with GTKWave"
	@echo "  clean           - Remove generated files"
	@echo "  help            - Show this help message"
	@echo ""
	@echo "Requirements:"
	@echo "  - Icarus Verilog (iverilog)"
	@echo "  - GTKWave (optional, for viewing waveforms)"
	@echo ""
	@echo "Example:"
	@echo "  make test_dispatch"
