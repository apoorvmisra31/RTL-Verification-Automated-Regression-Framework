# Troubleshooting Guide

## 1. Missing Tools / Command Not Found

### Symptom
```text
zsh: command not found: iverilog
```
or
```text
zsh: command not found: vvp
```

### Root Cause
`iverilog` is either not installed or Homebrew's binary directory is not in your current shell session's `PATH`.

### Solution
1. On Apple Silicon Macs (M1/M2/M3/M4), Homebrew installs into `/opt/homebrew/bin`. Verify that Homebrew is installed:
   ```bash
   /opt/homebrew/bin/brew --version
   ```
2. If Homebrew is installed but not in your `PATH`, export it:
   ```bash
   export PATH="/opt/homebrew/bin:$PATH"
   ```
   To make this permanent, add it to your `~/.zshrc`:
   ```bash
   echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zshrc
   ```
3. If `iverilog` is not yet installed:
   ```bash
   brew install icarus-verilog
   ```
4. Verify installation:
   ```bash
   iverilog -V
   vvp -V
   ```

---

## 2. GTKWave Issues on macOS

### Symptom
`gtkwave` command does not open or macOS reports an untrusted developer warning.

### Solution
1. Install GTKWave using Homebrew:
   ```bash
   brew install --cask gtkwave
   ```
2. If macOS Gatekeeper blocks opening GTKWave on first launch, open **System Settings -> Privacy & Security**, scroll down to the Security section, and click **Open Anyway** next to GTKWave.
3. Alternatively, open generated `.vcd` files using the `gtkwave` binary directly:
   ```bash
   open -a gtkwave waves/test_single_write_read.vcd
   ```
   Or use any modern waveform viewer such as VSCode WaveTrace / Surfer.

---

## 3. Python Execution Issues

### Symptom
```text
/usr/bin/python3: No module named ...
```

### Solution
The entire automation suite (scripts `run_test.py`, `regression.py`, `generate_report.py`) is written strictly with the **Python 3 Standard Library** (`argparse`, `json`, `csv`, `subprocess`, `pathlib`, `dataclasses`, `time`). It requires **zero** third-party packages.
If you encounter module errors, verify you are invoking standard Python 3.8+:
```bash
python3 --version
```

---

## 4. Simulator Compilation Warnings or Errors

### Symptom
```text
syntax error in SystemVerilog source
```

### Solution
Always ensure the `-g2012` flag is supplied to `iverilog`:
```bash
iverilog -g2012 -Wall -I rtl -I tb -I tests -o sim/tb_top.vvp ...
```
The Makefile and Python runner automatically pass this flag.

---

## 5. Cleaning Build and Output Artifacts

If the build directory enters an inconsistent state after aborting a test or switching branches:
```bash
make clean
```
This removes:
- `sim/*.vvp` (compiled simulation binaries)
- `reports/logs/*.log` (test execution logs)
- `reports/regression_summary.json` and `reports/regression_summary.csv`
- `waves/*.vcd` (waveform dumps)
