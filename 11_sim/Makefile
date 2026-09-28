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
MERGED_UCDB   = $(COV_DIR)/merged.ucdb

# The HTML report carries covergroups and code coverage only, so assertions
# and cover directives get their own text reports
ASSERT_TXT    = $(REPORT_DIR)/assertions.txt
DIRECTIVE_TXT = $(REPORT_DIR)/directives.txt
SVA_DIR       = ../10_tb/sva
COV_SUMMARY_AWK = cov_summary.awk

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
# One image per supported C_DPHASE_TIMEOUT, named <prefix><value>
OPT_TOP_TMO   ?= opt_bridge_tb_top_tmo
# The 64-bit configuration, in its own library because the widths are package
# parameters and have to be set at compile time
WORK64             ?= work64
WIDE_DATA_WIDTH    ?= 64
OPT_TOP_W64        ?= opt_bridge_tb_top_w64
OPT_TOP_W64_NARROW ?= opt_bridge_tb_top_w64_narrow
NARROW        ?= 0
TIMEOUT       ?= 0
WIDE          ?= 0
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
	         bridge_size_mapping_test bridge_single_wstrb_test \
	         bridge_unaligned_read_test bridge_protection_mapping_test \
	         bridge_response_mapping_test bridge_axi_backpressure_test \
	         bridge_timeout_test bridge_read_priority_test \
	         bridge_reset_test bridge_reset_mid_transfer_test \
	         bridge_parameter_test

# Tests that also run on the C_S_AXI_SUPPORTS_NARROW_BURST=1 build
NARROW_TEST_LIST ?= bridge_data_integrity_test bridge_size_mapping_test \
		            bridge_single_wstrb_test bridge_unaligned_read_test \
		            bridge_parameter_test

# Supported non-zero C_DPHASE_TIMEOUT values (PG177) and the tests that run on
# every one of them. The default build covers the C_DPHASE_TIMEOUT=0 case.
TIMEOUT_VALUES    ?= 16 32 64 128 256
TIMEOUT_TEST_LIST ?= bridge_timeout_test bridge_timeout_boundary_test \
                     bridge_timeout_recovery_test

# The compliance subset that also runs on the 64-bit build, narrow off and on.
# Timeout and reset behaviour does not depend on the bus width, so those tests
# stay on the 32-bit build.
PARAM_TEST_LIST ?= bridge_parameter_test bridge_sanity_test \
                   bridge_data_integrity_test bridge_burst_matrix_test \
                   bridge_size_mapping_test bridge_response_mapping_test

VLOG_BASE  ?= -sv -mfcu -timescale 1ns/1ps
VOPT_BASE  ?= +acc
VLOG_FLAGS ?= $(VLOG_BASE) -work work
VOPT_FLAGS ?= $(VOPT_BASE) -work work
VSIM_FLAGS ?= -c

# The bus widths are package parameters, so vopt -G cannot reach them and the
# 64-bit configuration needs its own compilation into its own library
VLOG64_FLAGS = $(VLOG_BASE) -work $(WORK64) \
               +define+BRIDGE_DATA_WIDTH=$(WIDE_DATA_WIDTH)
VOPT64_FLAGS = $(VOPT_BASE) -work $(WORK64)

VLOG_FLAGS   += -l $(LOG_DIR)/compile.log
VLOG64_FLAGS += -l $(LOG_DIR)/compile_w64.log

# A run fails on non-zero UVM error/fatal counts, on simulator error/fatal
# messages (SVA $error/$fatal bypass the UVM report server), or on a
# non-zero vsim error summary.
FAIL_REGEX := UVM_(ERROR|FATAL)[[:space:]]*:[[:space:]]*[1-9][0-9]*|^\# \*\* (Error|Fatal)|^\# Errors: [1-9]

RUN_OPT_TMO = $(if $(filter 0,$(TIMEOUT)),$(OPT_TOP),$(OPT_TOP_TMO)$(TIMEOUT))
RUN_OPT_32  = work.$(if $(filter 1,$(NARROW)),$(OPT_TOP_NARROW),$(RUN_OPT_TMO))
RUN_OPT_W64 = $(if $(filter 1,$(NARROW)),$(OPT_TOP_W64_NARROW),$(OPT_TOP_W64))
RUN_OPT_64  = $(WORK64).$(RUN_OPT_W64)
# Fully qualified library.top, because the 64-bit build lives elsewhere
RUN_OPT_TOP = $(if $(filter 1,$(WIDE)),$(RUN_OPT_64),$(RUN_OPT_32))

# The timeout and 64-bit images cost extra passes, so a plain run only builds
# the ones it actually asks for
RUN_OPT_DEPS = $(if $(filter 1,$(WIDE)),optimize_wide,optimize) \
               $(if $(filter 0,$(TIMEOUT)),,optimize_timeout)

ifeq ($(USE_COVERAGE),1)
    VLOG_FLAGS   += -cover sbcet
    VOPT_FLAGS   += -cover sbcet
    VLOG64_FLAGS += -cover sbcet
    VOPT64_FLAGS += -cover sbcet
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
                  $(test)_narrow_run_$(idx))) \
                  $(foreach tmo,$(TIMEOUT_VALUES),\
                  $(foreach test,$(TIMEOUT_TEST_LIST),\
                  $(foreach idx,$(shell seq 1 $(NUM_RUNS)),\
                  $(test)_tmo$(tmo)_run_$(idx)))) \
                  $(foreach test,$(PARAM_TEST_LIST),\
                  $(foreach idx,$(shell seq 1 $(NUM_RUNS)),\
                  $(test)_w64_run_$(idx))) \
                  $(foreach test,$(PARAM_TEST_LIST),\
                  $(foreach idx,$(shell seq 1 $(NUM_RUNS)),\
                  $(test)_w64n_run_$(idx)))

#-----------------------------------------------------------------------------
# Main targets
#-----------------------------------------------------------------------------
.PHONY: help check-tools compile optimize optimize_timeout compile_wide \
        optimize_wide run gui regress merge_cov cov_report assert_report clean

help:
	@echo "AXI4 to AHB-Lite Bridge VIP"
	@echo ""
	@echo "  make run             Run one test in batch mode"
	@echo "  make gui             Run one test in Questa GUI"
	@echo "  make regress         Run TEST_LIST in parallel"
	@echo "  make cov_report      Merge UCDB files and create HTML report"
	@echo "  make assert_report   Assertion and cover-directive text reports"
	@echo "  make clean           Remove generated simulation outputs"
	@echo ""
	@echo "  TESTNAME=<name>      Default: $(TESTNAME)"
	@echo "  SEED=<int/random>    Default: $(SEED)"
	@echo "  UVM_VERBOSITY=<val>  Default: $(UVM_VERBOSITY)"
	@echo "  NUM_RUNS=<n>         Default: $(NUM_RUNS)"
	@echo "  USE_COVERAGE=<0/1>   Default: $(USE_COVERAGE)"
	@echo "  NARROW=<0/1>         Run on narrow-burst DUT build: $(NARROW)"
	@echo "  TIMEOUT=<0/16/../256> Run on a C_DPHASE_TIMEOUT build: $(TIMEOUT)"
	@echo "  WIDE=<0/1>           Run on the 64-bit build: $(WIDE)"
	@echo "  PLUSARGS=\"...\"     Extra simulation plusargs"
	@echo "  TEST_LIST=\"...\"    Regression test list"
	@echo "  NARROW_TEST_LIST=\"...\" Regression tests on narrow build"
	@echo "  TIMEOUT_VALUES=\"...\"  Timeout builds: $(TIMEOUT_VALUES)"
	@echo "  TIMEOUT_TEST_LIST=\"...\" Regression tests on every timeout build"
	@echo "  PARAM_TEST_LIST=\"...\"   Compliance subset on the 64-bit build"
	@echo "  SKIP_MERGE=1         assert_report: use MERGED_UCDB as it is"

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

# One image per supported C_DPHASE_TIMEOUT. Kept out of 'optimize' so an
# ordinary run does not pay for five extra vopt passes.
optimize_timeout: compile
	@cd "$(MAKEFILE_DIR)" && mkdir -p "$(LOG_DIR)"
	@cd "$(MAKEFILE_DIR)" && for tmo in $(TIMEOUT_VALUES); do \
		echo "[OPTIMIZE] C_DPHASE_TIMEOUT=$$tmo"; \
		"$(VOPT)" $(VOPT_FLAGS) \
			-l "$(LOG_DIR)/optimize_tmo$$tmo.log" \
			-GC_DPHASE_TIMEOUT=$$tmo \
			"work.$(TOP)" -o "$(OPT_TOP_TMO)$$tmo" || exit 1; \
	done

# The 64-bit configuration. A separate compilation, not just a separate vopt,
# because the widths come from package parameters set by BRIDGE_DATA_WIDTH.
compile_wide: check-tools
	@cd "$(MAKEFILE_DIR)" && mkdir -p "$(LOG_DIR)"
	@cd "$(MAKEFILE_DIR)" && { test -d "$(WORK64)" || "$(VLIB)" "$(WORK64)"; }
	@cd "$(MAKEFILE_DIR)" && "$(VMAP)" "$(WORK64)" "$(WORK64)"
	cd "$(MAKEFILE_DIR)" && "$(VLOG)" $(VLOG64_FLAGS) -f "$(FILELIST)"

optimize_wide: compile_wide
	@cd "$(MAKEFILE_DIR)" && mkdir -p "$(LOG_DIR)"
	cd "$(MAKEFILE_DIR)" && "$(VOPT)" $(VOPT64_FLAGS) \
		-l "$(LOG_DIR)/optimize_w64.log" \
		"$(WORK64).$(TOP)" -o "$(OPT_TOP_W64)"
	cd "$(MAKEFILE_DIR)" && "$(VOPT)" $(VOPT64_FLAGS) \
		-l "$(LOG_DIR)/optimize_w64_narrow.log" \
		-GC_S_AXI_SUPPORTS_NARROW_BURST=1 \
		"$(WORK64).$(TOP)" -o "$(OPT_TOP_W64_NARROW)"

run: $(RUN_OPT_DEPS)
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
			"$(RUN_OPT_TOP)"
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

gui: $(RUN_OPT_DEPS)
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
			"$(RUN_OPT_TOP)"

#-----------------------------------------------------------------------------
# Regression
#-----------------------------------------------------------------------------
regress: optimize optimize_timeout optimize_wide
	@cd "$(MAKEFILE_DIR)" && mkdir -p \
		"$(LOG_DIR)" "$(WLF_DIR)" "$(COV_DIR)"
	@echo "[REGRESS] tests=$(TEST_LIST) narrow_tests=$(NARROW_TEST_LIST) timeout_tests=$(TIMEOUT_TEST_LIST) timeouts=$(TIMEOUT_VALUES) runs=$(NUM_RUNS)"
	@$(MAKE) -C "$(MAKEFILE_DIR)" $(REGRESS_TARGETS)

$(REGRESS_TARGETS):
	@cd "$(MAKEFILE_DIR)" && \
		target="$@"; \
		run_name="$${target%_run_*}"; \
		run_idx="$${target##*_run_}"; \
		test_name="$$run_name"; \
		opt_top="work.$(OPT_TOP)"; \
		case "$$run_name" in \
			*_narrow) test_name="$${run_name%_narrow}"; \
			          opt_top="work.$(OPT_TOP_NARROW)";; \
			*_tmo*)   test_name="$${run_name%_tmo*}"; \
			          opt_top="work.$(OPT_TOP_TMO)$${run_name##*_tmo}";; \
			*_w64n)   test_name="$${run_name%_w64n}"; \
			          opt_top="$(WORK64).$(OPT_TOP_W64_NARROW)";; \
			*_w64)    test_name="$${run_name%_w64}"; \
			          opt_top="$(WORK64).$(OPT_TOP_W64)";; \
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
			"$$opt_top"; \
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
		rm -f -- "$(MERGED_UCDB)"; \
		set -- $(COV_DIR)/*.ucdb; \
		if [ ! -e "$$1" ]; then \
			echo "ERROR: No UCDB files found in $(COV_DIR)"; \
			exit 1; \
		fi; \
		"$(VCOVER)" merge "$(MERGED_UCDB)" "$$@"

cov_report: merge_cov
	@cd "$(MAKEFILE_DIR)" && mkdir -p "$(COV_HTML_DIR)"
	cd "$(MAKEFILE_DIR)" && "$(VCOVER)" report -html \
		-htmldir "$(COV_HTML_DIR)" -verbose "$(MERGED_UCDB)"

#-----------------------------------------------------------------------------
# Assertion and cover-directive report
#-----------------------------------------------------------------------------
# The HTML report shows covergroups and code coverage only: after a run its
# global.json holds g_assertViews = 0 and g_directViews = 0, so assertions such
# as B_STABLE and cover directives such as C_B_STALL cannot be reviewed there.
# These text reports are the evidence for the Assertions sheet of the vplan.
#
# Questa collects these counts under plain 'vsim -coverage', so the data is in
# the UCDB already; only the HTML view of it is missing. An assertion pass
# count is one per test, so it reads as the number of runs that hit the
# assertion, not the number of evaluations.
#
# SKIP_MERGE=1 reuses the merged database instead of building it again, which
# is worth it after a plain 'make cov_report'. It is only a shortcut: if the
# database is not there, for instance right after a clean regression, the
# merge runs anyway.
SKIP_MERGE ?= 0

assert_report: $(if $(filter 1,$(SKIP_MERGE)),,merge_cov)
	@cd "$(MAKEFILE_DIR)" && mkdir -p "$(REPORT_DIR)"
	@cd "$(MAKEFILE_DIR)" && \
		if [ ! -e "$(MERGED_UCDB)" ]; then \
			echo "[ASSERT_REPORT] $(MERGED_UCDB) is missing, merging first"; \
			$(MAKE) -C "$(MAKEFILE_DIR)" merge_cov; \
		fi
	@cd "$(MAKEFILE_DIR)" && \
		"$(VCOVER)" report -assert -details "$(MERGED_UCDB)" \
			> "$(ASSERT_TXT)" 2>/dev/null || \
		"$(VCOVER)" report -assert "$(MERGED_UCDB)" \
			> "$(ASSERT_TXT)" || { \
			echo "ERROR: this Questa rejects 'vcover report -assert'."; \
			echo "       Run 'vcover report -help' and use the switch it lists."; \
			exit 1; \
		}
	@cd "$(MAKEFILE_DIR)" && \
		"$(VCOVER)" report -directive -details "$(MERGED_UCDB)" \
			> "$(DIRECTIVE_TXT)" 2>/dev/null || \
		"$(VCOVER)" report -directive "$(MERGED_UCDB)" \
			> "$(DIRECTIVE_TXT)" || { \
			echo "ERROR: this Questa rejects 'vcover report -directive'."; \
			echo "       Run 'vcover report -help' and use the switch it lists."; \
			exit 1; \
		}
	@cd "$(MAKEFILE_DIR)" && \
		for report_file in "$(ASSERT_TXT)" "$(DIRECTIVE_TXT)"; do \
			echo ""; \
			echo "[ASSERT_REPORT] $$report_file ($$(wc -l < "$$report_file") lines)"; \
			grep -iE 'TOTAL .* COVERAGE' "$$report_file" || true; \
			awk -f "$(COV_SUMMARY_AWK)" "$$report_file"; \
		done
	@cd "$(MAKEFILE_DIR)" && \
		seen=0; total=0; missing=""; \
		for label in $$(grep -hoE \
			'[A-Z][A-Z0-9_]{2,}[[:space:]]*:[[:space:]]*(assert|cover)' \
			$(SVA_DIR)/*.sv | sed -E 's/[[:space:]]*:.*//' | sort -u); do \
			total=$$((total + 1)); \
			if grep -qw "$$label" "$(ASSERT_TXT)" "$(DIRECTIVE_TXT)"; then \
				seen=$$((seen + 1)); \
			else \
				missing="$$missing $$label"; \
			fi; \
		done; \
		echo ""; \
		echo "[ASSERT_REPORT] SVA labels found in the reports: $$seen/$$total"; \
		if [ "$$seen" -eq 0 ]; then \
			echo "  The merged UCDB holds no assertion or directive data."; \
			echo "  These counts are collected during the run, so the"; \
			echo "  regression has to be repeated with collection enabled"; \
			echo "  before the numbers mean anything."; \
		elif [ -n "$$missing" ]; then \
			echo "  Absent from both reports:$$missing"; \
		fi

#-----------------------------------------------------------------------------
# Cleanup
#-----------------------------------------------------------------------------
# modelsim.ini is part of the source tree (library mappings); keep it
clean:
	@echo "[CLEAN] Removing generated files under $(MAKEFILE_DIR)"
	@cd "$(MAKEFILE_DIR)" && rm -rf -- work "$(WORK64)" report
	@cd "$(MAKEFILE_DIR)" && rm -f -- \
		transcript vsim.wlf vsim_stacktrace.vstf *.vcd *.ucdb