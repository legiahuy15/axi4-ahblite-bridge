#=============================================================================
# File        : Makefile
# Project     : AXI4 to AHB-Lite Bridge VIP
# Author      : Huy Le
# Description : QuestaSim targets for the basic DUT testbenches
#=============================================================================

.DEFAULT_GOAL := run

SHELL := /bin/bash

TOP       ?= tb_axi_ahblite_bridge_smoke
MAKEFILE_DIR := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))
TB        ?= $(MAKEFILE_DIR)tb_axi_ahblite_bridge_smoke.sv
FILELIST  ?= $(MAKEFILE_DIR)dut_files_list.f
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

.PHONY: all run compile rd-wait regress gui view clean help check-tools

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
	@cd "$(MAKEFILE_DIR)" && { test -d work || "$(VLIB)" work; }
	@cd "$(MAKEFILE_DIR)" && "$(VMAP)" work work
	cd "$(MAKEFILE_DIR)" && "$(VLOG)" $(VLOG_FLAGS) -work work -f "$(FILELIST)" "$(TB)"

run: compile
	cd "$(MAKEFILE_DIR)" && "$(VSIM)" -c $(VSIM_FLAGS) "work.$(TOP)" \
		-l "$(LOG)" -wlf "$(WLF)" \
		-do 'onerror {quit -code 1}; log -r /*; run -all; quit -code 0'
	@grep -q 'TEST PASS:' "$(MAKEFILE_DIR)$(LOG)" || { \
		echo "ERROR: test did not report TEST PASS; see $(MAKEFILE_DIR)$(LOG)"; \
		exit 1; \
	}

rd-wait:
	$(MAKE) run \
		TOP=tb_ahb_mstr_rd_wait \
		TB="$(MAKEFILE_DIR)tb_ahb_mstr_rd_wait.sv" \
		LOG=rd_wait.log \
		WLF=rd_wait.wlf

regress:
	$(MAKE) run
	$(MAKE) rd-wait

gui: compile
	cd "$(MAKEFILE_DIR)" && "$(VSIM)" -gui $(VSIM_FLAGS) "work.$(TOP)" \
		-do 'add wave -r sim:/$(TOP)/*'

view: check-tools
	@test -f "$(MAKEFILE_DIR)$(WLF)" || { echo "ERROR: $(WLF) not found; run 'make' first"; exit 1; }
	cd "$(MAKEFILE_DIR)" && "$(VSIM)" -view "$(WLF)"

clean:
	rm -rf -- "$(MAKEFILE_DIR)work"
	rm -f -- "$(MAKEFILE_DIR)transcript" "$(MAKEFILE_DIR)modelsim.ini" \
		"$(MAKEFILE_DIR)$(LOG)" "$(MAKEFILE_DIR)$(WLF)" \
		"$(MAKEFILE_DIR)rd_wait.log" "$(MAKEFILE_DIR)rd_wait.wlf"

help:
	@printf '%s\n' \
		'make          Compile and run the smoke test in console mode' \
		'make compile  Compile DUT and testbench only' \
		'make rd-wait  Run directed AHB_RD_WAIT restart checks' \
		'make regress  Run smoke and AHB_RD_WAIT regressions' \
		'make gui      Compile and open the testbench in QuestaSim GUI' \
		'make view     Open the waveform saved by the last console run' \
		'make clean    Remove generated simulation files' \
		'make help     Show this help' \
		'' \
		'If QuestaSim is not in PATH:' \
		'  make QUESTA_BIN=/opt/questa/bin/'
