#!/usr/bin/env python3
"""
run_test.py - Single Test Runner for Synchronous FIFO Verification Environment

Features:
- Toolchain discovery (PATH and /opt/homebrew/bin for macOS).
- Optional compilation with or without defect-injection defines.
- Simulation execution via vvp with runtime plusargs (+TESTNAME, +SEED, +DUMP_WAVE).
- Real-time stdout capture and log generation in reports/logs/<test>.log.
- Deterministic PASS/FAIL signature parsing (scoreboard mismatches, assertions, timeouts).
- Standardized process return codes:
    0 = PASS
    1 = TEST FUNCTIONAL / ASSERTION / SCOREBOARD FAILURE
    2 = COMPILATION ERROR
    3 = TIMEOUT
    4 = TOOLCHAIN NOT FOUND
"""

import argparse
import os
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path


def find_tool(tool_name: str) -> str:
    """Locate tool in PATH or common macOS Homebrew locations."""
    path = shutil.which(tool_name)
    if path:
        return path
    
    mac_homebrew_path = Path("/opt/homebrew/bin") / tool_name
    if mac_homebrew_path.is_file() and os.access(mac_homebrew_path, os.X_OK):
        return str(mac_homebrew_path)
    
    usr_local_path = Path("/usr/local/bin") / tool_name
    if usr_local_path.is_file() and os.access(usr_local_path, os.X_OK):
        return str(usr_local_path)
        
    return ""


def compile_testbench(root_dir: Path, sim_dir: Path, bug_macro: str = None) -> tuple:
    """Compile RTL and Testbench using iverilog."""
    iverilog = find_tool("iverilog")
    if not iverilog:
        return False, "Error: 'iverilog' compiler executable not found in PATH or Homebrew directories.", 4

    sim_dir.mkdir(parents=True, exist_ok=True)
    out_binary = sim_dir / ("tb_top_" + (bug_macro if bug_macro else "clean") + ".vvp")

    cmd = [
        iverilog,
        "-g2012",
        "-Wall",
        "-I", str(root_dir / "rtl"),
        "-I", str(root_dir / "tb"),
        "-I", str(root_dir / "tests"),
        "-o", str(out_binary),
    ]

    if bug_macro:
        cmd.append(f"-D{bug_macro}")

    sources = [
        root_dir / "rtl" / "sync_fifo.sv",
        root_dir / "tb" / "fifo_pkg.sv",
        root_dir / "tb" / "fifo_driver.sv",
        root_dir / "tb" / "fifo_scoreboard.sv",
        root_dir / "tb" / "fifo_assertions.sv",
        root_dir / "tb" / "fifo_monitor.sv",
        root_dir / "tb" / "tb_top.sv",
    ]

    for src in sources:
        if not src.exists():
            return False, f"Missing source file: {src}", 2
        cmd.append(str(src))

    try:
        proc = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=60)
        if proc.returncode != 0:
            return False, f"Compilation failed:\n{proc.stdout}", 2
        return True, str(out_binary), 0
    except subprocess.TimeoutExpired:
        return False, "Compilation timed out after 60 seconds.", 3
    except Exception as e:
        return False, f"Unexpected compilation error: {str(e)}", 2


def run_simulation(
    vvp_binary: str,
    test_name: str,
    seed: int,
    dump_wave: bool,
    log_file: Path,
    timeout_sec: int,
) -> tuple:
    """Run simulation binary using vvp and record log."""
    vvp = find_tool("vvp")
    if not vvp:
        return False, "Error: 'vvp' simulator runtime not found.", 4, 0.0, {}

    cmd = [vvp, vvp_binary, f"+TESTNAME={test_name}", f"+SEED={seed}"]
    if dump_wave:
        cmd.append("+DUMP_WAVE=1")

    log_file.parent.mkdir(parents=True, exist_ok=True)

    start_time = time.time()
    try:
        proc = subprocess.run(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            timeout=timeout_sec,
        )
        duration = time.time() - start_time
        stdout = proc.stdout
        exit_code = proc.returncode
    except subprocess.TimeoutExpired as te:
        duration = time.time() - start_time
        stdout = (te.stdout or "") + f"\n*** FATAL: Simulator process timed out after {timeout_sec} seconds! ***\n"
        with open(log_file, "w") as f:
            f.write(stdout)
        return False, "Simulation process timed out.", 3, duration, {"timeout": True}

    with open(log_file, "w") as f:
        f.write(stdout)

    # Parse log for verification metrics
    metrics = {
        "pass_signature": bool(re.search(rf"=== TEST PASSED:\s+{re.escape(test_name)}\s+===", stdout)),
        "fail_signature": bool(re.search(r"=== TEST FAILED", stdout)),
        "scoreboard_mismatches": len(re.findall(r"Scoreboard: Data MISMATCH", stdout)),
        "flag_errors": len(re.findall(r"Scoreboard: .* MISMATCH", stdout)),
        "assertion_failures": len(re.findall(r"ASSERTION FAILED|failed:", stdout)),
        "exit_code": exit_code,
    }

    if metrics["pass_signature"] and exit_code == 0:
        return True, "Test PASSED", 0, duration, metrics
    else:
        reason = "Test FAILED"
        if metrics["scoreboard_mismatches"] > 0:
            reason += f" ({metrics['scoreboard_mismatches']} data mismatch(es))"
        if metrics["assertion_failures"] > 0:
            reason += f" ({metrics['assertion_failures']} assertion failure(s))"
        if exit_code != 0 and not metrics["fail_signature"]:
            reason += f" (Process exited with non-zero code {exit_code})"
        return False, reason, 1, duration, metrics


def main():
    parser = argparse.ArgumentParser(description="Run single verification test for sync_fifo")
    parser.add_argument("--test", required=True, help="Name of the test to execute (e.g. test_reset)")
    parser.add_argument("--seed", type=int, default=42, help="Random seed (default: 42)")
    parser.add_argument("--wave", action="store_true", help="Enable VCD waveform generation")
    parser.add_argument("--bug", default=None, help="Compile-time defect injection macro (e.g. BUG_INJECT_OVERFLOW)")
    parser.add_argument("--timeout", type=int, default=30, help="Simulation timeout in seconds (default: 30)")
    parser.add_argument("--sim-dir", default="sim", help="Directory for compiled simulation binaries")
    parser.add_argument("--out-dir", default="reports/logs", help="Directory for log files")
    parser.add_argument("--waves-dir", default="waves", help="Directory for waveform output")
    parser.add_argument("--force-compile", action="store_true", help="Force recompilation even if binary exists")
    args = parser.parse_args()

    root_dir = Path(__file__).resolve().parent.parent
    sim_dir = root_dir / args.sim_dir
    log_dir = root_dir / args.out_dir
    waves_dir = root_dir / args.waves_dir

    if args.wave:
        waves_dir.mkdir(parents=True, exist_ok=True)

    # 1. Compile or find existing binary
    binary_name = "tb_top_" + (args.bug if args.bug else "clean") + ".vvp"
    binary_path = sim_dir / binary_name

    if args.force_compile or not binary_path.exists():
        print(f"[BUILD] Compiling testbench snapshot (Bug define: {args.bug})...")
        success, msg, code = compile_testbench(root_dir, sim_dir, args.bug)
        if not success:
            print(f"[BUILD ERROR] {msg}")
            sys.exit(code)
        binary_path = Path(msg)

    # 2. Run simulation
    log_file = log_dir / f"{args.test}.log"
    print(f"[RUN] Executing {args.test} (Seed: {args.seed}, Wave: {args.wave})...")
    success, summary, exit_code, duration, metrics = run_simulation(
        str(binary_path),
        args.test,
        args.seed,
        args.wave,
        log_file,
        args.timeout,
    )

    status_tag = "\033[92mPASS\033[0m" if success else "\033[91mFAIL\033[0m"
    print(f"[{status_tag}] {args.test} ({duration:.3f}s) - {summary}")
    print(f"[LOG] Log saved to {log_file}")
    if args.wave:
        wave_file = waves_dir / f"{args.test}.vcd"
        print(f"[WAVE] Waveform saved to {wave_file}")

    sys.exit(exit_code)


if __name__ == "__main__":
    main()
