# Verification Plan: Synchronous FIFO (`sync_fifo`)

## 1. Introduction & Verification Objectives
The goal of this verification plan is to achieve thorough, deterministic functional verification of the Parameterized Synchronous FIFO (`sync_fifo.sv`).

The verification environment must prove that:
1. Data integrity is strictly maintained (First-In, First-Out order, zero bit flips, zero loss, zero duplication).
2. Pointers wrap correctly without boundary anomalies.
3. Status flags (`empty`, `full`, `almost_empty`, `almost_full`) accurately reflect internal state at every cycle.
4. Simultaneous read and write operations resolve properly across all fill states (empty, partial, full).
5. Illegal operations (write when full, read when empty) are safely blocked without memory corruption, and dedicated error flags (`overflow`, `underflow`) are raised.
6. The reset sequence brings all registers to their specified default values deterministically.
7. SystemVerilog Assertions (SVA) enforce safety properties on every active clock edge.
8. Intentionally injected hardware defects cause regression failures deterministically.

---

## 2. Testbench Architecture & Layering

```
+------------------------------------------------------------------------------------+
|                                    TESTBENCH TOP                                   |
|                                     (tb_top.sv)                                    |
|                                                                                    |
|  Clock Gen (100MHz) | Reset Gen | Plusarg Dispatcher (+TESTNAME, +SEED, +DUMP_WAVE)|
|  --------------------------------------------------------------------------------  |
|  SystemVerilog Assertions (fifo_assertions.sv)                                     |
|  --------------------------------------------------------------------------------  |
|    +-------------------+       +--------------------+       +-------------------+  |
|    |    Stimulus       | ----> |    FIFO Driver     | ----> |    DUT            |  |
|    |  (tests/*.sv)     |       |  (fifo_driver.sv)  |       |  (sync_fifo.sv)   |  |
|    +-------------------+       +--------------------+       +-------------------+  |
|                                         |                             |            |
|                                         v (wr_mon)                    v (rd_mon)   |
|                                +----------------------------------------------+    |
|                                |                 FIFO Monitor                 |    |
|                                |              (fifo_monitor.sv)               |    |
|                                +----------------------------------------------+    |
|                                         |                             |            |
|                                         v (tx)                        v (tx)       |
|                                +----------------------------------------------+    |
|                                |            FIFO Scoreboard & Model           |    |
|                                |             (fifo_scoreboard.sv)             |    |
|                                | - Independent golden queue model             |    |
|                                | - Read vs expected comparison                |    |
|                                | - Fill level & flag tracking                 |    |
|                                | - Summary pass/fail accounting               |    |
|                                +----------------------------------------------+    |
+------------------------------------------------------------------------------------+
```

### 2.1 Interface & Monitor
- **Write Monitor**: Samples `wr_en`, `wr_data`, `full` at `posedge clk`. When `wr_en && (!full || rd_en)`, queues transaction into the golden reference model.
- **Read Monitor**: Samples `rd_en`, `rd_data`, `empty` at `posedge clk`. When `rd_en && !empty`, forwards transaction to the scoreboard for comparison.

### 2.2 Scoreboard & Reference Model
- Independent golden reference queue storing expected transactions.
- Independent occupancy counter computing expected `full`, `empty`, `almost_full`, `almost_empty`.
- Instant comparison of each read transaction with expected queue head:
  - Error flagged if data mismatch occurs.
  - Error flagged if FIFO outputs data when expected empty.
  - Error flagged if FIFO reports full when expected has space.
- Post-test drain check ensuring zero unverified lingering items.

---

## 3. Test Matrix & Scenarios

| Test Identifier | Category | Purpose & Stimulus Description | Expected Outcome |
| :--- | :--- | :--- | :--- |
| `test_reset` | Reset / Boundary | Asserts reset for 5 cycles; verifies default flag states; applies writes during reset to verify rejection; releases reset and confirms normal operation. | Reset state verified; illegal writes during reset ignored; post-reset operations succeed. |
| `test_single_write_read` | Directed / Basic | Writes single word (e.g. `8'hA5`), checks `empty` transitions low, reads word on subsequent cycle, verifies `empty` returns high. | Read data matches `8'hA5`; count transitions 0->1->0; flags valid. |
| `test_burst_write_read` | Directed / Functional | Writes burst of 8 distinct sequential values, waits 3 idle cycles, reads all 8 values in burst mode. | Strict FIFO ordering verified for all 8 items; no data loss or corruption. |
| `test_fifo_full` | Boundary | Performs consecutive writes until `count == DEPTH` (16 words). Verifies `full == 1` and `almost_full == 1`. | Full flag asserted on 16th write; write pointer wrapped or capped correctly. |
| `test_fifo_empty` | Boundary | Fills FIFO partially (4 items) then reads until empty. Verifies `empty == 1` and `almost_empty` deasserts at 0. | `empty` asserted immediately upon reading last element; subsequent reads disabled. |
| `test_simultaneous_rw` | Corner Case | Fills FIFO to 8 items, then issues concurrent `wr_en` and `rd_en` for 16 consecutive cycles. Then tests concurrent RW at full capacity. | Count remains steady; read data matches golden stream; no data dropped or duplicated. |
| `test_overflow` | Error / Robustness | Fills FIFO to `DEPTH`. Attempts 5 consecutive illegal writes while `full`. Reads all valid data back. | `overflow` flag asserted; memory protected; the original 16 words read back unharmed. |
| `test_underflow` | Error / Robustness | While empty, issues 5 consecutive illegal read requests. Verifies `underflow` flag. Writes and reads valid item. | `underflow` flag asserted; empty remains 1; subsequent valid write/read succeeds. |
| `test_almost_flags` | Boundary / Watermark | Increments occupancy item-by-item across `ALMOST_EMPTY_THRESH` and `ALMOST_FULL_THRESH`. Decrements back to 0. | `almost_empty` and `almost_full` flags assert and deassert at exact threshold boundaries. |
| `test_random_traffic` | Stress / Random | Applies 200 cycles of constrained pseudo-random operations (random `wr_en`, `rd_en`, payload, and back-to-back bursts). Configurable seed. | 100% data integrity verified by scoreboard; zero assertion violations. |

---

## 4. Assertion Taxonomy (SVA)

All properties are evaluated on `@(posedge clk)`:

1. **`A_RESET_STATE`**:
   $$\text{rst\_n} == 0 \implies (\text{empty} == 1 \land \text{full} == 0 \land \text{count} == 0 \land \text{overflow} == 0 \land \text{underflow} == 0)$$
2. **`A_MUTEX_FULL_EMPTY`**:
   $$\neg (\text{full} \land \text{empty})$$
3. **`A_OVERFLOW_DETECT`**:
   $$(\text{wr\_en} \land \text{full} \land \neg \text{rd\_en}) \implies \text{overflow}$$
4. **`A_UNDERFLOW_DETECT`**:
   $$(\text{rd\_en} \land \text{empty}) \implies \text{underflow}$$
5. **`A_COUNT_LIMIT`**:
   $$\text{count} \le \text{DEPTH}$$
6. **`A_ALMOST_FULL_RULE`**:
   $$\text{count} \ge (\text{DEPTH} - \text{ALMOST\_FULL\_THRESH}) \implies \text{almost\_full}$$
7. **`A_ALMOST_EMPTY_RULE`**:
   $$(\text{count} \le \text{ALMOST\_EMPTY\_THRESH} \land \neg \text{empty}) \implies \text{almost\_empty}$$

---

## 5. Verification Sign-Off Criteria

The verification suite achieves sign-off when:
- All 10 tests compile cleanly without simulator warnings or errors.
- 100% of the tests in the regression suite pass (`10 Passed, 0 Failed`).
- Zero scoreboard mismatches and zero assertion violations are reported across all test logs.
- Bug-injection tests confirm that each injected defect is detected by at least one test in the suite.
- Waveforms are generated and verified for signal transitions and timing.
- Machine-readable (JSON, CSV) and human-readable (Markdown) reports are generated with exit code 0.
