# Troubleshooting & Diagnostic Guide

A comprehensive troubleshooting reference for the **RTL Verification & Automated Regression Studio**, covering local environment setup, dashboard operations, simulator diagnostics, and waveform visualization.

---

## 1. Dashboard Launch & Networking Diagnostics

### Symptom: `Address already in use` or Port 8080 Conflict
```text
OSError: [Errno 48] Address already in use
```
- **Cause**: Another service on your workstation (e.g. an existing web server, proxy, or Docker container) is actively using port `8080`.
- **Automatic Resolution**: The dashboard server (`dashboard_server.py`) includes built-in port hunting. If port `8080` is busy, it automatically increments and binds to the next free port (`8081`, `8082`, etc.).
- **Manual Custom Port**: You can explicitly designate an alternative port:
  ```bash
  python3 scripts/dashboard_server.py --port 9000
  ```

### Symptom: `Launch_Dashboard.command` Shows Permission Denied on macOS
- **Cause**: The executable permission bit was not set on the script.
- **Resolution**:
  ```bash
  chmod +x Launch_Dashboard.command launch_dashboard.sh
  ```
  Once set, double-clicking `Launch_Dashboard.command` in macOS Finder will launch the studio immediately.

### Symptom: Dashboard Shows "Disconnected / Connection Refused"
- **Cause**: The background server process was terminated or stopped.
- **Resolution**: Re-launch the server using `./launch_dashboard.sh` or `make dashboard`. Verify the process is running locally:
  ```bash
  lsof -i :8080
  ```

---

## 2. Hardware Simulator (`iverilog` / `vvp`) Diagnostics

### Symptom: Simulator Status Shows "NOT FOUND" in Dashboard
- **Cause**: The `iverilog` and `vvp` executables are not located within your environment `PATH`.
- **Resolution**:
  - **macOS (Apple Silicon M1/M2/M3/M4)**: Homebrew packages are located in `/opt/homebrew/bin`. Verify installation:
    ```bash
    brew install icarus-verilog
    ```
    Ensure your shell configuration (`~/.zshrc`) contains:
    ```bash
    eval "$(/opt/homebrew/bin/brew shellenv)"
    ```
  - **Ubuntu / Debian Linux**:
    ```bash
    sudo apt-get update && sudo apt-get install iverilog
    ```
  - **Verification**: Navigate to the **System Health** panel in the dashboard to confirm detected paths for both `iverilog` and `vvp`.

### Symptom: Elaboration or Syntax Error during Simulation
```text
syntax error in SystemVerilog source
```
- **Cause**: Icarus Verilog defaults to older Verilog-1995/2001 mode unless instructed.
- **Resolution**: The framework automatically enforces `-g2012` flag across all compilations. If compiling manually, ensure `-g2012` is included:
  ```bash
  iverilog -g2012 -Wall -I rtl -I tb -I tests -o sim/tb_top.vvp tb/tb_top.sv rtl/sync_fifo.sv
  ```

---

## 3. Waveform Debugger Diagnostics

### Symptom: In-Browser Waveform Canvas is Blank
- **Cause**: The test was executed without the waveform dumping flag enabled (`+DUMP_WAVE=1`).
- **Resolution**:
  1. Open the **Test Catalog** in the dashboard.
  2. Click **Configure & Run** on the target test card.
  3. Ensure the **"Dump Waveforms (.vcd)"** checkbox is ticked.
  4. Click **Run Test**.
  5. Once completed, navigate to the **Waveforms** tab and select the test from the dropdown list.

### Symptom: GTKWave Does Not Open when Clicking "Launch GTKWave"
- **Cause**: GTKWave is not installed or blocked by macOS Gatekeeper security policies.
- **Resolution**:
  1. **Install GTKWave**:
     - **macOS**: `brew install --cask gtkwave`
     - **Linux**: `sudo apt-get install gtkwave`
  2. **macOS Gatekeeper First Launch**:
     If macOS blocks opening GTKWave with an "unidentified developer" prompt:
     - Open **System Settings -> Privacy & Security**.
     - Scroll to the Security section.
     - Click **Open Anyway** next to GTKWave.
  3. **Direct File Access**:
     Waveform `.vcd` files are always generated in the `waves/` directory:
     ```bash
     open -a gtkwave waves/test_burst_write_read.vcd
     ```
     You can also view these files with modern VSCode extensions such as **WaveTrace** or **Surfer**.

---

## 4. Defect-Injection Lab Diagnostics

### Symptom: Clean Regression Fails after Running Defect Lab
- **Cause**: A previous simulation was forcibly killed mid-execution, leaving the injected compiler define active or the workspace binary stale.
- **Resolution**:
  1. Open the **System Health** panel in the dashboard.
  2. Click the **"Purge Build Artifacts & Logs"** button.
  3. Alternatively, trigger a clean compile from the **Regression Suite** panel.
  4. In terminal: `make clean && make regression`.

---

## 5. Python Runtime Diagnostics

### Symptom: `No module named ...`
- **Cause**: Python is running in a misconfigured virtual environment or calling an incompatible interpreter.
- **Resolution**:
  The entire framework—including the web dashboard server, REST API, regression runner, and report generator—is built **strictly using the Python 3 Standard Library**. It requires **zero** third-party packages (`no pip install`, `no flask`, `no npm`, `no node`).
  Verify your interpreter version:
  ```bash
  python3 --version
  ```
  Python 3.8+ (Python 3.9, 3.10, 3.11, 3.12, 3.13) is fully supported.
