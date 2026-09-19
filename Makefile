#=============================================================================
# Makefile: Synchronous FIFO RTL Verification & Regression Framework
# Compatible with macOS (Apple Silicon / Intel) and Linux (Ubuntu CI)
#=============================================================================

SHELL := /bin/bash
export PATH := /opt/homebrew/bin:/usr/local/bin:$(PATH)

# Python runner
PYTHON := python3

# Directories
RTL_DIR     := rtl
TB_DIR      := tb
TESTS_DIR   := tests
SIM_DIR     := sim
REPORTS_DIR := reports
LOGS_DIR    := $(REPORTS_DIR)/logs
WAVES_DIR   := waves
SCRIPTS_DIR := scripts

# Default parameters
TEST  ?= test_single_write_read
SEED  ?= 42
WAVE  ?= 0
BUG   ?=

.PHONY: all help dashboard gui compile test regression regression-bug demo-defect wave report clean

# Default target
all: dashboard

help:
	@echo "================================================================================"
	@echo "             SYNC FIFO VERIFICATION & REGRESSION FRAMEWORK"
	@echo "================================================================================"
	@echo "  PRIMARY INTERFACE (Recommended):"
	@echo "    make dashboard                Launch interactive Verification Studio Web UI"
	@echo "    ./launch_dashboard.sh         One-click shell launcher"
	@echo "    Launch_Dashboard.command      Double-click launcher in macOS Finder"
	@echo ""
	@echo "  Headless / Terminal Targets (Automation & CI):"
	@echo "    make compile                  Compile simulation binary (tb_top_clean.vvp)"
	@echo "    make test TEST=<name>         Run single test (e.g. TEST=test_burst_write_read)"
	@echo "                              Optional flags: WAVE=1 (dump VCD), SEED=<int>"
	@echo "    make regression               Execute all 10 tests and generate reports"
	@echo "    make regression-bug BUG=<def> Run regression with injected RTL defect"
	@echo "                              (e.g. BUG=BUG_INJECT_OVERFLOW)"
	@echo "    make demo-defect BUG=<def>    Execute validated 3-stage defect lifecycle demo"
	@echo "                              (Inject -> Verify Failure -> Restore -> Verify Pass)"
	@echo "    make wave TEST=<name>         Open test waveform in GTKWave"
	@echo "    make report                   Display latest regression report summary"
	@echo "    make clean                    Remove all build, log, report, and wave artifacts"
	@echo "================================================================================"

dashboard:
	@$(PYTHON) $(SCRIPTS_DIR)/dashboard_server.py

gui: dashboard


compile:
	@mkdir -p $(SIM_DIR) $(LOGS_DIR) $(WAVES_DIR)
	@$(PYTHON) $(SCRIPTS_DIR)/run_test.py --test $(TEST) --force-compile

test:
	@mkdir -p $(SIM_DIR) $(LOGS_DIR) $(WAVES_DIR)
	@if [ "$(WAVE)" = "1" ]; then \
		$(PYTHON) $(SCRIPTS_DIR)/run_test.py --test $(TEST) --seed $(SEED) --wave $(if $(BUG),--bug $(BUG),); \
	else \
		$(PYTHON) $(SCRIPTS_DIR)/run_test.py --test $(TEST) --seed $(SEED) $(if $(BUG),--bug $(BUG),); \
	fi

regression:
	@mkdir -p $(SIM_DIR) $(LOGS_DIR) $(WAVES_DIR)
	@$(PYTHON) $(SCRIPTS_DIR)/regression.py --seed $(SEED)

regression-bug:
	@if [ -z "$(BUG)" ]; then \
		echo "Error: Please specify BUG=<macro>. Example: make regression-bug BUG=BUG_INJECT_OVERFLOW"; \
		exit 1; \
	fi
	@mkdir -p $(SIM_DIR) $(LOGS_DIR) $(WAVES_DIR)
	@$(PYTHON) $(SCRIPTS_DIR)/regression.py --bug $(BUG) --seed $(SEED)

demo-defect:
	@if [ -z "$(BUG)" ]; then \
		echo "Error: Please specify BUG=<macro>. Example: make demo-defect BUG=BUG_INJECT_OVERFLOW"; \
		exit 1; \
	fi
	@$(PYTHON) $(SCRIPTS_DIR)/regression.py --demo-defect $(BUG) --seed $(SEED)

wave:
	@if [ ! -f "$(WAVES_DIR)/$(TEST).vcd" ]; then \
		echo "Waveform $(WAVES_DIR)/$(TEST).vcd not found. Generating now..."; \
		$(PYTHON) $(SCRIPTS_DIR)/run_test.py --test $(TEST) --wave; \
	fi
	@if command -v gtkwave >/dev/null 2>&1; then \
		gtkwave $(WAVES_DIR)/$(TEST).vcd & \
	elif [ -d "/Applications/gtkwave.app" ]; then \
		open -a gtkwave $(WAVES_DIR)/$(TEST).vcd; \
	else \
		echo "GTKWave executable not found in PATH or Applications."; \
		echo "To inspect waveforms on macOS, run: brew install --cask gtkwave"; \
		echo "Waveform file is available at: $(WAVES_DIR)/$(TEST).vcd"; \
	fi

report:
	@$(PYTHON) $(SCRIPTS_DIR)/generate_report.py

clean:
	@echo "Cleaning build artifacts, logs, waveforms, and reports..."
	@rm -rf $(SIM_DIR)/*.vvp
	@rm -rf $(LOGS_DIR)/*.log
	@rm -rf $(WAVES_DIR)/*.vcd
	@rm -rf $(REPORTS_DIR)/regression_summary.json
	@rm -rf $(REPORTS_DIR)/regression_summary.csv
	@rm -rf $(REPORTS_DIR)/regression_report.md
	@echo "Clean completed."
