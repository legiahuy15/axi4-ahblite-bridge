#=============================================================================
# File        : Makefile
# Project     : AXI4 to AHB-Lite Bridge VIP
# Author      : Huy Le
# Description : QuestaSim build and smoke-test targets for Linux
#=============================================================================

.DEFAULT_GOAL := run

SHELL := /bin/bash

TOP       ?= tb_axi_ahblite_bridge_smoke
TB        ?= tb_axi_ahblite_bridge_smoke.sv
DUT_DIR   ?= src/dut
LOG       ?= smoke.log
WLF       ?= smoke.wlf

# Leave empty when QuestaSim tools are already in PATH. If not, pass a path
# ending in '/', for example: make QUESTA_BIN=/opt/questa/bin/
QUESTA_BIN ?=
VLIB       ?= $(QUESTA_BIN)vlib
VMAP       ?= $(QUESTA_BIN)vmap
VLOG       ?= $(QUESTA_BIN)vlog
VSIM       ?= $(QUESTA_BIN)vsim

VLOG_FLAGS ?= -sv
VSIM_FLAGS ?=

# Keep the same compile order as src/dut/files.f. Do not compile
# axi_ahblite_bridge_all.sv because it duplicates the modules below.
DUT_SRCS := \
	$(DUT_DIR)/counter_f.sv \
	$(DUT_DIR)/time_out.sv \
	$(DUT_DIR)/ahb_skid_buf.sv \
	$(DUT_DIR)/axi_slv_if.sv \
	$(DUT_DIR)/ahb_mstr_if.sv \
	$(DUT_DIR)/axi_ahblite_bridge.sv

.PHONY: all run compile gui view clean help check-tools

all: run

check-tools:
	@for tool in "$(VLIB)" "$(VMAP)" "$(VLOG)" "$(VSIM)"; do \
		command -v "$$tool" >/dev/null 2>&1 || { \
			echo "ERROR: QuestaSim command not found: $$tool"; \
			echo "Add QuestaSim bin to PATH or use QUESTA_BIN=/path/to/questa/bin/"; \
			exit 127; \
		}; \
	done

compile: check-tools
	@test -d work || "$(VLIB)" work
	@"$(VMAP)" work work
	"$(VLOG)" $(VLOG_FLAGS) -work work $(DUT_SRCS) "$(TB)"

run: compile
	"$(VSIM)" -c $(VSIM_FLAGS) "work.$(TOP)" \
		-l "$(LOG)" -wlf "$(WLF)" \
		-do 'onerror {quit -code 1}; log -r /*; run -all; quit -code 0'
	@grep -q 'TEST PASS:' "$(LOG)" || { \
		echo "ERROR: smoke test did not report TEST PASS; see $(LOG)"; \
		exit 1; \
	}

gui: compile
	"$(VSIM)" -gui $(VSIM_FLAGS) "work.$(TOP)" \
		-do 'add wave -r sim:/$(TOP)/*'

view: check-tools
	@test -f "$(WLF)" || { echo "ERROR: $(WLF) not found; run 'make' first"; exit 1; }
	"$(VSIM)" -view "$(WLF)"

clean:
	rm -rf -- work
	rm -f -- transcript modelsim.ini "$(LOG)" "$(WLF)"

help:
	@printf '%s\n' \
		'make          Compile and run the smoke test in console mode' \
		'make compile  Compile DUT and testbench only' \
		'make gui      Compile and open the testbench in QuestaSim GUI' \
		'make view     Open the waveform saved by the last console run' \
		'make clean    Remove generated simulation files' \
		'make help     Show this help' \
		'' \
		'If QuestaSim is not in PATH:' \
		'  make QUESTA_BIN=/opt/questa/bin/'
