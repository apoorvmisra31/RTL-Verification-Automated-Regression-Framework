# Verification Plan: Synchronous FIFO (`sync_fifo`)

An authoritative verification specification and test plan for the Parameterized Synchronous FIFO (`sync_fifo.sv`), defining the coverage metrics, test scenarios, assertion taxonomy, defect-injection verification matrix, and dashboard control surface mappings.

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
6. **Defect Catching**: 100% deterministic detection of injected hardware defects by the verification harness.

---

## 2. Test Matrix & Verification Scenarios

All 10 verification scenarios are implemented in `tests/` and operable via the Verification Studio Dashboard:

| Test Identifier | Category | Verification Scenario & Stimulus | Pass Criteria | Dashboard Control |
| :--- | :--- | :--- | :--- | :--- |
| `test_reset` | Reset | Asserts asynchronous reset for 5 cycles; verifies default flag states; applies writes during reset to verify stimulus rejection; releases reset and confirms recovery. | All flags default; writes during reset ignored; post-reset operations succeed. | Test Catalog -> Configure & Run -> `test_reset` |
| `test_single_write_read` | Directed | Writes single word (`8'hA5`), checks `empty` transitions low, reads word on next cycle, verifies `empty` returns high. | Read data matches `8'hA5`; count transitions 0->1->0; flags valid. | Test Catalog -> Configure & Run -> `test_single_write_read` |
| `test_burst_write_read` | Functional | Writes burst of 8 distinct sequential values, waits 3 idle cycles, reads all 8 values in burst mode. | Strict FIFO ordering verified for all 8 items; zero data mismatch. | Test Catalog -> Configure & Run -> `test_burst_write_read` |
| `test_fifo_full` | Boundary | Consecutive writes until `count == DEPTH` (16 words). Verifies `full == 1` and `almost_full == 1`. | Full flag asserted on 16th write; write pointer wrapped or capped correctly. | Test Catalog -> Configure & Run -> `test_fifo_full` |
| `test_fifo_empty` | Boundary | Fills FIFO partially (4 items) then reads until empty. Verifies `empty == 1` and `almost_empty` deasserts at 0. | `empty` asserted immediately upon reading last element; subsequent reads disabled. | Test Catalog -> Configure & Run -> `test_fifo_empty` |
| `test_simultaneous_rw` | Corner Case | Fills FIFO to 8 items, then issues concurrent `wr_en` and `rd_en` for 16 consecutive cycles. Then tests concurrent RW at full capacity. | Count remains steady; read data matches golden stream; no data dropped or duplicated. | Test Catalog -> Configure & Run -> `test_simultaneous_rw` |
| `test_overflow` | Robustness | Fills FIFO to `DEPTH`. Attempts 5 consecutive illegal writes while `full`. Reads all valid data back. | `overflow` flag asserted; memory protected; original 16 words read back unharmed. | Test Catalog -> Configure & Run -> `test_overflow` |
| `test_underflow` | Robustness | While empty, issues 5 consecutive illegal read requests. Verifies `underflow` flag. Writes and reads valid item. | `underflow` flag asserted; empty remains 1; subsequent valid write/read succeeds. | Test Catalog -> Configure & Run -> `test_underflow` |
| `test_almost_flags` | Watermark | Increments occupancy item-by-item across `ALMOST_EMPTY_THRESH` and `ALMOST_FULL_THRESH`. Decrements back to 0. | `almost_empty` and `almost_full` flags assert and deassert at exact threshold boundaries. | Test Catalog -> Configure & Run -> `test_almost_flags` |
| `test_random_traffic` | Stress | Applies 200 cycles of constrained pseudo-random operations (random `wr_en`, `rd_en`, payload, and bursts) with repeatable seed control. | 100% data integrity verified by scoreboard; zero assertion violations. | Test Catalog -> Configure & Run -> `test_random_traffic` |

---

## 3. SystemVerilog Assertion (SVA) Taxonomy

Formal safety invariants evaluated continuously in `tb/fifo_assertions.sv` at `@(posedge clk)`:

| Assertion Identifier | Formal Property Specification | Description |
| :--- | :--- | :--- |
| `A_RESET_STATE` | `!rst_n \|-> (empty == 1 && full == 0 && count == 0 && overflow == 0 && underflow == 0)` | Validates that active reset forces all registers to clean initial state. |
| `A_MUTEX_FULL_EMPTY` | `!(full && empty)` | Safety invariant: FIFO cannot be simultaneously full and empty. |
| `A_COUNT_LIMIT` | `count <= DEPTH` | FIFO occupancy count can never exceed maximum hardware depth (16). |
| `A_OVERFLOW_DETECT` | `(wr_en && full && !rd_en) \|=> overflow` | Writing to a full FIFO without simultaneous read must trigger `overflow`. |
| `A_UNDERFLOW_DETECT` | `(rd_en && empty) \|=> underflow` | Reading from an empty FIFO must trigger `underflow`. |
| `A_ALMOST_FULL_RULE` | `count >= (DEPTH - ALMOST_FULL_THRESH) \|-> almost_full` | Watermark check: `almost_full` must assert when count $\ge 14$. |
| `A_ALMOST_EMPTY_RULE`| `count <= ALMOST_EMPTY_THRESH \|-> almost_empty` | Watermark check: `almost_empty` must assert when count $\le 2$. |

---

## 4. Defect-Injection Verification Matrix

To prove the non-vacuity of the verification environment, 5 compile-time RTL defect macros are implemented in `rtl/sync_fifo.sv`. Each defect is guaranteed to be detected by specific tests in the regression suite:

| Defect Macro | Injected RTL Bug Description | Detecting Test Cases | Detection Mechanism |
| :--- | :--- | :--- | :--- |
| `BUG_INJECT_OVERFLOW` | Disables write protection on full; write pointer increments and overwrites unread memory. | `test_overflow`, `test_random_traffic` | Scoreboard detects data corruption; `A_OVERFLOW_DETECT` assertion failure. |
| `BUG_INJECT_UNDERFLOW_FLAG`| Suppresses `underflow` error flag generation on illegal reads when empty. | `test_underflow` | Scoreboard flag validation error; `A_UNDERFLOW_DETECT` assertion failure. |
| `BUG_INJECT_COUNT_SIMULTANEOUS` | Erroneously increments occupancy counter during concurrent read/write when full. | `test_simultaneous_rw` | Scoreboard count mismatch; `A_COUNT_LIMIT` assertion failure (`count > 16`). |
| `BUG_INJECT_ALMOST_FULL` | Inverts threshold comparison logic (`count <= threshold` instead of `>=`). | `test_almost_flags` | Scoreboard status flag checker flags incorrect `almost_full` value. |
| `BUG_INJECT_RESET_NEGLECT` | Omits reset clearing logic for error flags (`overflow`, `underflow`). | `test_reset` | Reset task observes persistent error flags; `A_RESET_STATE` assertion failure. |

---

## 5. Dashboard Control Surface Mapping

Every requirement in this verification plan is mapped to a dedicated control surface in the Verification Studio Web UI:

```
VERIFICATION GOAL               DASHBOARD CONTROL SURFACE
-----------------------------------------------------------------------------------------
Execute Single Test             Test Catalog -> Card -> [Configure & Run] Modal
Run Full Regression Suite       Regression Suite -> [Run Full Regression] Button
Observe Live Test Execution     Regression Suite -> Real-Time Log Terminal Window (SSE)
Inspect Pass/Fail Metrics       Overview / KPI Summary & Reports -> Summary Cards
Inspect Signal Transitions      Waveforms Tab -> In-Browser HTML5 Timing Diagram
Launch Desktop Waveform Tool    Waveforms Tab -> [Launch in Desktop GTKWave] Button
Search Simulator Logs           Log Inspector -> Test Dropdown & Real-time Text Filter
Export Machine-Readable Data    Reports & Data -> Download JSON / Download CSV Buttons
Demonstrate Defect Detection    Defect Lab -> Select Defect -> [Run Defect Injection Demo]
Check System & Simulator Path   System Health -> Toolchain Status Cards
```

---

## 6. Verification Sign-Off Criteria

Verification sign-off is achieved when:
1. **100% Test Pass Rate**: All 10 tests in the suite pass cleanly (`10 Passed, 0 Failed`).
2. **Zero Scoreboard Errors**: Every monitored read transaction matches the golden reference queue bit-for-bit.
3. **Zero Assertion Violations**: All 7 SystemVerilog Assertions hold true continuously without failure.
4. **100% Defect Detection**: All 5 hardware defect injection experiments fail predictably when activated and recover cleanly when deactivated.
5. **Automated CI Validation**: GitHub Actions workflow completes with zero errors on Ubuntu CI runners.
