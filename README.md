# Synchronous FIFO RTL Verification & Automated Regression Framework

A complete, production-grade, reproducible hardware verification and automated regression environment built for SystemVerilog digital design. 

This repository demonstrates the end-to-end verification lifecycle:
$$\text{RTL} \longrightarrow \text{Testbench} \longrightarrow \text{Stimulus} \longrightarrow \text{DUT Execution} \longrightarrow \text{Monitoring} \longrightarrow \text{Checking} \longrightarrow \text{Assertions} \longrightarrow \text{Simulation} \longrightarrow \text{Regression} \longrightarrow \text{Reporting} \longrightarrow \text{CI}$$

---

## Table of Contents
1. [Project Overview](#1-project-overview)
2. [Verification Architecture](#2-verification-architecture)
3. [Repository Structure](#3-repository-structure)
4. [Technology Stack & Justification](#4-technology-stack--justification)
5. [Prerequisites](#5-prerequisites)
6. [Installation & Setup](#6-installation--setup)
7. [Running an Individual Test](#7-running-an-individual-test)
8. [Running the Full Automated Regression Suite](#8-running-the-full-automated-regression-suite)
9. [Waveform Inspection with GTKWave](#9-waveform-inspection-with-gtkwave)
10. [Understanding Reports & Metrics](#10-understanding-reports--metrics)
11. [Defect-Injection Verification (Mandatory Demo)](#11-defect-injection-verification-mandatory-demo)
12. [Continuous Integration (GitHub Actions)](#12-continuous-integration-github-actions)
13. [Verification Methodology](#13-verification-methodology)
14. [Limitations](#14-limitations)
15. [Future Extensions](#15-future-extensions)

---

## 1. Project Overview

This project provides an industry-realistic verification environment for a **Parameterized Synchronous FIFO (`sync_fifo.sv`) with Status Protection, Watermark Thresholds, and Simultaneous Read/Write Capability**.

### Primary Verification Objectives
- **Data Integrity**: Guarantee that every word written to the FIFO is read out in exact first-in, first-out order without bit flips, drops, or duplications.
- **Protocol Safety**: Ensure that illegal operations (writing when full, reading when empty) are safely blocked, error flags (`overflow`, `underflow`) are raised, and stored memory is protected.
- **Boundary & Watermark Checking**: Verify exact single-cycle assertion and deassertion of `empty`, `full`, `almost_empty`, and `almost_full` status flags.
- **Concurrent Transactions**: Validate steady-state occupancy during continuous simultaneous write and read requests across empty, partial, and full conditions.
- **Automated Regression**: Execute a 10-test regression suite orchestrated by a robust Python 3 engine that outputs machine-readable JSON/CSV metrics and human-readable Markdown summaries.
- **Defect Detection**: Prove through compile-time macro injections that the scoreboard and SystemVerilog Assertions (SVA) deterministically detect RTL bugs.

---

## 2. Verification Architecture

The testbench strictly separates stimulus generation, signal observation, and independent checking:

```
+-----------------------------------------------------------------------------------------+
|                                    TESTBENCH TOP (tb_top.sv)                            |
|                                                                                         |
|  100MHz Clock Generator | Reset Controller | Plusarg Dispatcher (+TESTNAME, +SEED, +WAVE)
|  -------------------------------------------------------------------------------------  |
|  SystemVerilog Safety Assertions (fifo_assertions.sv)                                   |
|  -------------------------------------------------------------------------------------  |
|    +-------------------+       +--------------------+       +-----------------------+   |
|    |   Test Sequences  | ----> |    FIFO Driver     | ----> |       DUT             |   |
|    |   (tests/*.sv)    |       |  (fifo_driver.sv)  |       |   (sync_fifo.sv)      |   |
|    +-------------------+       +--------------------+       +-----------------------+   |
|                                          |                              |               |
|                                          v (wr_mon)                     v (rd_mon)      |
|                                 +-----------------------------------------------+       |
|                                 |                 FIFO Monitor                  |       |
|                                 |              (fifo_monitor.sv)                |       |
|                                 +-----------------------------------------------+       |
|                                          |                              |               |
|                                          v (tx)                         v (tx)          |
|                                 +-----------------------------------------------+       |
|                                 |          Independent FIFO Scoreboard          |       |
|                                 |             (fifo_scoreboard.sv)              |       |
|                                 |  - Golden Reference Queue Model               |       |
|                                 |  - Occupancy & Flag State Tracker             |       |
|                                 |  - Cycle-by-cycle Bitwise Comparator          |       |
|                                 |  - End-of-test Drain Accounting               |       |
|                                 +-----------------------------------------------+       |
+-----------------------------------------------------------------------------------------+
                                           ^
                                           |
                       +---------------------------------------+
                       |       Python 3 Regression Engine      |
                       |  (scripts/run_test.py, regression.py) |
                       +---------------------------------------+
                                           ^
                                           |
                       +---------------------------------------+
                       |       Makefile & GitHub Actions CI    |
                       +---------------------------------------+
```

### Component Roles
1. **DUT (`rtl/sync_fifo.sv`)**: Dual-port synchronous FIFO with circular write/read pointers, fill counter, threshold comparators, and error flag generation.
2. **Driver (`tb/fifo_driver.sv`)**: Active stimulus driver executing cycle-accurate reset, single writes, single reads, continuous back-to-back bursts, and simultaneous transactions.
3. **Monitor (`tb/fifo_monitor.sv`)**: Passive bus monitor observing transactions at clock boundaries and forwarding transactions to the scoreboard.
4. **Scoreboard (`tb/fifo_scoreboard.sv`)**: Independent reference model containing a golden reference queue (`logic [DATA_WIDTH-1:0] ref_queue[$]`). Computes expected occupancy and flags independently from the DUT's internal pointers.
5. **Assertions (`tb/fifo_assertions.sv`)**: SVA immediate and procedural assertions evaluating safety invariants (e.g. mutual exclusion of `full` and `empty`, count bounds, protocol error flag timing).
6. **Top Harness (`tb/tb_top.sv`)**: Wires all modules, generates a 100MHz clock, dispatches tests based on plusargs (`+TESTNAME=`), arms a 50,000-cycle watchdog timer, and terminates with standard exit codes via `$finish(0)` on pass or `$fatal(1)` on error.

---

## 3. Repository Structure

```
.
├── rtl/
│   └── sync_fifo.sv             # Parameterized Synchronous FIFO RTL (with defect injection hooks)
├── tb/
│   ├── fifo_pkg.sv              # Package: Transaction types, enums, logging utilities
│   ├── fifo_driver.sv           # Active stimulus driver (cycle-accurate pin driving)
│   ├── fifo_monitor.sv          # Passive transaction monitor
│   ├── fifo_scoreboard.sv       # Independent golden reference model & data comparator
│   ├── fifo_assertions.sv      # SystemVerilog safety assertions (protocol & flags)
│   └── tb_top.sv                # Top-level harness, plusarg dispatcher, watchdog timer
├── tests/
│   ├── test_base.sv             # Base test helpers and formatted banners
│   ├── test_reset.sv            # Test 1: Reset behavior, illegal ops during reset, recovery
│   ├── test_single_write_read.sv# Test 2: Single word write followed by single read
│   ├── test_burst_write_read.sv # Test 3: Back-to-back burst write followed by burst read
│   ├── test_fifo_full.sv        # Test 4: Fill to capacity (DEPTH=16), check full flag & recovery
│   ├── test_fifo_empty.sv       # Test 5: Drain sequence and empty flag timing/stability
│   ├── test_simultaneous_rw.sv  # Test 6: Concurrent read and write at partial & full fill
│   ├── test_overflow.sv         # Test 7: Illegal write on full, overflow flag & data protection
│   ├── test_underflow.sv        # Test 8: Illegal read on empty, underflow flag & recovery
│   ├── test_almost_flags.sv     # Test 9: Watermark threshold crossing verification
│   └── test_random_traffic.sv   # Test 10: Constrained random stimulus with seed control
├── scripts/
│   ├── run_test.py              # Single test runner, log capture, timeout, exit codes
│   ├── regression.py            # Regression orchestrator, JSON/CSV/Markdown reports
│   └── generate_report.py       # Standalone report generator from simulation logs
├── docs/
│   ├── dut_specification.md     # Hardware specification for sync_fifo
│   ├── verification_plan.md     # Test matrix, SVA taxonomy, sign-off criteria
│   ├── architecture.md          # Architecture and execution methodology
│   └── troubleshooting.md       # Diagnostic guide for local simulation & tooling
├── sim/                         # Simulation build artifacts (.vvp binaries)
├── reports/                     # Machine-readable summaries and human-readable reports
│   └── logs/                    # Individual test run execution logs
├── waves/                       # Value Change Dump (.vcd) waveform files for GTKWave
├── .github/
│   └── workflows/
│       └── regression.yml       # Continuous Integration workflow (Ubuntu + iverilog)
├── Makefile                     # Top-level command orchestration
├── requirements.txt             # Python environment specification (zero external deps)
├── .gitignore                   # Version control ignore rules
└── README.md                    # This documentation
```

---

## 4. Technology Stack & Justification

| Tool / Technology | Version / Requirement | Role | Engineering Rationale |
| :--- | :--- | :--- | :--- |
| **SystemVerilog** | IEEE 1800-2012 (`-g2012`) | RTL & Testbench | Industry-standard language for digital design and hardware verification. |
| **Icarus Verilog (`iverilog`)** | `13.0` (stable) | Simulator Compiler | High-performance, open-source Verilog/SystemVerilog compiler available on macOS and Linux. |
| **Icarus Runtime (`vvp`)** | `13.0` (stable) | Simulation Engine | Executes compiled `.vvp` simulation binaries with runtime plusarg support. |
| **Python 3** | $\ge 3.8$ (Standard Library) | Automation & Regression | Cross-platform automation without external dependencies (`argparse`, `subprocess`, `json`, `csv`, `pathlib`). |
| **GTKWave** | Any modern version | Waveform Viewer | Standard open-source waveform inspection tool for `.vcd` files. |
| **Make** | GNU Make $\ge 3.81$ | Command Orchestration | Universal interface for reproducible compilation and test runs. |
| **GitHub Actions** | Ubuntu Latest | Continuous Integration | Verifies pull requests and commits in a clean Linux container. |

---

## 5. Prerequisites

### macOS (Apple Silicon or Intel)
1. **Homebrew**: Package manager for installing EDA tools.
2. **Icarus Verilog**:
   ```bash
   brew install icarus-verilog
   ```
3. **Python 3**: Standard macOS Python (`/usr/bin/python3`) or Homebrew Python.
4. **GTKWave** (Optional, for waveform inspection):
   ```bash
   brew install --cask gtkwave
   ```

### Linux (Ubuntu / Debian)
```bash
sudo apt-get update && sudo apt-get install -y iverilog python3 make
```

---

## 6. Installation & Setup

1. **Clone the repository**:
   ```bash
   git clone https://github.com/<your-username>/rtl-verification-regression.git
   cd rtl-verification-regression
   ```

2. **Verify toolchain availability**:
   ```bash
   iverilog -V | head -n 2
   vvp -V | head -n 2
   python3 --version
   ```
   *(On macOS Apple Silicon, ensure `/opt/homebrew/bin` is in your `PATH`)*.

3. **Check available Make targets**:
   ```bash
   make help
   ```

---

## 7. Running an Individual Test

Run any of the 10 verification test cases using `make test` or `python3 scripts/run_test.py`:

```bash
# Run test_burst_write_read
make test TEST=test_burst_write_read

# Run with waveform generation enabled (VCD output saved to waves/)
make test TEST=test_burst_write_read WAVE=1

# Run with custom pseudo-random seed
make test TEST=test_random_traffic SEED=12345
```

### Direct Python Invocation
```bash
python3 scripts/run_test.py --test test_single_write_read --wave
```

### Expected Output
```text
[RUN] Executing test_burst_write_read (Seed: 42, Wave: False)...
[PASS] test_burst_write_read (0.008s) - Test PASSED
[LOG] Log saved to /Users/.../reports/logs/test_burst_write_read.log
```

---

## 8. Running the Full Automated Regression Suite

Execute all 10 verification test cases in sequence, aggregate results, and generate reports:

```bash
make regression
```
Or directly:
```bash
python3 scripts/regression.py
```

### Terminal Dashboard Output
```text
[REGRESSION START] Discovered 10 tests for regression suite.
[COMPILATION] Compiling RTL and testbench suite...
[COMPILATION OK] Simulation binary ready: sim/tb_top_clean.vvp
  [1/10] Running test_almost_flags... PASS (0.009s)
  [2/10] Running test_burst_write_read... PASS (0.008s)
  [3/10] Running test_fifo_empty... PASS (0.008s)
  [4/10] Running test_fifo_full... PASS (0.009s)
  [5/10] Running test_overflow... PASS (0.009s)
  [6/10] Running test_random_traffic... PASS (0.011s)
  [7/10] Running test_reset... PASS (0.008s)
  [8/10] Running test_simultaneous_rw... PASS (0.009s)
  [9/10] Running test_single_write_read... PASS (0.008s)
  [10/10] Running test_underflow... PASS (0.008s)

===============================================================================================
                 SYNCHRONOUS FIFO REGRESSION EXECUTION DASHBOARD
===============================================================================================
Test Identifier              | Status   | Time (s)   | Mismatches | Details                  
-----------------------------------------------------------------------------------------------
test_almost_flags            | PASS     | 0.009      | 0          | PASSED                   
test_burst_write_read        | PASS     | 0.008      | 0          | PASSED                   
test_fifo_empty              | PASS     | 0.008      | 0          | PASSED                   
test_fifo_full               | PASS     | 0.009      | 0          | PASSED                   
test_overflow                | PASS     | 0.009      | 0          | PASSED                   
test_random_traffic          | PASS     | 0.011      | 0          | PASSED                   
test_reset                   | PASS     | 0.008      | 0          | PASSED                   
test_simultaneous_rw         | PASS     | 0.009      | 0          | PASSED                   
test_single_write_read       | PASS     | 0.008      | 0          | PASSED                   
test_underflow               | PASS     | 0.008      | 0          | PASSED                   
-----------------------------------------------------------------------------------------------
Total Tests: 10  |  Passed: 10  |  Failed: 0  |  Pass Rate: 100.0%  |  Duration: 0.091s
Overall Regression Status: PASSED
===============================================================================================

[REPORTS] JSON Summary : reports/regression_summary.json
[REPORTS] CSV Summary  : reports/regression_summary.csv
[REPORTS] Markdown     : reports/regression_report.md
```

---

## 9. Waveform Inspection with GTKWave

### 1. Generating Waveforms
Waveforms are dumped in standard Value Change Dump (`.vcd`) format when `+DUMP_WAVE=1` is passed or `WAVE=1` is specified:
```bash
make test TEST=test_simultaneous_rw WAVE=1
```
The file is generated at: `waves/test_simultaneous_rw.vcd`.

### 2. Opening in GTKWave
```bash
make wave TEST=test_simultaneous_rw
```
Or directly:
```bash
gtkwave waves/test_simultaneous_rw.vcd
```
*(On macOS, you can also use `open -a gtkwave waves/test_simultaneous_rw.vcd`)*.

### 3. Recommended Signals to Inspect
Add the following signals from `tb_top.dut` to the waveform viewer:
- **System**: `clk`, `rst_n`
- **Write Channel**: `wr_en`, `wr_data[7:0]`, `full`, `overflow`
- **Read Channel**: `rd_en`, `rd_data[7:0]`, `empty`, `underflow`
- **State & Watermarks**: `count[4:0]`, `almost_full`, `almost_empty`
- **Internal Storage**: `wr_ptr[3:0]`, `rd_ptr[3:0]`

---

## 10. Understanding Reports & Metrics

Each regression run automatically generates three report artifacts:

### 1. Machine-Readable JSON (`reports/regression_summary.json`)
Contains complete metadata, runtime configuration, per-test timing, and error classification:
```json
{
  "timestamp": "2026-09-19T00:39:01.058925+00:00",
  "configuration": {
    "simulator": "Icarus Verilog 13.0 (vvp)",
    "dut": "sync_fifo",
    "seed": 42,
    "wave_dump": false,
    "bug_macro": null
  },
  "summary": {
    "total_tests": 10,
    "passed": 10,
    "failed": 0,
    "pass_rate": "100.0%",
    "total_duration_sec": 0.091,
    "overall_status": "PASSED"
  },
  "test_results": [
    {
      "test_name": "test_burst_write_read",
      "passed": true,
      "status": "PASS",
      "duration_sec": 0.008,
      "data_mismatches": 0,
      "state_errors": 0,
      "assertion_failures": 0,
      "exit_code": 0,
      "details": "PASSED",
      "log_path": "reports/logs/test_burst_write_read.log"
    }
  ]
}
```

### 2. Machine-Readable CSV (`reports/regression_summary.csv`)
Easily ingestible into CI dashboards, spreadsheets, or automated parsing pipelines:
```csv
Test Name,Status,Duration (s),Data Mismatches,State Errors,Assertion Failures,Details,Log File
test_almost_flags,PASS,0.0090,0,0,0,PASSED,reports/logs/test_almost_flags.log
test_burst_write_read,PASS,0.0080,0,0,0,PASSED,reports/logs/test_burst_write_read.log
...
```

### 3. Human-Readable Markdown (`reports/regression_report.md`)
Formatted for GitHub PR comments or documentation archiving, displaying summary metrics and tabular test breakdowns.

---

## 11. Defect-Injection Verification (Mandatory Demo)

A verification framework is only as credible as its ability to catch genuine design defects. This environment provides built-in compile-time defect injection macros in `rtl/sync_fifo.sv`:

| Defect Injection Macro | Injected Bug Mechanism | Expected Test Failures |
| :--- | :--- | :--- |
| `BUG_INJECT_OVERFLOW` | Disables overflow protection: allows writes to proceed when full, corrupting memory array. | `test_overflow` (5 data mismatches) & `test_random_traffic` (43 mismatches). |
| `BUG_INJECT_UNDERFLOW_FLAG` | Suppresses `underflow` error flag generation on illegal reads when empty. | `test_underflow` (5 assertion failures). |
| `BUG_INJECT_COUNT_SIMULTANEOUS` | Miscalculates occupancy during simultaneous read/write when full (increments past `DEPTH`). | `test_simultaneous_rw` (SVA `A_COUNT_LIMIT` violation). |
| `BUG_INJECT_ALMOST_FULL` | Uses `<` instead of `>=` for watermark calculation. | `test_almost_flags` (watermark state mismatches). |

### Reproducible Bug-Injection Demonstration

#### Step 1: Run Clean Regression (All 10 Pass)
```bash
make regression
```
Result: **`10 Passed, 0 Failed, Exit Code 0`**.

#### Step 2: Inject Overflow Defect (`BUG_INJECT_OVERFLOW`)
```bash
make regression-bug BUG=BUG_INJECT_OVERFLOW
```
Result: **`8 Passed, 2 Failed, Exit Code 1`**.
```text
  [5/10] Running test_overflow... FAIL (0.014s)
  [6/10] Running test_random_traffic... FAIL (0.022s)

Test Identifier        | Status | Mismatches | Details
---------------------------------------------------------------------
test_overflow          | FAIL   | 5          | 5 data mismatch(es)
test_random_traffic    | FAIL   | 43         | 43 data mismatch(es)
---------------------------------------------------------------------
Overall Regression Status: FAILED
```

#### Step 3: Inject Underflow Flag Defect (`BUG_INJECT_UNDERFLOW_FLAG`)
```bash
make regression-bug BUG=BUG_INJECT_UNDERFLOW_FLAG
```
Result: **`9 Passed, 1 Failed, Exit Code 1`**.
```text
  [10/10] Running test_underflow... FAIL (0.008s)

Test Identifier        | Status | Mismatches | Details
---------------------------------------------------------------------
test_underflow         | FAIL   | 0          | 5 assertion failure(s)
---------------------------------------------------------------------
Overall Regression Status: FAILED
```

#### Step 4: Restore Clean Baseline
```bash
make regression
```
Result: **`10 Passed, 0 Failed, Exit Code 0`**.

---

## 12. Continuous Integration (GitHub Actions)

The repository includes a production-ready CI workflow located at [`.github/workflows/regression.yml`](.github/workflows/regression.yml).

### CI Workflow Stages
1. **Runner Setup**: Spawns an `ubuntu-latest` virtual environment with Python 3.11.
2. **Toolchain Installation**: Installs `iverilog` via `apt-get` and performs version checks.
3. **Clean Regression**: Executes `make regression` and verifies that all 10 tests pass.
4. **Defect-Injection Validation**:
   - Executes `python3 scripts/regression.py --bug BUG_INJECT_OVERFLOW`.
   - Confirms that the runner returns a non-zero exit code (defects are caught).
   - Executes `python3 scripts/regression.py --bug BUG_INJECT_UNDERFLOW_FLAG`.
   - Confirms that assertion failures correctly fail the run.
5. **Artifact Publishing**: Uploads `reports/regression_summary.json`, `reports/regression_summary.csv`, `reports/regression_report.md`, and all individual test logs (`reports/logs/*.log`) as downloadable workflow artifacts.

---

## 13. Verification Methodology

### 1. Independent Golden Reference Model
To avoid mirror-imaging bugs present in the RTL, the scoreboard maintains a dedicated SystemVerilog queue (`logic [DATA_WIDTH-1:0] ref_queue[$]`).
- When the write monitor observes `wr_en && (!full || rd_en)`, the data is pushed to the golden queue.
- When the read monitor observes `rd_en && !empty`, the golden queue pops the front word.
- The actual `rd_data` from the DUT is compared bit-for-bit against the popped reference word.
- Mismatches immediately trigger an error log with expected vs actual values, simulation time, and queue size.

### 2. SystemVerilog Assertions (SVA)
Assertions run continuously on every clock edge:
- **`A_RESET_STATE`**: Confirms that when `rst_n == 0`, `empty=1`, `full=0`, `count=0`, `overflow=0`, `underflow=0`.
- **`A_MUTEX_FULL_EMPTY`**: Invariant ensuring `!(full && empty)` holds unconditionally.
- **`A_COUNT_LIMIT`**: Bounds check ensuring `count <= DEPTH`.
- **`A_OVERFLOW_PROTOCOL`**: Asserts that an illegal write attempt while full without concurrent read triggers `overflow`.
- **`A_UNDERFLOW_PROTOCOL`**: Asserts that an illegal read attempt while empty triggers `underflow`.
- **`A_ALMOST_FULL_RULE`**: Verifies that `almost_full` asserts if and only if `count >= (DEPTH - ALMOST_FULL_THRESH)`.
- **`A_ALMOST_EMPTY_RULE`**: Verifies that `almost_empty` asserts if and only if `count <= ALMOST_EMPTY_THRESH && !empty`.

---

## 14. Limitations

This project is intentionally designed with a lightweight, zero-dependency stack. It explicitly does **NOT** include:
- **Universal Verification Methodology (UVM)**: UVM requires proprietary EDA simulators (VCS, Questa, Xcelium) or heavy wrappers and is omitted in favor of lightweight, native SystemVerilog.
- **Asynchronous Clock Domain Crossing (CDC)**: The DUT is a synchronous FIFO. Multi-clock Gray-code synchronization, 2-flop synchronizers, and formal CDC analysis are outside the scope of this single-clock design.
- **Functional Coverage Groups (`covergroup`)**: Open-source Icarus Verilog does not currently support SystemVerilog `covergroup` and `coverpoint` constructs. Coverage is tracked via functional test matrix mapping and scoreboard checks.

---

## 15. Future Extensions

1. **Verilator Integration**: Adding Verilator linting and C++ testbench co-simulation for multi-million-cycle stress testing.
2. **Asynchronous Dual-Clock FIFO**: Implementing Gray-code pointer CDC synchronization with Questa/ModelSim SVA concurrent sequences.
3. **AXI4-Stream Protocol Adapter**: Wrapping the FIFO with standard `s_axis_tready/tvalid` and `m_axis_tvalid/tready` handshaking.
4. **HTML Coverage Dashboard**: Extending `scripts/generate_report.py` to produce interactive HTML reports with collapsible logs.
