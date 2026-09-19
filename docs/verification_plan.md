# Verification Plan: Synchronous FIFO (`sync_fifo`)

An authoritative verification specification and test plan for the Parameterized Synchronous FIFO (`sync_fifo.sv`), defining verification objectives, architectural layering, test scenarios, assertion taxonomy, defect-injection matrix, and toolchain capabilities.

---

## 1. Introduction & Verification Objectives

The primary objective is the functional verification of `sync_fifo.sv` across all normal, boundary, corner-case, and illegal operation scenarios.

### Verified Hardware Parameters
- **`DATA_WIDTH`**: 8 bits
- **`DEPTH`**: 16 words
- **`ALMOST_FULL_THRESH`**: 2 (Asserts when fill level $\ge 14$)
- **`ALMOST_EMPTY_THRESH`**: 2 (Asserts when fill level $\le 2$)

### Verification Goals
1. **Data Integrity**: 100% data preservation across all transactions. Zero bit flips, zero packet drops, zero duplications, strict FIFO ordering.
2. **Flag Timings**: Cycle-accurate evaluation of `empty`, `full`, `almost_empty`, and `almost_full`.
3. **Protocol Robustness**: Verifying that illegal operations (writes when full, reads when empty) are safely blocked without memory corruption, while raising single-cycle `overflow` and `underflow` error pulses.
4. **Concurrent Operations**: Zero data loss during continuous simultaneous read/write cycles across empty, partial, and full fill states.
5. **Reset Invariants**: Complete clearing of pointers, counts, and error flags upon active-low asynchronous reset assertion.
6. **Defect Catching**: Deterministic detection of injected hardware defects by the verification harness.

---

## 2. Testbench Architecture & Data Path

The testbench strictly separates stimulus generation, signal observation, and independent checking across modular SystemVerilog blocks:

```
+------------------------------------------------------------------------------------+
|                                    TESTBENCH TOP                                   |
|                                     (tb_top.sv)                                    |
|                                                                                    |
|  Clock Gen (100MHz) | Reset Gen | Plusarg Dispatcher (+TESTNAME, +SEED, +DUMP_WAVE)|
|  --------------------------------------------------------------------------------  |
|  SystemVerilog Immediate Assertions (fifo_assertions.sv)                           |
|  --------------------------------------------------------------------------------  |
|    +-------------------+       +--------------------+       +-------------------+  |
|    |    Stimulus       | ----> |    FIFO Driver     | ----> |    DUT            |  |
|    |  (tests/*.sv)     |       |  (fifo_driver.sv)  |       |  (sync_fifo.sv)   |  |
|    +-------------------+       +--------------------+       +-------------------+  |
|                                                                       |            |
|                                                                       v            |
|                                +----------------------------------------------+    |
|                                |                 FIFO Monitor                 |    |
|                                |              (fifo_monitor.sv)               |    |
|                                | - Samples DUT interface on posedge clk       |    |
|                                | - Qualifies accepted writes & valid reads    |    |
|                                | - Forwards monitored tx to scoreboard        |    |
|                                +----------------------------------------------+    |
|                                                        |                           |
|                                                        v                           |
|                                +----------------------------------------------+    |
|                                |            FIFO Scoreboard & Model           |    |
|                                |             (fifo_scoreboard.sv)             |    |
|                                | - Independent golden queue model             |    |
|                                | - Read vs expected comparison                |    |
|                                | - Fill level & flag tracking                 |    |
|                                | - Error accounting (mismatches, flag errors) |    |
|                                +----------------------------------------------+    |
+------------------------------------------------------------------------------------+
```

### 2.1 Driver (`tb/fifo_driver.sv`)
Active stimulus agent driving cycle-accurate waveforms (`rst_n`, `wr_en`, `wr_data`, `rd_en`) synchronous to `@(negedge clk)` to guarantee clean setup and hold margins before active rising clock edges.

### 2.2 Monitor (`tb/fifo_monitor.sv`)
Passive transaction observer. At `@(posedge clk)`, samples DUT interface lines, qualifies accepted transactions (`wr_en && (!full || rd_en)` and `rd_en && !empty`), and forwards observed payloads and status checks directly to the scoreboard.

### 2.3 Scoreboard & Independent Reference Model (`tb/fifo_scoreboard.sv`)
Maintains an independent golden reference queue (`logic [DATA_WIDTH-1:0] ref_queue[$]`). It independently tracks expected occupancy, predicts status flags, and compares each read data word against the golden queue head. Any mismatch or state discrepancy increments error counters and triggers diagnostic logs.

---

## 3. Test Matrix & Verification Scenarios

All 10 verification scenarios are implemented in `tests/` and operable via both the Verification Studio Dashboard and automated CLI commands:

| Test Identifier | Category | Verification Scenario & Stimulus | Pass Criteria | Dashboard & CLI Control |
| :--- | :--- | :--- | :--- | :--- |
| `test_reset` | Reset | Asserts reset for 5 cycles; verifies default flag states; applies writes during reset to verify stimulus rejection; releases reset and confirms normal recovery. | All flags default; writes during reset ignored; post-reset operations succeed. | `make test TEST=test_reset` |
| `test_single_write_read` | Directed | Writes single word (`8'hA5`), checks `empty` transitions low, reads word on next cycle, verifies `empty` returns high. | Read data matches `8'hA5`; count transitions 0->1->0; flags valid. | `make test TEST=test_single_write_read` |
| `test_burst_write_read` | Functional | Writes burst of 8 distinct sequential values, waits 3 idle cycles, reads all 8 values in burst mode. | Strict FIFO ordering verified for all 8 items; zero data mismatch. | `make test TEST=test_burst_write_read` |
| `test_fifo_full` | Boundary | Consecutive writes until `count == DEPTH` (16 words). Verifies `full == 1` and `almost_full == 1`. Tests single-read full deassertion. | Full flag asserted on 16th write; single-read deasserts full flag cleanly. | `make test TEST=test_fifo_full` |
| `test_fifo_empty` | Boundary | Fills FIFO partially (4 items) then reads until empty. Verifies `empty == 1` and stability across idle cycles. | `empty` asserted immediately upon reading last element; subsequent reads disabled. | `make test TEST=test_fifo_empty` |
| `test_simultaneous_rw` | Corner Case | Fills FIFO to 8 items, then issues concurrent `wr_en` and `rd_en` for 16 consecutive cycles. Then tests concurrent RW at full capacity. | Count remains steady; read data matches golden stream; no data dropped or duplicated. | `make test TEST=test_simultaneous_rw` |
| `test_overflow` | Robustness | Fills FIFO to `DEPTH`. Attempts 5 consecutive illegal writes while `full`. Reads all valid data back. | `overflow` flag asserts on illegal write; deasserts post-stop; original 16 words read back unharmed. | `make test TEST=test_overflow` |
| `test_underflow` | Robustness | While empty, issues 5 consecutive illegal read requests. Verifies `underflow` flag. Writes and reads valid item. | `underflow` flag asserts on illegal read; deasserts post-stop; subsequent valid write/read succeeds. | `make test TEST=test_underflow` |
| `test_almost_flags` | Watermark | Increments occupancy item-by-item across `ALMOST_EMPTY_THRESH` and `ALMOST_FULL_THRESH`. Decrements back to 0. | `almost_empty` and `almost_full` flags assert and deassert at exact threshold boundaries. | `make test TEST=test_almost_flags` |
| `test_random_traffic` | Stress | Applies 200 cycles of weighted pseudo-random operations (writes, reads, simultaneous RW, and bursts) with repeatable seed control. | 100% data integrity verified by scoreboard; zero assertion violations. | `make test TEST=test_random_traffic SEED=42` |

---

## 4. SystemVerilog Assertions (SVA) Taxonomy

Hardware invariants and protocol checks implemented in `tb/fifo_assertions.sv`:

| Assertion Identifier | Assertion Type | Property Checked | Failure Consequence |
| :--- | :--- | :--- | :--- |
| `A_RESET_FLAGS` | Immediate Assert | `empty == 1 && full == 0 && count == 0` during active reset | Flagged reset state failure; simulation `$fatal(1)` |
| `A_RESET_ERROR_FLAGS` | Immediate Assert | `overflow == 0 && underflow == 0` during active reset | Flagged reset failure; simulation `$fatal(1)` |
| `A_MUTEX_FULL_EMPTY` | Immediate Assert | `!(full && empty)` (Mutual exclusion) | Protocol safety failure; simulation `$fatal(1)` |
| `A_COUNT_LIMIT` | Immediate Assert | `count <= DEPTH` (Occupancy upper bound) | Pointer/counter overflow; simulation `$fatal(1)` |
| `A_FULL_FLAG_INVARIANT` | Immediate Assert | `full == (count == DEPTH)` | Flag desynchronization; simulation `$fatal(1)` |
| `A_EMPTY_FLAG_INVARIANT`| Immediate Assert | `empty == (count == 0)` | Flag desynchronization; simulation `$fatal(1)` |
| `A_ALMOST_FULL_RULE` | Immediate Assert | `almost_full == (count >= DEPTH - ALMOST_FULL_THRESH)` | Watermark failure; simulation `$fatal(1)` |
| `A_ALMOST_EMPTY_RULE`| Immediate Assert | `almost_empty == (count <= ALMOST_EMPTY_THRESH && count > 0)` | Watermark failure; simulation `$fatal(1)` |
| `A_OVERFLOW_PROTOCOL`| Immediate Assert | `overflow == 1` cycle following illegal write on full FIFO | Protocol violation; simulation `$fatal(1)` |
| `A_UNDERFLOW_PROTOCOL`| Immediate Assert | `underflow == 1` cycle following illegal read on empty FIFO | Protocol violation; simulation `$fatal(1)` |

> [!NOTE]
> **Simulator Compatibility Note on SVA**:
> All assertions are implemented using standard SystemVerilog **Immediate Assertions** (`assert (...) else $error(...)`), which are fully supported by Icarus Verilog (`iverilog -g2012`). Concurrent temporal sequences (`assert property` with `property ... endproperty`) are not supported by Icarus Verilog v13.0 (`error: Invalid module item`).

---

## 5. Defect-Injection Verification Matrix

To prove the non-vacuity of the verification environment, 5 compile-time RTL defect macros are implemented in `rtl/sync_fifo.sv`. Each defect is guaranteed to be detected by specific tests in the regression suite:

| Defect Macro | Injected RTL Bug Description | Detecting Test Cases | Detection Mechanism |
| :--- | :--- | :--- | :--- |
| `BUG_INJECT_OVERFLOW` | Disables write protection on full; memory overwritten and overflow masked. | `test_overflow`, `test_random_traffic` | Scoreboard detects data corruption; `A_OVERFLOW_PROTOCOL` failure. |
| `BUG_INJECT_UNDERFLOW_FLAG`| Suppresses `underflow` error flag generation on illegal reads when empty. | `test_underflow` | Scoreboard flag mismatch; `A_UNDERFLOW_PROTOCOL` failure. |
| `BUG_INJECT_COUNT_SIMULTANEOUS` | Erroneously increments fill counter during concurrent read/write when full. | `test_simultaneous_rw`, `test_random_traffic` | Scoreboard count mismatch; `A_COUNT_LIMIT` failure (`count > 16`). |
| `BUG_INJECT_ALMOST_FULL` | Inverts threshold comparison logic (`count < threshold` instead of `>=`). | `test_almost_flags` (and downstream) | Scoreboard status flag checker flags incorrect `almost_full`; `A_ALMOST_FULL_RULE` failure. |
| `BUG_INJECT_RESET_NEGLECT` | Omits reset clearing logic for error flags (`overflow`, `underflow`). | `test_reset` (and downstream) | Reset task observes persistent error flags; `A_RESET_ERROR_FLAGS` failure. |

---

## 6. Functional Coverage & Constrained Randomization Limitations

To ensure complete technical honesty:
1. **Functional Coverage (`covergroup` / `coverpoint`)**:
   - Functional coverage is **not implemented** because open-source Icarus Verilog 13.0 does not support SystemVerilog `covergroup` constructs (`error: Invalid module item`).
   - The test plan achieves thorough validation through exhaustive directed state sweeps, boundary value analysis, independent scoreboard state comparisons, and assertion checks.
2. **Constrained Random Verification (CRV)**:
   - Class-based constraint solvers (`class ... constraint ... randomize()`) are not supported in Icarus Verilog.
   - Randomized testing is achieved via seed-controlled weighted pseudo-random stimulus (`test_random_traffic.sv`) utilizing `$urandom(seed)` with predictable distribution weights.

---

## 7. Verification Sign-Off Criteria

Verification sign-off is achieved when:
1. **100% Test Pass Rate**: All 10 tests pass cleanly on golden RTL (`10 Passed, 0 Failed`).
2. **Zero Scoreboard Errors**: Every monitored read transaction matches the golden reference queue bit-for-bit.
3. **Zero Assertion Violations**: All 10 SystemVerilog immediate assertions hold true continuously without failure.
4. **Deterministic Defect Detection**: All 5 hardware defect injection experiments fail predictably when activated and recover cleanly when deactivated.
5. **Continuous Integration**: GitHub Actions workflow completes with zero errors on Ubuntu CI runners.
