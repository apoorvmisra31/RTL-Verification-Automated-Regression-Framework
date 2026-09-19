# RTL Verification & Automated Regression Studio

A complete, locally reproducible SystemVerilog verification environment and automated regression framework for digital hardware design, validated using the open-source **Icarus Verilog** toolchain.

This framework integrates the entire verification lifecycle into a **dashboard-first control surface**, enabling verification engineers to discover tests, trigger simulations, monitor real-time execution, inspect in-browser digital waveforms, and run controlled defect-injection experiments **without requiring manual terminal commands**.

$$\text{Interactive Dashboard} \longleftrightarrow \text{REST API Engine} \longleftrightarrow \text{Regression Orchestrator} \longleftrightarrow \text{Icarus Verilog} \longleftrightarrow \text{DUT / SVA / Scoreboard}$$

---

## Table of Contents
1. [Project Overview & Objectives](#1-project-overview--objectives)
2. [Verification Architecture & Data Path](#2-verification-architecture--data-path)
3. [Technology Stack & Justification](#3-technology-stack--justification)
4. [Prerequisites](#4-prerequisites)
5. [One-Click Dashboard Launch](#5-one-click-dashboard-launch)
6. [Dashboard Control Surface Guide](#6-dashboard-control-surface-guide)
   - [Overview & KPI Summary](#panel-1-overview--kpi-summary)
   - [Test Catalog](#panel-2-test-catalog)
   - [Regression Suite & Live Streaming](#panel-3-regression-suite--live-streaming)
   - [Waveform Debugger (In-Browser & GTKWave)](#panel-4-waveform-debugger)
   - [Log Inspector](#panel-5-log-inspector)
   - [Reports & Export](#panel-6-reports--export)
   - [Defect-Injection Verification Lab](#panel-7-defect-injection-verification-lab)
   - [System Health & Environment Diagnostics](#panel-8-system-health--diagnostics)
7. [SystemVerilog Assertions (SVA) Implementation](#7-systemverilog-assertions-sva-implementation)
8. [Defect-Injection Demonstration Workflow](#8-defect-injection-demonstration-workflow)
9. [Continuous Integration (GitHub Actions)](#9-continuous-integration-github-actions)
10. [Repository File Inventory](#10-repository-file-inventory)
11. [Developer & CI CLI Reference](#11-developer--ci-cli-reference)
12. [Troubleshooting Guide](#12-troubleshooting-guide)
13. [Process Safety & Security Boundaries](#13-process-safety--security-boundaries)
14. [Toolchain Limitations & Engineering Honesty](#14-toolchain-limitations--engineering-honesty)

---

## 1. Project Overview & Objectives

Traditional semiconductor verification frameworks rely heavily on terminal scripts, fragmented log grep commands, and external viewers. This project integrates the entire verification lifecycle into a unified, locally hosted **Verification Studio**:

- **Target DUT**: Parameterized Synchronous FIFO (`sync_fifo.sv`) with 8-bit data width, 16-word depth, watermark flags (`almost_full`, `almost_empty`), single-cycle pulse protocol error flags (`overflow`, `underflow`), and concurrent read/write support.
- **Verification Harness**: Modular SystemVerilog testbench featuring an active stimulus driver, cycle-accurate bus monitor, independent golden reference queue scoreboard, and SystemVerilog immediate assertions.
- **Primary Control Surface**: A responsive web studio operating locally on macOS and Linux that provides complete operational parity with headless workflows.

### Verified Capabilities
- **Zero-Terminal User Workflow**: All operational actions—from test launch to waveform inspection—are accessible via UI buttons.
- **Real-Time Job Streaming**: Live execution tracking with step progress and Server-Sent Events (SSE) terminal logs.
- **In-Browser Timing Diagrams**: Interactive HTML5 Canvas digital waveform viewer with zoom, pan, and cursor time-measurement.
- **Native GTKWave Bridge**: One-click local launch of GTKWave for deep multi-hierarchy debug sessions.
- **Deterministic Defect Lab**: A 3-stage controlled hardware defect injection experiment verifying that the verification harness deterministically catches RTL bugs and restores golden clean code.

---

## 2. Verification Architecture & Data Path

To ensure unbiased verification, the testbench enforces strict separation of concerns across active and passive components:

```
+-----------------------------------------------------------------------------------------+
|                                    TESTBENCH TOP (tb_top.sv)                            |
|                                                                                         |
|  100MHz Clock Generator | Reset Controller | Plusarg Dispatcher (+TESTNAME, +SEED, +WAVE)
|  -------------------------------------------------------------------------------------  |
|  SystemVerilog Immediate Assertions (fifo_assertions.sv)                                |
|  -------------------------------------------------------------------------------------  |
|    +-------------------+       +--------------------+       +-----------------------+   |
|    |   Test Sequences  | ----> |    FIFO Driver     | ----> |       DUT             |   |
|    |   (tests/*.sv)    |       |  (fifo_driver.sv)  |       |   (sync_fifo.sv)      |   |
|    +-------------------+       +--------------------+       +-----------------------+   |
|                                                                         |               |
|                                                                         v (interface)   |
|                                 +-----------------------------------------------+       |
|                                 |                 FIFO Monitor                  |       |
|                                 |              (fifo_monitor.sv)                |       |
|                                 |  - Passively samples bus on posedge clk       |       |
|                                 |  - Qualifies accepted writes & valid reads    |       |
|                                 |  - Forwards transactions to scoreboard        |       |
|                                 +-----------------------------------------------+       |
|                                                         |                               |
|                                                         v (monitored tx & flags)        |
|                                 +-----------------------------------------------+       |
|                                 |          Independent FIFO Scoreboard          |       |
|                                 |             (fifo_scoreboard.sv)              |       |
|                                 |  - Golden Reference Queue Model               |       |
|                                 |  - Occupancy & Flag State Tracker             |       |
|                                 |  - Cycle-by-cycle Bitwise Comparator          |       |
|                                 |  - Error Accounting (Mismatches, Flag Errors) |       |
|                                 +-----------------------------------------------+       |
+-----------------------------------------------------------------------------------------+
```

### Component Roles
1. **Driver (`tb/fifo_driver.sv`)**: Active stimulus agent driving signals (`rst_n`, `wr_en`, `wr_data`, `rd_en`) synchronous to `@(negedge clk)` so that inputs are stable ahead of setup times on rising clock edges. Has zero knowledge of expected scoreboard data.
2. **DUT (`rtl/sync_fifo.sv`)**: Parameterized Synchronous FIFO with circular write/read pointers, fill counter, threshold comparators, and single-cycle pulse error flags (`overflow`, `underflow`).
3. **Monitor (`tb/fifo_monitor.sv`)**: Passive observer sampling interface signals on `@(posedge clk)`. Pre-samples boundary flags to qualify accepted writes and valid reads, then forwards monitored transactions and observed status flags directly to `tb_top.scoreboard`.
4. **Scoreboard (`tb/fifo_scoreboard.sv`)**: Independent reference model maintaining an unbounded golden queue (`ref_queue[$]`). Computes expected occupancy and flags independently from the DUT's internal pointers and compares each read data word bit-for-bit against the golden model.
5. **Assertions (`tb/fifo_assertions.sv`)**: SystemVerilog Immediate Assertions evaluated at clock boundaries, enforcing reset state invariants, full/empty mutual exclusion, count bounds, and protocol error pulse timing.
6. **Top Harness (`tb/tb_top.sv`)**: Wires all blocks, dispatches tests based on plusargs, enforces a 50,000-cycle hardware watchdog timer, and terminates with standard exit codes via `$finish(0)` on pass or `$fatal(1)` on any detected verification error.

---

## 3. Technology Stack & Justification

| Layer | Technology | Version | Architectural Rationale |
| :--- | :--- | :--- | :--- |
| **Primary UI** | Vanilla HTML5 / CSS3 / ES6 | Modern Browser | Maximum responsiveness, zero build steps (`npm`/`node` free), dark EDA studio aesthetic, instant loading. |
| **Waveform Canvas** | HTML5 2D Canvas API | Native Browser | Zero-dependency digital timing diagram rendering with pan, zoom, signal labels, and timestamp cursors. |
| **Application Server** | Python `http.server.ThreadingHTTPServer` | Python 3.9+ | Built strictly on the Python Standard Library. Zero `pip` dependencies; runs instantly in clean environments. |
| **Process Control** | Python `subprocess` & `threading` | Python 3 Standard | Thread-safe background execution, asynchronous SSE log streaming, and deterministic process isolation. |
| **HDL Simulator** | Icarus Verilog (`iverilog` / `vvp`) | v13.0+ | IEEE 1364-2005 / SystemVerilog 2012 open-source standard simulator with VCD dumping and plusarg support. |
| **Desktop Waveform Viewer** | GTKWave | v3.3+ | Full-featured digital waveform inspection tool for deep hierarchy debugging, launched via dashboard button. |
| **Continuous Integration** | GitHub Actions | Ubuntu 22.04 | Automated regression validation on push and pull requests with build artifact retention. |

---

## 4. Prerequisites

The framework runs out-of-the-box on **macOS (Apple Silicon & Intel)** and **Linux (Ubuntu/Debian)**:

1. **Python 3.9+** (Standard library only; zero pip installations needed).
2. **Icarus Verilog (`iverilog` and `vvp`)**:
   - **macOS**: `brew install icarus-verilog`
   - **Ubuntu/Debian**: `sudo apt-get install iverilog`
3. *(Optional)* **GTKWave**:
   - **macOS**: `brew install --cask gtkwave`
   - **Ubuntu/Debian**: `sudo apt-get install gtkwave`

---

## 5. One-Click Dashboard Launch

To launch the Verification Studio, use any of the three provided launcher methods:

### Method A: macOS Finder Double-Click (Zero Terminal)
In macOS Finder, locate the project folder and double-click:
```text
Launch_Dashboard.command
```
This automatically starts the local dashboard server and opens `http://127.0.0.1:8080` in your default browser.

### Method B: Executable Script
```bash
./launch_dashboard.sh
```

### Method C: Standard Make Target
```bash
make dashboard
```

> [!NOTE]
> The server automatically selects port `8080` (or the next available port if `8080` is in use) and binds strictly to `127.0.0.1` for local safety.

---

## 6. Dashboard Control Surface Guide

The dashboard is structured into 8 intuitive navigation panels:

### Panel 1: Overview & KPI Summary
- **System Health Indicator**: Displays simulator availability (`Icarus Verilog 13.0`), runtime engine status, and project root path.
- **KPI Metrics**: Real-time counters showing total tests (10), latest pass rate (100%), duration, and hardware parameter summary (Width: 8, Depth: 16).
- **Quick Action Bar**: One-click triggers for **Run Full Regression**, **Run Defect Demo**, and **Inspect Waveforms**.
- **Recent Results Table**: Live breakdown of the most recent execution with test-by-test status indicators.

### Panel 2: Test Catalog
- Lists all 10 verification scenarios across 5 engineering categories:
  - **Directed / Functional**: `test_single_write_read`, `test_burst_write_read`
  - **Boundary / Capacity**: `test_fifo_full`, `test_fifo_empty`, `test_almost_flags`
  - **Corner Case**: `test_simultaneous_rw`
  - **Robustness / Protocol**: `test_overflow`, `test_underflow`
  - **Stress & Reset**: `test_reset`, `test_random_traffic`
- Each card displays verification purpose, stimulus description, and an interactive **Configure & Run** modal allowing custom random seeds, waveform dumping, and compile-time defect defines.

### Panel 3: Regression Suite & Live Streaming
- **Batch Regression Launcher**: Executes the complete 10-test suite sequentially.
- **Live Progress Bar**: Displays real-time test count, percentage completion, and current active simulation.
- **Streaming Terminal Window**: Real-time Server-Sent Events (SSE) output showing simulation logs, scoreboard checkpoints, and SVA evaluations.
- **Results Matrix**: Granular metrics for each test, including duration, data mismatches, state errors, and SVA failure count.

### Panel 4: Waveform Debugger
- **In-Browser Digital Logic Canvas**: Select any completed test with waveform dumping enabled to render interactive digital traces for `clk`, `rst_n`, `wr_en`, `rd_en`, `wr_data`, `rd_data`, `full`, `empty`, `almost_full`, `almost_empty`, `overflow`, `underflow`, `count`.
- **Interactive Controls**: Zoom In (+), Zoom Out (-), Reset View, and click anywhere to place a timestamp measurement cursor.
- **Native GTKWave Launcher**: Click **Launch GTKWave** to launch the native desktop viewer with the generated `.vcd` file.

### Panel 5: Log Inspector
- Searchable, syntax-highlighted simulation logs for every test case.
- Filter by test name or search for specific substrings (e.g. `SCOREBOARD`, `ASSERTION`, `MISMATCH`).
- Download individual `.log` files directly to your workstation.

### Panel 6: Reports & Export
- **Live Markdown Report**: Formatted regression report with executive summary, configuration parameters, and detailed test tables.
- **Export Raw Data**: Instant download links for `regression_summary.json` and `regression_summary.csv` for downstream CI/CD ingestion or spreadsheet analysis.

### Panel 7: Defect-Injection Verification Lab
- Interactive proof of verification harness effectiveness.
- Select from 5 real-world hardware defect macros and execute the guided 3-stage validation cycle (Inject -> Catch -> Restore -> Pass).

### Panel 8: System Health & Diagnostics
- Toolchain validation showing detected paths for `iverilog`, `vvp`, `gtkwave`, and Python runtime.
- One-click workspace cache cleaner to purge stale `.vvp`, `.log`, and `.vcd` files.

---

## 7. SystemVerilog Assertions (SVA) Implementation

All hardware assertions are implemented in `tb/fifo_assertions.sv` using standard SystemVerilog **Immediate Assertions** evaluated at rising clock boundaries:

- `A_RESET_FLAGS`: Validates that `empty == 1`, `full == 0`, and `count == 0` during active reset.
- `A_RESET_ERROR_FLAGS`: Validates that `overflow == 0` and `underflow == 0` during active reset.
- `A_MUTEX_FULL_EMPTY`: Validates that `full` and `empty` are never asserted concurrently.
- `A_COUNT_LIMIT`: Validates that occupancy count never exceeds `DEPTH` (16).
- `A_FULL_FLAG_INVARIANT`: Enforces `full == (count == DEPTH)`.
- `A_EMPTY_FLAG_INVARIANT`: Enforces `empty == (count == 0)`.
- `A_ALMOST_FULL_RULE`: Enforces watermark assertion when `count >= DEPTH - ALMOST_FULL_THRESH`.
- `A_ALMOST_EMPTY_RULE`: Enforces watermark assertion when `count <= ALMOST_EMPTY_THRESH && count > 0`.
- `A_OVERFLOW_PROTOCOL`: Enforces that `overflow` asserts on the cycle following an illegal write to a full FIFO.
- `A_UNDERFLOW_PROTOCOL`: Enforces that `underflow` asserts on the cycle following an illegal read to an empty FIFO.

---

## 8. Defect-Injection Demonstration Workflow

To prove that verification checks genuinely catch hardware bugs (and do not pass vacuously), the framework includes a validated 3-stage defect injection laboratory:

```
[STAGE 1: DEFECT INJECTION]
Compile RTL with `+define+<BUG_MACRO>`
Run regression suite
VERIFICATION CHECK:
- Did regression fail?
- Did the expected test detector fail?
IF NO -> Mark DEMO FAILED and abort.
IF YES -> Proceed to Stage 2.
       ↓
[STAGE 2: RESTORE CLEAN BASELINE]
Compile clean golden RTL (`sync_fifo.sv`)
       ↓
[STAGE 3: CLEAN VERIFICATION PASS]
Run regression on golden RTL
VERIFICATION CHECK:
- Did all 10 tests pass?
- Were zero errors reported?
IF NO -> Mark DEMO FAILED.
IF YES -> Mark STAGE_3_VERIFIED.
```

### Available Defect Injections
1. `BUG_INJECT_OVERFLOW`: Disables write protection when full; memory is overwritten and overflow error is masked. *(Detected by `test_overflow`, `test_random_traffic`)*
2. `BUG_INJECT_UNDERFLOW_FLAG`: Suppresses underflow error flag generation on illegal reads when empty. *(Detected by `test_underflow`)*
3. `BUG_INJECT_COUNT_SIMULTANEOUS`: Erroneously increments fill counter on concurrent read/write when full. *(Detected by `test_simultaneous_rw`, `test_random_traffic`)*
4. `BUG_INJECT_ALMOST_FULL`: Inverts the threshold comparison logic for almost-full detection. *(Detected by `test_almost_flags`)*
5. `BUG_INJECT_RESET_NEGLECT`: Fails to clear error flags during reset deassertion. *(Detected by `test_reset`)*

---

## 9. Continuous Integration (GitHub Actions)

The framework includes a CI pipeline defined in [`.github/workflows/regression.yml`](file:///.github/workflows/regression.yml):

- **Environment**: Ubuntu 22.04 LTS
- **Triggers**: Every `push` to `main` and all `pull_request` events.
- **Workflow**:
  1. Installs Icarus Verilog (`sudo apt-get install iverilog`).
  2. Executes the full regression suite via `python3 scripts/regression.py`.
  3. Verifies that all 10 tests pass with exit code `0`.
  4. Runs the defect-injection pipeline with `BUG_INJECT_OVERFLOW` to verify that CI correctly identifies hardware bugs and rejects broken builds.
  5. Publishes machine-readable summaries (`regression_summary.json`, `regression_summary.csv`, `regression_report.md`) as downloadable build artifacts.

---

## 10. Repository File Inventory

```
RTL Verification/
├── Launch_Dashboard.command     # macOS Desktop Finder double-clickable launcher
├── launch_dashboard.sh          # Shell one-click launcher for macOS and Linux
├── Makefile                     # Top-level commands (make dashboard, make test, make clean)
├── requirements.txt             # Environment declaration (Standard Library only)
├── README.md                    # Authoritative user guide and project documentation
│
├── dashboard/                   # Interactive Web Studio Frontend
│   ├── index.html               # Semantic HTML5 layout with 8 operational panels
│   ├── css/
│   │   └── style.css            # Dark-mode EDA studio theme with responsive grid & badges
│   └── js/
│       ├── app.js               # Core frontend controller, REST API calls, SSE streaming
│       └── waveform_viewer.js   # In-browser HTML5 2D Canvas digital timing diagram renderer
│
├── rtl/
│   └── sync_fifo.sv             # Parameterized Synchronous FIFO with compile-time bug hooks
│
├── tb/
│   ├── fifo_pkg.sv              # Verification package, transaction structs, logging macros
│   ├── fifo_driver.sv           # Active stimulus driver (write, read, burst, reset)
│   ├── fifo_monitor.sv          # Passive transaction monitor
│   ├── fifo_scoreboard.sv       # Golden reference queue model & bitwise comparator
│   ├── fifo_assertions.sv      # SystemVerilog Immediate Assertions for safety invariants
│   └── tb_top.sv                # Top harness, clock generator, test plusarg dispatcher
│
├── tests/                       # 10 Verification Test Cases
│   ├── test_base.sv             # Base test tasks and common verification helpers
│   ├── test_reset.sv            # Test 1: Reset behavior and register initialization
│   ├── test_single_write_read.sv# Test 2: Single word write followed by read
│   ├── test_burst_write_read.sv # Test 3: Burst write and burst read sequence
│   ├── test_fifo_full.sv        # Test 4: Capacity limit and full flag assertion
│   ├── test_fifo_empty.sv       # Test 5: Drain sequence and empty flag assertion
│   ├── test_simultaneous_rw.sv  # Test 6: Concurrent read and write at partial & full fill
│   ├── test_overflow.sv         # Test 7: Overflow attempt and memory non-corruption
│   ├── test_underflow.sv        # Test 8: Underflow attempt and error flag generation
│   ├── test_almost_flags.sv     # Test 9: Watermark threshold crossing verification
│   └── test_random_traffic.sv   # Test 10: Seed-controlled weighted pseudo-random stimulus
│
├── scripts/                     # Backend API & Automation Engine
│   ├── dashboard_server.py      # Multi-threaded REST API server, SSE log streamer, VCD parser
│   ├── run_test.py              # Single test runner, log capture, timeout, exit codes
│   ├── regression.py            # Regression orchestrator, JSON/CSV/Markdown reports
│   └── generate_report.py       # Standalone report generator from simulation logs
│
├── docs/                        # Engineering Documentation
│   ├── architecture.md          # Full-stack system architecture, dataflow, security model
│   ├── dut_specification.md     # Hardware specification for sync_fifo
│   ├── verification_plan.md     # Test matrix, SVA taxonomy, sign-off criteria
│   └── troubleshooting.md       # Diagnostic guide for local simulation & tooling
│
├── sim/                         # Simulation build artifacts (.vvp binaries)
├── reports/                     # Machine-readable summaries and human-readable reports
│   └── logs/                    # Individual test execution logs
├── waves/                       # Value Change Dump (.vcd) waveform files
└── .github/
    └── workflows/
        └── regression.yml       # GitHub Actions CI workflow
```

---

## 11. Developer & CI CLI Reference

For automated build pipelines, headless servers, and CI environments, the underlying Python scripts and Makefile remain fully functional:

```bash
# Launch Dashboard (Recommended normal workflow)
make dashboard

# Compile simulation binary
make compile

# Run single test in terminal
make test TEST=test_burst_write_read
make test TEST=test_random_traffic SEED=1234 WAVE=1

# Run full headless regression
make regression

# Run regression with injected defect
make regression-bug BUG=BUG_INJECT_OVERFLOW

# Run validated 3-stage defect lifecycle demonstration
make demo-defect BUG=BUG_INJECT_OVERFLOW

# Open waveform in desktop GTKWave
make wave TEST=test_burst_write_read

# View latest summary report
make report

# Clean all generated artifacts
make clean
```

---

## 12. Troubleshooting Guide

- **Port 8080 Conflict**: The dashboard server automatically probes ports `8080..8180` and binds to the first free port. You can also specify an explicit port:
  ```bash
  python3 scripts/dashboard_server.py --port 9090
  ```
- **macOS Gatekeeper**: If macOS prompts when double-clicking `Launch_Dashboard.command` or opening GTKWave for the first time, navigate to **System Settings -> Privacy & Security** and click **Open Anyway**.
- **Blank In-Browser Waveforms**: Ensure the test was executed with the waveform option enabled (**Dump Waveforms** checkbox in the **Configure & Run** modal).
- **Workspace Cleaning**: To purge stale `.vvp`, `.log`, and `.vcd` files, click **"Purge Build Artifacts & Logs"** in the **System Health** panel or run `make clean`.

---

## 13. Process Safety & Security Boundaries

Because the dashboard server executes simulation processes locally, strict defensive programming practices are implemented:
- **No Arbitrary Shell Execution**: The dashboard backend does not expose generic shell or command execution endpoints. All commands are constructed using discrete argument lists (`subprocess.run(["iverilog", ...])`).
- **Strict Parameter Allowlisting**: Test names are matched against strict regex patterns (`^[a-zA-Z0-9_]+$`) and validated against discovered files in `tests/`. Defect macros are checked against an immutable allowlist (`VALID_BUG_MACROS`).
- **Loopback Binding**: The dashboard binds exclusively to `127.0.0.1` (localhost), preventing unauthenticated access across local networks.
- **Process Timeout Protection**: Individual simulations are protected by a 30-second watchdog timer to eliminate zombie processes from infinite simulation loops.

---

## 14. Toolchain Limitations & Engineering Honesty

To ensure technical honesty and defensibility during engineering evaluations:
1. **Simulator Scope**: Built and validated using **Icarus Verilog (`iverilog` / `vvp` v13.0)**. While the RTL and SystemVerilog testbench follow standard IEEE 1800 syntax, compilation flags in the regression engine default to `iverilog -g2012`.
2. **SystemVerilog Assertions**: Evaluated using **SystemVerilog Immediate Assertions** (`assert (...) else $error(...)`). Concurrent assertions (`assert property` with `property ... endproperty` temporal sequence expressions) are not supported by Icarus Verilog (`error: Invalid module item`).
3. **Functional Coverage**: SystemVerilog `covergroup` and `coverpoint` constructs are not supported by Icarus Verilog and are therefore not implemented.
4. **Randomization Methodology**: Implemented as seed-controlled weighted pseudo-random stimulus (`test_random_traffic.sv`) using `$urandom(seed)`. Class solver-based Constrained Random Verification (CRV) with `constraint` blocks is not supported by Icarus Verilog.
5. **Browser VCD Parsing Scale**: The in-browser waveform parser is optimized for focused unit test traces (up to 500,000 transitions). For multi-gigabyte traces from lengthy stress tests, use the one-click **Launch GTKWave** button.

---

**RTL Verification & Automated Regression Studio** is verified and ready for use.
Launch the studio with `./launch_dashboard.sh` or double-click `Launch_Dashboard.command`!
