# System Architecture & Verification Methodology

## 1. Directory Structure

```
rtl-verification-regression/
├── rtl/
│   └── sync_fifo.sv             # Parameterized Synchronous FIFO with defect injection hooks
├── tb/
│   ├── fifo_pkg.sv              # Verification package, transaction structs, logging macros
│   ├── fifo_driver.sv           # Active stimulus driver (write, read, burst, reset)
│   ├── fifo_monitor.sv          # Passive transaction monitor
│   ├── fifo_scoreboard.sv       # Independent golden reference model & data comparator
│   ├── fifo_assertions.sv      # SystemVerilog safety assertions (protocol & flags)
│   └── tb_top.sv                # Top-level harness, clock/reset generator, test dispatcher
├── tests/
│   ├── test_base.sv             # Base test tasks and common verification helpers
│   ├── test_reset.sv            # Test 1: Reset behavior and register state
│   ├── test_single_write_read.sv# Test 2: Single word write followed by read
│   ├── test_burst_write_read.sv # Test 3: Burst write and burst read sequence
│   ├── test_fifo_full.sv        # Test 4: Capacity limit and full flag assertion
│   ├── test_fifo_empty.sv       # Test 5: Drain sequence and empty flag assertion
│   ├── test_simultaneous_rw.sv  # Test 6: Concurrent read and write at partial & full fill
│   ├── test_overflow.sv         # Test 7: Overflow attempt and memory non-corruption
│   ├── test_underflow.sv        # Test 8: Underflow attempt and error flag generation
│   ├── test_almost_flags.sv     # Test 9: Watermark threshold crossing verification
│   └── test_random_traffic.sv   # Test 10: Constrained random stimulus with seed control
├── scripts/
│   ├── run_test.py              # Single test runner, log capture, timeout, exit codes
│   ├── regression.py            # Regression orchestrator, JSON/CSV/Markdown reports
│   └── generate_report.py       # Standalone report generator from simulation logs
├── docs/
│   ├── dut_specification.md     # Hardware specification for sync_fifo
│   ├── verification_plan.md     # Test matrix, SVA taxonomy, sign-off criteria
│   ├── architecture.md          # Architecture and execution methodology (this file)
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
└── README.md                    # Publication-quality project documentation
```

---

## 2. Component Separation & Dataflow

To ensure unbiased verification, the architecture enforces strict separation of responsibilities:

1. **Stimulus Generation (`tests/*.sv`, `fifo_driver.sv`)**:
   - The test defines the sequence of operations (e.g. write N words, wait M cycles, read K words).
   - The driver toggles interface signals (`wr_en`, `wr_data`, `rd_en`) synchronously to `clk`.
   - The stimulus components have zero knowledge of the expected outcomes or scoreboard state.

2. **Observation (`fifo_monitor.sv`)**:
   - The monitor passively samples signal lines on the active clock edge (`posedge clk`).
   - Writes are sampled when `wr_en` is asserted and the FIFO is ready to accept data (`!full || rd_en`).
   - Reads are sampled when `rd_en` is asserted and valid data is output (`!empty`).
   - Monitored transactions are pushed to the scoreboard via standardized mailboxes/tasks.

3. **Golden Reference Model & Checking (`fifo_scoreboard.sv`)**:
   - Maintains an independent golden queue model completely separate from the DUT's memory array.
   - When a write is accepted, the golden model enqueues the payload.
   - When a read occurs, the golden model dequeues the expected payload and performs a strict bit-for-bit comparison against `rd_data`.
   - Occupancy is independently tracked to verify `count`, `full`, `empty`, `almost_full`, and `almost_empty`.
   - Any mismatch immediately triggers an error message with full timestamp and data details.

4. **Safety & Protocol Assertions (`fifo_assertions.sv`)**:
   - Independent verification checking rules evaluated at every clock cycle.
   - Verifies invariant properties (e.g. `!(full && empty)`, `count <= DEPTH`).
   - Verifies protocol rules (e.g. `overflow` must assert if `wr_en && full && !rd_en`).

---

## 3. Test Dispatch & Plusargs Mechanism

The testbench is compiled into a single unified binary (`sim/tb_top.vvp`). Individual tests are selected at runtime using simulator plusargs without requiring recompilation:

```bash
vvp sim/tb_top.vvp +TESTNAME=test_burst_write_read +SEED=42 +DUMP_WAVE=1
```

Inside `tb/tb_top.sv`:
```systemverilog
string test_name;
int seed;
int dump_wave;

initial begin
  if (!$value$plusargs("TESTNAME=%s", test_name)) test_name = "test_single_write_read";
  if (!$value$plusargs("SEED=%d", seed)) seed = 1;
  dump_wave = $test$plusargs("DUMP_WAVE");

  if (dump_wave) begin
    $dumpfile({"waves/", test_name, ".vcd"});
    $dumpvars(0, tb_top);
  end

  // Dispatch test sequence
  run_test_by_name(test_name, seed);
end
```

---

## 4. Exit Code Contract & Pass/Fail Signatures

To ensure deterministic automation between simulator, Python scripts, Make, and CI, the testbench adheres to a strict protocol:

| Status | Terminal Log Signature | Simulator Exit Code | Python Return Code | CI Status |
| :--- | :--- | :--- | :--- | :--- |
| **PASS** | `=== TEST PASSED: <testname> ===` | `0` (`$finish(0)`) | `0` | Success |
| **FAIL (Mismatch)** | `*** ERROR: Scoreboard Mismatch ...` followed by `=== TEST FAILED: <testname> ===` | `1` (`$fatal(1)` or `$finish(1)`) | `1` | Failure |
| **FAIL (Assertion)** | `*** ASSERTION FAILED: <property> ...` followed by `=== TEST FAILED ===` | `1` | `1` | Failure |
| **TIMEOUT** | `*** FATAL: Watchdog timer expired at <time> ns ***` | `1` | `3` | Failure |
| **COMPILE ERROR** | Compiler syntax / elaboration error | Non-zero (`iverilog`) | `2` | Failure |

The Python harness validates both the process return code **and** the presence of the exact terminal signature `=== TEST PASSED: <testname> ===`. A run that exits with code 0 but lacks the pass signature is classified as an infrastructure error.
