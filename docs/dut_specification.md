# Hardware Design Specification: Synchronous FIFO (`sync_fifo`)

## 1. Overview
The `sync_fifo` is a fully synchronous, parameterizable First-In, First-Out (FIFO) buffer designed for on-chip data buffering, rate matching, and queueing across digital logic blocks operating within the same clock domain.

The design features:
- Configurable data width and memory depth.
- Independent write and read interfaces with handshake and status signaling.
- High-watermark (`almost_full`) and low-watermark (`almost_empty`) early warning flags.
- Real-time occupancy tracking (`count`).
- Strict overflow and underflow protection with dedicated single-cycle pulse error status flags.
- Support for concurrent read and write operations across empty, partial, and full fill states.
- Clean compile-time defect-injection hooks for automated verification regression validation.

---

## 2. Parameter Definitions

| Parameter Name | Type | Default Value | Valid Range | Description |
| :--- | :--- | :--- | :--- | :--- |
| `DATA_WIDTH` | `int` | `8` | $\ge 1$ | Width of the data bus in bits. |
| `DEPTH` | `int` | `16` | $\ge 2$ (Power of 2 recommended) | Maximum number of data words stored. |
| `ALMOST_FULL_THRESH` | `int` | `2` | $1 \le \text{Thresh} < \text{DEPTH}$ | Number of free slots remaining when `almost_full` asserts. |
| `ALMOST_EMPTY_THRESH` | `int` | `2` | $1 \le \text{Thresh} < \text{DEPTH}$ | Number of occupied slots remaining when `almost_empty` asserts. |

---

## 3. Interface Signals

All operations are synchronous to the rising edge of `clk`. Reset is asynchronous active-low (`rst_n`).

| Signal Name | Direction | Width | Description |
| :--- | :--- | :--- | :--- |
| `clk` | Input | `1` | Primary system clock. |
| `rst_n` | Input | `1` | Active-low asynchronous master reset. |
| `wr_en` | Input | `1` | Write enable request. Active-high. |
| `wr_data` | Input | `DATA_WIDTH` | Write data payload. Sampled on `clk` posedge when `wr_en` is high. |
| `rd_en` | Input | `1` | Read enable request. Active-high. |
| `rd_data` | Output | `DATA_WIDTH` | Read data payload. Synchronously updated upon valid read. |
| `full` | Output | `1` | Full status flag. High when FIFO holds `DEPTH` elements. |
| `empty` | Output | `1` | Empty status flag. High when FIFO holds `0` elements. |
| `almost_full` | Output | `1` | High when `count >= (DEPTH - ALMOST_FULL_THRESH)`. |
| `almost_empty` | Output | `1` | High when `count <= ALMOST_EMPTY_THRESH && !empty`. |
| `overflow` | Output | `1` | Error flag: asserted if `wr_en` is high while `full` without concurrent read. |
| `underflow` | Output | `1` | Error flag: asserted if `rd_en` is high while `empty`. |
| `count` | Output | `[$clog2(DEPTH+1)-1:0]` | Current occupancy count ($0 \le \text{count} \le \text{DEPTH}$). |

---

## 4. Operational Semantics

### 4.1 Reset State
When `rst_n` is driven low (`0`):
- Write pointer (`wr_ptr`) and Read pointer (`rd_ptr`) are reset to `0`.
- Occupancy counter (`count`) is reset to `0`.
- Status flags are initialized:
  - `empty = 1'b1`
  - `full = 1'b0`
  - `almost_full = 1'b0`
  - `almost_empty = 1'b0`
  - `overflow = 1'b0`
  - `underflow = 1'b0`
- `rd_data` is driven to `0` or holds default zero-vector.

### 4.2 Write Operation
A write occurs when `wr_en` is high on the rising edge of `clk`:
- **Normal Write (`count < DEPTH`)**:
  - `wr_data` is stored into `mem[wr_ptr]`.
  - `wr_ptr` advances to `(wr_ptr + 1) % DEPTH`.
  - If no concurrent valid read occurs, `count` increments by 1.
- **Illegal Write (`full == 1` and `rd_en == 0`)**:
  - Write is **suppressed**; memory contents are preserved.
  - `wr_ptr` remains unchanged.
  - `overflow` error flag is asserted on the following clock edge.

### 4.3 Read Operation
A read occurs when `rd_en` is high on the rising edge of `clk`:
- **Normal Read (`empty == 0`)**:
  - `rd_data` outputs `mem[rd_ptr]`.
  - `rd_ptr` advances to `(rd_ptr + 1) % DEPTH`.
  - If no concurrent valid write occurs, `count` decrements by 1.
- **Illegal Read (`empty == 1`)**:
  - Read request is rejected.
  - `rd_ptr` remains unchanged.
  - `underflow` error flag is asserted on the following clock edge.

### 4.4 Simultaneous Read and Write Semantics
Simultaneous read and write operations (`wr_en == 1` and `rd_en == 1`) are handled deterministically depending on current occupancy:
1. **Partially Full ($0 < \text{count} < \text{DEPTH}$)**:
   - Both operations execute in the same cycle.
   - One element is written; one element is read.
   - Net change in `count` is **0** (`count` remains constant).
   - Neither `overflow` nor `underflow` is asserted.
2. **At Full Capacity (`count == DEPTH`)**:
   - The simultaneous read operation frees a memory slot, allowing the simultaneous write operation to succeed.
   - `rd_data` receives the word pointed to by `rd_ptr`.
   - `wr_data` is written to `mem[wr_ptr]`.
   - Both `rd_ptr` and `wr_ptr` advance.
   - `count` remains at `DEPTH`.
   - `overflow` is **NOT** asserted.
3. **At Empty State (`count == 0`)**:
   - The read operation cannot be serviced because no valid data exists in the FIFO.
   - `underflow` error is asserted.
   - The write operation proceeds normally: `wr_data` is stored at `mem[wr_ptr]`, `wr_ptr` advances, and `count` transitions to 1.

---

## 5. Threshold & Status Flag Rules

- **Empty Flag**:
  $$\text{empty} = (\text{count} == 0)$$
- **Full Flag**:
  $$\text{full} = (\text{count} == \text{DEPTH})$$
- **Almost Full Flag**:
  $$\text{almost\_full} = (\text{count} \ge (\text{DEPTH} - \text{ALMOST\_FULL\_THRESH}))$$
- **Almost Empty Flag**:
  $$\text{almost\_empty} = (\text{count} \le \text{ALMOST\_EMPTY\_THRESH}) \land (\text{count} > 0)$$

---

## 6. Timing Diagrams

### 6.1 Normal Burst Write, Idle, Burst Read
```
clk         : _/-\_/-\_/-\_/-\_/-\_/-\_/-\_/-\_/-\_/-\_/-\_
rst_n       : ---------------------------------------------
wr_en       : ___/-----\_____/-----\_______________________
wr_data     : ---< D0  >< D1 >< D2 >-----------------------
rd_en       : _____________________________/-----\_________
rd_data     : -----------------------------< D0  >< D1 >---
empty       : ---\_______________________________/---------
full        : _____________________________________________
count       :  0 |  1  |  2  |  3  |  3  |  2  |  1  |  0  
```

### 6.2 Full State with Simultaneous Read & Write
```
clk         : _/-\_/-\_/-\_/-\_/-\_/-\_/-\_/-\_
rst_n       : ---------------------------------
count       : 15 | 16 | 16 | 16 | 15 | 14 | ...
full        : ___/--------------------\________
wr_en       : ___/-----\_____/-----\___________
rd_en       : _________/-----\_________________
overflow    : _________________________________
```

---

## 7. Defect Injection Capability (Compile-Time)

To guarantee that the verification suite detects hardware bugs rather than reporting false-positive passes, the RTL includes compile-time macro injections:

| Defect Injection Macro | Injected Failure Mechanism | Expected Detection Mechanism |
| :--- | :--- | :--- |
| `BUG_INJECT_OVERFLOW` | Disables overflow protection; write pointer increments and overwrites oldest unread data when full. | `test_overflow` detects data corruption in scoreboard and failure to suppress write. |
| `BUG_INJECT_UNDERFLOW_FLAG` | Suppresses `underflow` flag generation during illegal reads when empty. | `test_underflow` detects missing `underflow` assertion. |
| `BUG_INJECT_COUNT_SIMULTANEOUS` | Miscalculates occupancy during simultaneous read/write when full (increments count past `DEPTH`). | `test_simultaneous_rw` triggers SVA `A_COUNT_LIMIT` violation. |
| `BUG_INJECT_ALMOST_FULL` | Uses `<` instead of `>=` for watermark calculation. | `test_almost_flags` detects premature/delayed flag assertions. |
| `BUG_INJECT_RESET_NEGLECT` | Neglects resetting error flags (`overflow`/`underflow`) upon `rst_n` assertion. | `test_reset` detects non-zero error flags post-reset. |
