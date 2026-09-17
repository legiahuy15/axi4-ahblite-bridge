#=============================================================================
# File        : Makefile
# Project     : AXI4 to AHB-Lite Bridge VIP
# Author      : Huy Le
# Description : QuestaSim build, run, regression, and coverage targets.
#=============================================================================

.DEFAULT_GOAL := run

SHELL := /bin/bash

#-----------------------------------------------------------------------------
# Paths and tools
#-----------------------------------------------------------------------------
MAKEFILE_DIR := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))

FILELIST     ?= bridge_files.f
REPORT_DIR   ?= report
LOG_DIR       = $(REPORT_DIR)/logs
WLF_DIR       = $(REPORT_DIR)/wlf
COV_DIR       = $(REPORT_DIR)/coverage
COV_HTML_DIR  = $(REPORT_DIR)/cov_html

QUESTA_BIN ?=
VLIB        ?= $(QUESTA_BIN)vlib
VMAP        ?= $(QUESTA_BIN)vmap
VLOG        ?= $(QUESTA_BIN)vlog
VOPT        ?= $(QUESTA_BIN)vopt
VSIM        ?= $(QUESTA_BIN)vsim
VCOVER      ?= $(QUESTA_BIN)vcover

#-----------------------------------------------------------------------------
# Simulation configuration
#-----------------------------------------------------------------------------
TOP           ?= bridge_tb_top
OPT_TOP       ?= opt_bridge_tb_top
OPT_TOP_NARROW ?= opt_bridge_tb_top_narrow
NARROW        ?= 0
TESTNAME      ?= bridge_sanity_test
SEED          ?= random
UVM_VERBOSITY ?= UVM_LOW
NUM_RUNS      ?= 5
USE_COVERAGE  ?= 1
PLUSARGS      ?=

TEST_LIST ?= bridge_sanity_test bridge_data_integrity_test \
	     bridge_burst_matrix_test bridge_incr_mapping_test \
	     bridge_fixed_mapping_test bridge_wrap_mapping_test \
	     bridge_1kb_boundary_test bridge_unsupported_feature_test \
	     bridge_size_mapping_test bridge_single_wstrb_test

# Tests that also run on the C_S_AXI_SUPPORTS_NARROW_BURST=1 build
NARROW_TEST_LIST ?= bridge_data_integrity_test bridge_size_mapping_test \
		    bridge_single_wstrb_test

VLOG_FLAGS ?= -sv -mfcu -work work -timescale 1ns/1ps
VOPT_FLAGS ?= +acc -work work
VSIM_FLAGS ?= -c

VLOG_FLAGS += -l $(LOG_DIR)/compile.log

# A run fails on non-zero UVM error/fatal counts, on simulator error/fatal
# messages (SVA $error/$fatal bypass the UVM report server), or on a
# non-zero vsim error summary.
FAIL_REGEX := UVM_(ERROR|FATAL)[[:space:]]*:[[:space:]]*[1-9][0-9]*|^\# \*\* (Error|Fatal)|^\# Errors: [1-9]

RUN_OPT_TOP = $(if $(filter 1,$(NARROW)),$(OPT_TOP_NARROW),$(OPT_TOP))

ifeq ($(USE_COVERAGE),1)
    VLOG_FLAGS += -cover sbcet
    VOPT_FLAGS += -cover sbcet
    VSIM_COV_FLAG = -coverage
else
    VSIM_COV_FLAG =
endif

ifeq ($(SEED),random)
    GEN_SEED := $(shell shuf -i 1-99999999 -n 1 2>/dev/null || \
                 echo $$((($$RANDOM * 32768 + $$RANDOM) % 99999999 + 1)))
else
    GEN_SEED := $(SEED)
endif

RUN_LOG  = $(LOG_DIR)/$(TESTNAME)_seed_$(GEN_SEED).log
RUN_WLF  = $(WLF_DIR)/$(TESTNAME)_seed_$(GEN_SEED).wlf
RUN_UCDB = $(COV_DIR)/$(TESTNAME)_seed_$(GEN_SEED).ucdb

REGRESS_TARGETS = $(foreach test,$(TEST_LIST),\
                  $(foreach idx,$(shell seq 1 $(NUM_RUNS)),\
                  $(test)_run_$(idx))) \
                  $(foreach test,$(NARROW_TEST_LIST),\
                  $(foreach idx,$(shell seq 1 $(NUM_RUNS)),\
                  $(test)_narrow_run_$(idx)))

#-----------------------------------------------------------------------------
# Main targets
#-----------------------------------------------------------------------------
.PHONY: help check-tools compile optimize run gui regress merge_cov \
        cov_report clean

help:
	@echo "AXI4 to AHB-Lite Bridge VIP"
	@echo ""
	@echo "  make run             Run one test in batch mode"
	@echo "  make gui             Run one test in Questa GUI"
	@echo "  make regress         Run TEST_LIST in parallel"
	@echo "  make cov_report      Merge UCDB files and create HTML report"
	@echo "  make clean           Remove generated simulation outputs"
	@echo ""
	@echo "  TESTNAME=<name>      Default: $(TESTNAME)"
	@echo "  SEED=<int/random>    Default: $(SEED)"
	@echo "  UVM_VERBOSITY=<val>  Default: $(UVM_VERBOSITY)"
	@echo "  NUM_RUNS=<n>         Default: $(NUM_RUNS)"
	@echo "  USE_COVERAGE=<0/1>   Default: $(USE_COVERAGE)"
	@echo "  NARROW=<0/1>         Run on narrow-burst DUT build: $(NARROW)"
	@echo "  PLUSARGS=\"...\"     Extra simulation plusargs"
	@echo "  TEST_LIST=\"...\"    Regression test list"
	@echo "  NARROW_TEST_LIST=\"...\" Regression tests on narrow build"

check-tools:
	@for tool in "$(VLIB)" "$(VMAP)" "$(VLOG)" "$(VOPT)" "$(VSIM)"; do \
		command -v "$$tool" >/dev/null 2>&1 || { \
			echo "ERROR: QuestaSim command not found: $$tool"; \
			exit 127; \
		}; \
	done

compile: check-tools
	@cd "$(MAKEFILE_DIR)" && mkdir -p "$(LOG_DIR)"
	@cd "$(MAKEFILE_DIR)" && { test -d work || "$(VLIB)" work; }
	@cd "$(MAKEFILE_DIR)" && "$(VMAP)" work work
	cd "$(MAKEFILE_DIR)" && "$(VLOG)" $(VLOG_FLAGS) -f "$(FILELIST)"

optimize: compile
	@cd "$(MAKEFILE_DIR)" && mkdir -p "$(LOG_DIR)"
	cd "$(MAKEFILE_DIR)" && "$(VOPT)" $(VOPT_FLAGS) \
		-l "$(LOG_DIR)/optimize.log" \
		"work.$(TOP)" -o "$(OPT_TOP)"
	cd "$(MAKEFILE_DIR)" && "$(VOPT)" $(VOPT_FLAGS) \
		-l "$(LOG_DIR)/optimize_narrow.log" \
		-GC_S_AXI_SUPPORTS_NARROW_BURST=1 \
		"work.$(TOP)" -o "$(OPT_TOP_NARROW)"

run: optimize
	@cd "$(MAKEFILE_DIR)" && mkdir -p \
		"$(LOG_DIR)" "$(WLF_DIR)" "$(COV_DIR)"
	@echo "[RUN] $(TESTNAME) | seed=$(GEN_SEED)"
	@cd "$(MAKEFILE_DIR)" && \
		cov_cmd=""; \
		if [ "$(USE_COVERAGE)" = "1" ]; then \
			cov_cmd="coverage save -onexit $(RUN_UCDB);"; \
		fi; \
		"$(VSIM)" $(VSIM_FLAGS) $(VSIM_COV_FLAG) \
			-sv_seed "$(GEN_SEED)" \
			+UVM_TESTNAME="$(TESTNAME)" \
			+UVM_VERBOSITY="$(UVM_VERBOSITY)" \
			$(PLUSARGS) \
			-l "$(RUN_LOG)" -wlf "$(RUN_WLF)" \
			-do "$$cov_cmd run -all; quit -f" \
			"work.$(RUN_OPT_TOP)"
	@cd "$(MAKEFILE_DIR)" && \
		if grep -Eq '$(FAIL_REGEX)' "$(RUN_LOG)" || \
			grep -q '=== TEST FAILED ===' "$(RUN_LOG)"; then \
			echo "[FAILED] $(TESTNAME) | log=$(RUN_LOG)"; \
			exit 1; \
		elif grep -q '=== TEST PASSED ===' "$(RUN_LOG)"; then \
			echo "[PASSED] $(TESTNAME) | log=$(RUN_LOG)"; \
		else \
			echo "[FAILED] Test result marker not found | log=$(RUN_LOG)"; \
			exit 1; \
		fi

gui: optimize
	@cd "$(MAKEFILE_DIR)" && mkdir -p \
		"$(LOG_DIR)" "$(WLF_DIR)" "$(COV_DIR)"
	@echo "[GUI] $(TESTNAME) | seed=$(GEN_SEED)"
	cd "$(MAKEFILE_DIR)" && \
		cov_cmd=""; \
		if [ "$(USE_COVERAGE)" = "1" ]; then \
			cov_cmd="coverage save -onexit $(RUN_UCDB);"; \
		fi; \
		"$(VSIM)" -gui $(VSIM_COV_FLAG) \
			-sv_seed "$(GEN_SEED)" \
			+UVM_TESTNAME="$(TESTNAME)" \
			+UVM_VERBOSITY="$(UVM_VERBOSITY)" \
			$(PLUSARGS) \
			-l "$(RUN_LOG)" -wlf "$(RUN_WLF)" \
			-do "do wave.do; $$cov_cmd run -all" \
			"work.$(RUN_OPT_TOP)"

#-----------------------------------------------------------------------------
# Regression
#-----------------------------------------------------------------------------
regress: optimize
	@cd "$(MAKEFILE_DIR)" && mkdir -p \
		"$(LOG_DIR)" "$(WLF_DIR)" "$(COV_DIR)"
	@echo "[REGRESS] tests=$(TEST_LIST) narrow_tests=$(NARROW_TEST_LIST) runs=$(NUM_RUNS)"
	@$(MAKE) -C "$(MAKEFILE_DIR)" $(REGRESS_TARGETS)

$(REGRESS_TARGETS):
	@cd "$(MAKEFILE_DIR)" && \
		target="$@"; \
		run_name="$${target%_run_*}"; \
		run_idx="$${target##*_run_}"; \
		test_name="$$run_name"; \
		opt_top="$(OPT_TOP)"; \
		case "$$run_name" in \
			*_narrow) test_name="$${run_name%_narrow}"; \
			          opt_top="$(OPT_TOP_NARROW)";; \
		esac; \
		seed=$$(shuf -i 1-99999999 -n 1 2>/dev/null || \
			echo $$((($$RANDOM * 32768 + $$RANDOM) % 99999999 + 1))); \
		log_file="$(LOG_DIR)/$${run_name}_run_$${run_idx}_seed_$${seed}.log"; \
		wlf_file="$(WLF_DIR)/$${run_name}_run_$${run_idx}_seed_$${seed}.wlf"; \
		ucdb_file="$(COV_DIR)/$${run_name}_run_$${run_idx}_seed_$${seed}.ucdb"; \
		cov_cmd=""; \
		if [ "$(USE_COVERAGE)" = "1" ]; then \
			cov_cmd="coverage save -onexit $$ucdb_file;"; \
		fi; \
		echo "[REGRESS] $$run_name | run=$$run_idx seed=$$seed"; \
		"$(VSIM)" $(VSIM_FLAGS) $(VSIM_COV_FLAG) \
			-sv_seed "$$seed" \
			+UVM_TESTNAME="$$test_name" \
			+UVM_VERBOSITY="$(UVM_VERBOSITY)" \
			$(PLUSARGS) \
			-l "$$log_file" -wlf "$$wlf_file" \
			-do "$$cov_cmd run -all; quit -f" \
			"work.$$opt_top"; \
		if grep -Eq '$(FAIL_REGEX)' "$$log_file" || \
			! grep -q '=== TEST PASSED ===' "$$log_file"; then \
			echo "[FAILED] $$run_name | run=$$run_idx log=$$log_file"; \
			exit 1; \
		fi; \
		echo "[PASSED] $$run_name | run=$$run_idx"

#-----------------------------------------------------------------------------
# Coverage report
#-----------------------------------------------------------------------------
merge_cov:
	@cd "$(MAKEFILE_DIR)" && mkdir -p "$(COV_DIR)"
	@cd "$(MAKEFILE_DIR)" && \
		rm -f -- "$(COV_DIR)/merged.ucdb"; \
		set -- $(COV_DIR)/*.ucdb; \
		if [ ! -e "$$1" ]; then \
			echo "ERROR: No UCDB files found in $(COV_DIR)"; \
			exit 1; \
		fi; \
		"$(VCOVER)" merge "$(COV_DIR)/merged.ucdb" "$$@"

cov_report: merge_cov
	@cd "$(MAKEFILE_DIR)" && mkdir -p "$(COV_HTML_DIR)"
	cd "$(MAKEFILE_DIR)" && "$(VCOVER)" report -html \
		-htmldir "$(COV_HTML_DIR)" -verbose "$(COV_DIR)/merged.ucdb"

#-----------------------------------------------------------------------------
# Cleanup
#-----------------------------------------------------------------------------
clean:
	@echo "[CLEAN] Removing generated files under $(MAKEFILE_DIR)"
	@cd "$(MAKEFILE_DIR)" && rm -rf -- work report
	@cd "$(MAKEFILE_DIR)" && rm -f -- \
		transcript vsim.wlf vsim_stacktrace.vstf modelsim.ini *.vcd *.ucdb