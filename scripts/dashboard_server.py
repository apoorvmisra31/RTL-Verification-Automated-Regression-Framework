#!/usr/bin/env python3
"""
dashboard_server.py - Primary Application Backend & REST API Server
RTL Verification & Automated Regression Framework

Features:
- Built strictly with the Python 3 Standard Library (ThreadingHTTPServer).
- Serves the interactive dashboard frontend (HTML/CSS/JS).
- Thread-safe background execution manager for single tests and regressions.
- Real-time Server-Sent Events (SSE) log streaming & status polling.
- In-browser VCD waveform parser for interactive digital timing diagrams.
- One-click native desktop GTKWave launcher for macOS & Linux.
- Interactive Defect-Injection Lab orchestrator.
- Input validation and allowlisting (zero arbitrary shell execution).
- Zero external package dependencies.
"""

import argparse
import json
import mimetypes
import os
import re
import shutil
import subprocess
import sys
import threading
import time
import webbrowser
from datetime import datetime, timezone
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse

# Add project root to sys.path
ROOT_DIR = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT_DIR))

# Import existing regression & test functions to maintain 100% parity
from scripts.regression import (
    compile_testbench,
    discover_tests,
    find_tool,
    run_single_test,
    write_csv_summary,
    write_json_summary,
    write_markdown_report,
)

# Allowlisted defect injection macros
VALID_BUG_MACROS = {
    "BUG_INJECT_OVERFLOW": "Disables write protection on full; memory overwritten and overflow masked.",
    "BUG_INJECT_UNDERFLOW_FLAG": "Suppresses underflow error flag generation on illegal reads when empty.",
    "BUG_INJECT_COUNT_SIMULTANEOUS": "Erroneously increments count on simultaneous read/write when full.",
    "BUG_INJECT_ALMOST_FULL": "Inverts condition for almost_full threshold calculation.",
    "BUG_INJECT_RESET_NEGLECT": "Fails to clear error flags during reset.",
}

# Expected failure signatures for deterministic defect verification
EXPECTED_DEFECT_FAILURES = {
    "BUG_INJECT_OVERFLOW": ["test_overflow", "test_random_traffic"],
    "BUG_INJECT_UNDERFLOW_FLAG": ["test_underflow"],
    "BUG_INJECT_COUNT_SIMULTANEOUS": ["test_simultaneous_rw"],
    "BUG_INJECT_ALMOST_FULL": ["test_almost_flags"],
    "BUG_INJECT_RESET_NEGLECT": ["test_reset"],
}

# Test descriptions extracted from test header comments
TEST_METADATA = {
    "test_reset": {
        "title": "Reset & Initialization",
        "category": "Reset",
        "description": "Verifies asynchronous reset assertion, default flag states, stimulus rejection during reset, and post-reset recovery.",
    },
    "test_single_write_read": {
        "title": "Single Write & Read",
        "category": "Directed",
        "description": "Writes 1 word, verifies empty deasserts, reads word, and verifies empty reasserts with zero mismatches.",
    },
    "test_burst_write_read": {
        "title": "Burst Write & Read",
        "category": "Functional",
        "description": "Writes burst of 8 unique sequential words, verifies occupancy, reads all 8 words, and validates FIFO ordering.",
    },
    "test_fifo_full": {
        "title": "FIFO Full Capacity",
        "category": "Boundary",
        "description": "Fills FIFO to maximum depth (16 words), verifies full and almost_full flags assert, and checks single-read recovery.",
    },
    "test_fifo_empty": {
        "title": "FIFO Empty Transition",
        "category": "Boundary",
        "description": "Fills 4 items, drains completely, verifies exact empty flag assertion cycle, and confirms idle stability.",
    },
    "test_simultaneous_rw": {
        "title": "Simultaneous Read/Write",
        "category": "Corner Case",
        "description": "16 cycles of concurrent read and write at count=8, followed by concurrent read/write at full capacity.",
    },
    "test_overflow": {
        "title": "Overflow Protection",
        "category": "Error / Robustness",
        "description": "Attempts 5 illegal writes to full FIFO, verifies overflow error pulse, and proves original memory was unharmed.",
    },
    "test_underflow": {
        "title": "Underflow Protection",
        "category": "Error / Robustness",
        "description": "Attempts 5 illegal reads from empty FIFO, verifies underflow error pulse, and checks normal operation recovery.",
    },
    "test_almost_flags": {
        "title": "Watermark Thresholds",
        "category": "Boundary",
        "description": "Incremental item-by-item fill and drain across almost_empty (count<=2) and almost_full (count>=14) thresholds.",
    },
    "test_random_traffic": {
        "title": "Constrained Random Traffic",
        "category": "Stress",
        "description": "200 cycles of pseudo-random mixed writes, reads, bursts, and idle cycles with repeatable seed control.",
    },
}


class ExecutionManager:
    """Thread-safe manager for background simulation and regression execution."""

    def __init__(self, root_dir: Path):
        self.root_dir = root_dir
        self.sim_dir = root_dir / "sim"
        self.reports_dir = root_dir / "reports"
        self.logs_dir = self.reports_dir / "logs"
        self.waves_dir = root_dir / "waves"

        self.lock = threading.Lock()
        self.active_thread = None
        self.current_process = None
        self.cancelled = False

        # State dictionary
        self.state = {
            "status": "IDLE",  # IDLE, PREPARING, COMPILING, RUNNING, COMPLETED, FAILED, CANCELLED
            "job_type": None,  # "test", "regression", "defect_demo"
            "active_test": None,
            "current_index": 0,
            "total_tests": 0,
            "progress_pct": 0,
            "start_time": None,
            "elapsed_sec": 0.0,
            "log_stream": [],
            "error_message": None,
            "latest_result": None,
            "demo_step": None,
        }
        self.listeners = []  # List of queues or callback functions for SSE

    def get_state(self) -> dict:
        with self.lock:
            st = dict(self.state)
            if st["status"] in ["PREPARING", "COMPILING", "RUNNING"] and st["start_time"]:
                st["elapsed_sec"] = round(time.time() - st["start_time"], 2)
            # Return last 100 log lines to keep payload reasonable
            st["log_stream"] = st["log_stream"][-100:]
            return st

    def emit_log(self, text: str):
        with self.lock:
            self.state["log_stream"].append(text)
        # Notify SSE listeners
        for listener in list(self.listeners):
            try:
                listener(text)
            except Exception:
                pass

    def update_state(self, **kwargs):
        with self.lock:
            for k, v in kwargs.items():
                self.state[k] = v

    def cancel_job(self) -> bool:
        with self.lock:
            if self.state["status"] not in ["PREPARING", "COMPILING", "RUNNING"]:
                return False
            self.cancelled = True
            if self.current_process:
                try:
                    self.current_process.terminate()
                except Exception:
                    pass
            self.state["status"] = "CANCELLED"
            self.state["error_message"] = "Job cancelled by user."
        self.emit_log("[JOB] *** Execution cancelled by user ***")
        return True

    def run_single_test_async(self, test_name: str, seed: int = 42, wave: bool = False, bug_macro: str = None):
        with self.lock:
            if self.state["status"] in ["PREPARING", "COMPILING", "RUNNING"]:
                raise RuntimeError("A verification job is already running. Please wait or cancel it.")
            self.cancelled = False
            self.state.update({
                "status": "PREPARING",
                "job_type": "test",
                "active_test": test_name,
                "current_index": 1,
                "total_tests": 1,
                "progress_pct": 0,
                "start_time": time.time(),
                "elapsed_sec": 0.0,
                "log_stream": [],
                "error_message": None,
                "latest_result": None,
                "demo_step": None,
            })

        def worker():
            try:
                vvp = find_tool("vvp")
                if not vvp:
                    self.update_state(status="FAILED", error_message="Simulator 'vvp' not found.")
                    self.emit_log("[ERROR] 'vvp' executable not found.")
                    return

                self.update_state(status="COMPILING")
                self.emit_log(f"[BUILD] Compiling testbench snapshot (Defect Define: {bug_macro})...")
                ok, msg, code = compile_testbench(self.root_dir, self.sim_dir, bug_macro)
                if not ok or self.cancelled:
                    if not self.cancelled:
                        self.update_state(status="FAILED", error_message=f"Compilation failed: {msg}")
                        self.emit_log(f"[BUILD FAILED] {msg}")
                    return

                binary_path = msg
                self.update_state(status="RUNNING", progress_pct=50)
                self.emit_log(f"[RUN] Executing test: {test_name} (Seed: {seed}, Waveform: {wave})...")

                log_file = self.logs_dir / f"{test_name}.log"
                res = run_single_test(
                    vvp,
                    binary_path,
                    test_name,
                    seed,
                    wave,
                    log_file,
                    timeout_sec=30,
                )

                if self.cancelled:
                    return

                # Read stdout into log stream
                if log_file.exists():
                    with open(log_file, "r") as f:
                        for line in f.readlines():
                            self.emit_log(line.rstrip())

                self.update_state(
                    status="COMPLETED" if res["passed"] else "FAILED",
                    progress_pct=100,
                    latest_result=res,
                )
                status_str = "PASSED" if res["passed"] else "FAILED"
                self.emit_log(f"[DONE] Test {test_name} finished: {status_str} ({res['duration_sec']:.3f}s)")
            except Exception as e:
                self.update_state(status="FAILED", error_message=str(e))
                self.emit_log(f"[FATAL] Unexpected error: {str(e)}")

        t = threading.Thread(target=worker, daemon=True)
        self.active_thread = t
        t.start()

    def run_regression_async(self, test_list: list = None, seed: int = 42, wave: bool = False, bug_macro: str = None):
        with self.lock:
            if self.state["status"] in ["PREPARING", "COMPILING", "RUNNING"]:
                raise RuntimeError("A verification job is already running.")
            self.cancelled = False

            if not test_list:
                test_list = discover_tests(self.root_dir / "tests")

            self.state.update({
                "status": "PREPARING",
                "job_type": "regression",
                "active_test": None,
                "current_index": 0,
                "total_tests": len(test_list),
                "progress_pct": 0,
                "start_time": time.time(),
                "elapsed_sec": 0.0,
                "log_stream": [],
                "error_message": None,
                "latest_result": None,
                "demo_step": None,
            })

        def worker():
            try:
                vvp = find_tool("vvp")
                if not vvp:
                    self.update_state(status="FAILED", error_message="Simulator 'vvp' not found.")
                    return

                self.update_state(status="COMPILING")
                self.emit_log(f"[BUILD] Compiling full regression suite (Defect define: {bug_macro})...")
                ok, msg, code = compile_testbench(self.root_dir, self.sim_dir, bug_macro)
                if not ok or self.cancelled:
                    if not self.cancelled:
                        self.update_state(status="FAILED", error_message=f"Compilation failed: {msg}")
                        self.emit_log(f"[BUILD FAILED] {msg}")
                    return

                binary_path = msg
                self.update_state(status="RUNNING")
                self.emit_log(f"[REGRESSION] Running {len(test_list)} tests sequentially...")

                test_results = []
                for idx, t_name in enumerate(test_list, start=1):
                    if self.cancelled:
                        break

                    pct = int((idx - 1) / len(test_list) * 100)
                    self.update_state(active_test=t_name, current_index=idx, progress_pct=pct)
                    self.emit_log(f"  [{idx}/{len(test_list)}] Launching {t_name}...")

                    log_file = self.logs_dir / f"{t_name}.log"
                    res = run_single_test(
                        vvp,
                        binary_path,
                        t_name,
                        seed,
                        wave,
                        log_file,
                        timeout_sec=30,
                    )
                    test_results.append(res)
                    tag = "PASS" if res["passed"] else "FAIL"
                    self.emit_log(f"  [{idx}/{len(test_list)}] {t_name} -> {tag} ({res['duration_sec']:.3f}s)")

                if self.cancelled:
                    return

                total_duration = time.time() - self.state["start_time"]
                total_count = len(test_results)
                passed_count = sum(1 for t in test_results if t["passed"])
                failed_count = total_count - passed_count
                pass_rate = f"{(passed_count / total_count) * 100:.1f}%" if total_count > 0 else "0.0%"
                overall_status = "PASSED" if failed_count == 0 else "FAILED"

                summary_data = {
                    "timestamp": datetime.now(timezone.utc).isoformat(),
                    "configuration": {
                        "simulator": "Icarus Verilog 13.0 (vvp)",
                        "dut": "sync_fifo",
                        "seed": seed,
                        "wave_dump": wave,
                        "bug_macro": bug_macro,
                    },
                    "summary": {
                        "total_tests": total_count,
                        "passed": passed_count,
                        "failed": failed_count,
                        "pass_rate": pass_rate,
                        "total_duration_sec": round(total_duration, 4),
                        "overall_status": overall_status,
                    },
                    "test_results": test_results,
                }

                write_json_summary(summary_data, self.reports_dir / "regression_summary.json")
                write_csv_summary(summary_data, self.reports_dir / "regression_summary.csv")
                write_markdown_report(summary_data, self.reports_dir / "regression_report.md")

                self.update_state(
                    status="COMPLETED" if overall_status == "PASSED" else "FAILED",
                    progress_pct=100,
                    latest_result=summary_data,
                )
                self.emit_log(f"[REGRESSION COMPLETE] Overall: {overall_status} ({passed_count}/{total_count} Passed in {total_duration:.2f}s)")
            except Exception as e:
                self.update_state(status="FAILED", error_message=str(e))
                self.emit_log(f"[FATAL] Regression failed with error: {str(e)}")

        t = threading.Thread(target=worker, daemon=True)
        self.active_thread = t
        t.start()

    def run_defect_demo_async(self, bug_macro: str = "BUG_INJECT_OVERFLOW"):
        """Run controlled 3-stage defect demonstration."""
        with self.lock:
            if self.state["status"] in ["PREPARING", "COMPILING", "RUNNING"]:
                raise RuntimeError("A verification job is already running.")
            self.cancelled = False
            self.state.update({
                "status": "PREPARING",
                "job_type": "defect_demo",
                "active_test": None,
                "current_index": 0,
                "total_tests": 10,
                "progress_pct": 0,
                "start_time": time.time(),
                "elapsed_sec": 0.0,
                "log_stream": [],
                "error_message": None,
                "latest_result": None,
                "demo_step": "STAGE_1_INJECT",
            })

        def worker():
            try:
                vvp = find_tool("vvp")
                test_list = discover_tests(self.root_dir / "tests")

                # STAGE 1: Inject Defect and Run Regression
                self.emit_log("================================================================================")
                self.emit_log(f"  DEFECT DEMONSTRATION LAB: Testing '{bug_macro}'")
                self.emit_log(f"  Description: {VALID_BUG_MACROS.get(bug_macro, 'Custom defect')}")
                self.emit_log("================================================================================")
                self.update_state(status="COMPILING", demo_step="STAGE_1_INJECT")
                self.emit_log(f"[DEMO STAGE 1] Compiling RTL with injected defect: {bug_macro}...")

                ok, msg, code = compile_testbench(self.root_dir, self.sim_dir, bug_macro)
                if not ok or self.cancelled:
                    self.update_state(status="FAILED", error_message="Demo compilation failed.")
                    return

                binary_path = msg
                self.update_state(status="RUNNING")
                self.emit_log("[DEMO STAGE 1] Running regression to observe defect detection...")

                bug_results = []
                for idx, t_name in enumerate(test_list, start=1):
                    if self.cancelled:
                        return
                    self.update_state(active_test=t_name, current_index=idx, progress_pct=int(idx / 20 * 100))
                    res = run_single_test(vvp, binary_path, t_name, 42, False, self.logs_dir / f"{t_name}.log", 30)
                    bug_results.append(res)
                    tag = "PASS" if res["passed"] else "FAIL (EXPECTED)"
                    self.emit_log(f"  [{idx}/10] {t_name} -> {tag}")

                bug_failed = [t for t in bug_results if not t["passed"]]
                failed_names = [t["test_name"] for t in bug_failed]
                expected = EXPECTED_DEFECT_FAILURES.get(bug_macro, [])

                if len(bug_failed) == 0:
                    self.update_state(
                        status="FAILED",
                        demo_step="STAGE_1_FAILED",
                        error_message=f"Defect demonstration failed: Injected defect '{bug_macro}' was NOT detected by any test."
                    )
                    self.emit_log("--------------------------------------------------------------------------------")
                    self.emit_log(f"[DEMO FAILED] Defect '{bug_macro}' was NOT detected! All tests passed unexpectedly.")
                    self.emit_log("--------------------------------------------------------------------------------")
                    return

                # Verify that expected detector test actually failed
                matched_expected = [t for t in expected if t in failed_names]
                if expected and not matched_expected:
                    self.update_state(
                        status="FAILED",
                        demo_step="STAGE_1_FAILED",
                        error_message=f"Defect demonstration failed: Expected failure in {expected}, but observed {failed_names}."
                    )
                    self.emit_log(f"[DEMO FAILED] Expected test(s) {expected} did not fail. Observed failures: {failed_names}")
                    return

                self.emit_log("--------------------------------------------------------------------------------")
                self.emit_log(f"[DEMO STAGE 1 COMPLETE] Defect '{bug_macro}' was deterministically DETECTED!")
                self.emit_log(f"  Observed {len(bug_failed)} failing test(s): {failed_names}")
                self.emit_log(f"  Verified detector(s): {matched_expected if matched_expected else failed_names}")
                self.emit_log("--------------------------------------------------------------------------------")

                # STAGE 2: Restore Clean Baseline
                time.sleep(0.5)
                self.update_state(demo_step="STAGE_2_RESTORE", status="COMPILING")
                self.emit_log("[DEMO STAGE 2] Restoring clean RTL baseline and compiling clean binary...")
                ok_clean, msg_clean, _ = compile_testbench(self.root_dir, self.sim_dir, None)
                if not ok_clean or self.cancelled:
                    self.update_state(status="FAILED", error_message="Clean restore compilation failed.")
                    return

                clean_binary = msg_clean
                self.update_state(status="RUNNING")
                self.emit_log("[DEMO STAGE 2] Re-running regression on clean baseline...")

                clean_results = []
                clean_failed = []
                for idx, t_name in enumerate(test_list, start=1):
                    if self.cancelled:
                        return
                    self.update_state(active_test=t_name, current_index=idx, progress_pct=50 + int(idx / 20 * 100))
                    res = run_single_test(vvp, clean_binary, t_name, 42, False, self.logs_dir / f"{t_name}.log", 30)
                    clean_results.append(res)
                    if res["passed"]:
                        self.emit_log(f"  [{idx}/10] {t_name} -> PASS")
                    else:
                        clean_failed.append(res)
                        self.emit_log(f"  [{idx}/10] {t_name} -> FAIL (UNEXPECTED ON CLEAN RTL)")

                if len(clean_failed) > 0:
                    self.update_state(
                        status="FAILED",
                        demo_step="STAGE_2_FAILED",
                        error_message=f"Clean baseline verification failed: {len(clean_failed)} test(s) failed on golden RTL."
                    )
                    self.emit_log("================================================================================")
                    self.emit_log(f"  [DEMO FAILED] Clean restoration verification failed! Broken tests: {[t['test_name'] for t in clean_failed]}")
                    self.emit_log("================================================================================")
                    return

                self.emit_log("================================================================================")
                self.emit_log("  DEFECT DEMONSTRATION LAB: VERIFIED & COMPLETED")
                self.emit_log(f"  1. Injected defect '{bug_macro}' caused expected deterministic failure(s): {matched_expected if matched_expected else failed_names}.")
                self.emit_log("  2. Restored clean RTL passed 10/10 verification tests.")
                self.emit_log("================================================================================")

                self.update_state(
                    status="COMPLETED",
                    demo_step="STAGE_3_VERIFIED",
                    progress_pct=100,
                    latest_result={
                        "defect_macro": bug_macro,
                        "detected_failures": failed_names,
                        "clean_passed": len(clean_results),
                    },
                )
            except Exception as e:
                self.update_state(status="FAILED", error_message=str(e))
                self.emit_log(f"[DEMO ERROR] {str(e)}")

        t = threading.Thread(target=worker, daemon=True)
        self.active_thread = t
        t.start()


def parse_vcd_waveform(vcd_path: Path, max_changes_per_signal: int = 400) -> dict:
    """Parse standard VCD file into compact JSON digital waveform structure."""
    if not vcd_path.is_file():
        return {"error": "VCD waveform file not found"}

    signals = {}
    id_to_name = {}
    timescale = "1ns"

    # Relevant signals of interest
    WATCH_NAMES = {
        "clk", "rst_n", "wr_en", "wr_data", "rd_en", "rd_data",
        "full", "empty", "almost_full", "almost_empty",
        "overflow", "underflow", "count", "wr_ptr", "rd_ptr"
    }

    current_time = 0
    in_definitions = True

    try:
        with open(vcd_path, "r") as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue

                if in_definitions:
                    if line.startswith("$timescale"):
                        parts = line.split()
                        if len(parts) >= 2:
                            timescale = parts[1]
                    elif line.startswith("$var"):
                        parts = line.split()
                        # Format: $var <type> <width> <id> <name> [bounds] $end
                        if len(parts) >= 5:
                            width = int(parts[2])
                            s_id = parts[3]
                            s_name = parts[4]
                            # Look for watched signals in DUT or top
                            clean_name = s_name.split("[")[0]
                            if clean_name in WATCH_NAMES:
                                id_to_name[s_id] = {
                                    "name": s_name,
                                    "clean_name": clean_name,
                                    "width": width,
                                    "is_bus": width > 1,
                                }
                                signals[clean_name] = {
                                    "name": s_name,
                                    "width": width,
                                    "is_bus": width > 1,
                                    "transitions": [],
                                }
                    elif line.startswith("$enddefinitions"):
                        in_definitions = False
                    continue

                # Parse Simulation Data
                if line.startswith("#"):
                    try:
                        current_time = int(line[1:])
                    except ValueError:
                        pass
                elif line.startswith("b") or line.startswith("B"):
                    # Bus value change: b0101 ID or b0101 ID
                    parts = line.split()
                    if len(parts) == 2:
                        val_bin = parts[0][1:]
                        s_id = parts[1]
                        if s_id in id_to_name:
                            info = id_to_name[s_id]
                            clean_n = info["clean_name"]
                            # Convert binary to hex if valid
                            try:
                                val_hex = hex(int(val_bin, 2)).upper().replace("0X", "0x")
                            except ValueError:
                                val_hex = val_bin
                            sig_list = signals[clean_n]["transitions"]
                            if len(sig_list) < max_changes_per_signal:
                                sig_list.append({"t": current_time, "v": val_hex})
                elif len(line) >= 2 and line[0] in ["0", "1", "x", "X", "z", "Z"]:
                    val = line[0]
                    s_id = line[1:]
                    if s_id in id_to_name:
                        clean_n = id_to_name[s_id]["clean_name"]
                        sig_list = signals[clean_n]["transitions"]
                        if len(sig_list) < max_changes_per_signal:
                            sig_list.append({"t": current_time, "v": val})

    except Exception as e:
        return {"error": f"Failed to parse VCD: {str(e)}"}

    # Sort signals into standard logical order
    ORDER = [
        "clk", "rst_n", "wr_en", "wr_data", "rd_en", "rd_data",
        "full", "empty", "almost_full", "almost_empty",
        "overflow", "underflow", "count", "wr_ptr", "rd_ptr"
    ]
    sorted_signals = []
    for sig_key in ORDER:
        if sig_key in signals:
            sorted_signals.append(signals[sig_key])

    return {
        "test_name": vcd_path.stem,
        "timescale": timescale,
        "max_time": current_time,
        "signals": sorted_signals,
    }


def launch_gtkwave(vcd_path: Path) -> tuple:
    """Launch GTKWave locally on macOS or Linux."""
    if not vcd_path.is_file():
        return False, f"Waveform file not found at {vcd_path.name}. Run the test with waveform dumping enabled first."

    # On macOS, prioritize launching the native .app bundle via 'open -a'
    # This prevents issues with outdated Perl wrapper scripts (/opt/homebrew/bin/gtkwave) requiring Switch.pm
    if sys.platform == "darwin":
        for app_path in ["/Applications/gtkwave.app", str(Path.home() / "Applications" / "gtkwave.app")]:
            if Path(app_path).exists():
                try:
                    res = subprocess.run(["open", "-a", app_path, str(vcd_path)], capture_output=True, text=True, timeout=5)
                    if res.returncode == 0:
                        return True, f"Opened {vcd_path.name} in GTKWave desktop application."
                    return False, f"macOS 'open' failed: {res.stderr.strip()}"
                except Exception as e:
                    return False, f"Failed to launch GTKWave app: {str(e)}"

        # Try generic open -a gtkwave
        try:
            res = subprocess.run(["open", "-a", "gtkwave", str(vcd_path)], capture_output=True, text=True, timeout=5)
            if res.returncode == 0:
                return True, f"Opened {vcd_path.name} in GTKWave desktop application."
        except Exception:
            pass

    # Linux or fallback CLI binary in PATH
    gtkwave_bin = find_tool("gtkwave")
    if gtkwave_bin:
        try:
            subprocess.Popen([gtkwave_bin, str(vcd_path)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            return True, f"Launched GTKWave ({gtkwave_bin}) with {vcd_path.name} in background."
        except Exception as e:
            return False, f"Failed to launch GTKWave binary: {str(e)}"

    return False, "GTKWave executable not found. Install on macOS with: brew install --cask gtkwave"


class DashboardHandler(BaseHTTPRequestHandler):
    """HTTP Request Handler for Dashboard Web UI and REST API."""

    execution_mgr: ExecutionManager = None
    dashboard_dir: Path = ROOT_DIR / "dashboard"

    def log_message(self, format, *args):
        # Suppress noisy HTTP access logs, keeping terminal clean
        pass

    def send_json_response(self, data, status: int = 200):
        body = json.dumps(data, indent=2).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Cache-Control", "no-cache")
        self.end_headers()
        self.wfile.write(body)

    def send_error_response(self, message: str, status: int = 400):
        self.send_json_response({"error": message, "status": status}, status=status)

    def do_OPTIONS(self):
        # Handle CORS preflight
        self.send_response(HTTPStatus.NO_CONTENT)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.end_headers()

    def do_GET(self):
        parsed = urlparse(self.path)
        path = parsed.path
        query = parse_qs(parsed.query)

        # ---------------------------------------------------------------------
        # REST API Endpoints
        # ---------------------------------------------------------------------
        if path == "/api/status":
            iverilog_path = find_tool("iverilog")
            vvp_path = find_tool("vvp")
            gtkwave_path = find_tool("gtkwave") or ("/Applications/gtkwave.app" if Path("/Applications/gtkwave.app").exists() else "")

            # Simulator version
            sim_version = "Unknown"
            if iverilog_path:
                try:
                    out = subprocess.check_output([iverilog_path, "-V"], text=True, timeout=2)
                    m = re.search(r"Icarus Verilog version\s+([0-9.]+)", out)
                    if m:
                        sim_version = f"Icarus Verilog {m.group(1)}"
                    else:
                        sim_version = out.splitlines()[0]
                except Exception:
                    sim_version = "Icarus Verilog"

            data = {
                "system": {
                    "platform": sys.platform,
                    "python_version": sys.version.split()[0],
                    "simulator": sim_version,
                    "iverilog_path": iverilog_path,
                    "vvp_path": vvp_path,
                    "gtkwave_path": gtkwave_path,
                    "simulator_ready": bool(iverilog_path and vvp_path),
                },
                "project": {
                    "root_dir": str(ROOT_DIR),
                    "dut": "sync_fifo",
                    "data_width": 8,
                    "depth": 16,
                    "almost_full_thresh": 2,
                    "almost_empty_thresh": 2,
                },
                "job": self.execution_mgr.get_state(),
            }
            self.send_json_response(data)
            return

        if path == "/api/tests":
            discovered = discover_tests(ROOT_DIR / "tests")
            tests_info = []
            for t_name in discovered:
                meta = TEST_METADATA.get(t_name, {
                    "title": t_name.replace("_", " ").title(),
                    "category": "Verification",
                    "description": "Functional verification test case.",
                })
                log_p = ROOT_DIR / "reports" / "logs" / f"{t_name}.log"
                wave_p = ROOT_DIR / "waves" / f"{t_name}.vcd"

                tests_info.append({
                    "name": t_name,
                    "title": meta["title"],
                    "category": meta["category"],
                    "description": meta["description"],
                    "has_log": log_p.is_file(),
                    "has_wave": wave_p.is_file(),
                })
            self.send_json_response({"tests": tests_info, "total": len(tests_info)})
            return

        if path == "/api/job-status":
            self.send_json_response(self.execution_mgr.get_state())
            return

        if path == "/api/job-stream":
            # Server-Sent Events (SSE) stream for live updates
            self.send_response(HTTPStatus.OK)
            self.send_header("Content-Type", "text/event-stream")
            self.send_header("Cache-Control", "no-cache")
            self.send_header("Connection", "keep-alive")
            self.send_header("Access-Control-Allow-Origin", "*")
            self.end_headers()

            queue = []
            lock = threading.Lock()

            def sse_cb(msg):
                with lock:
                    queue.append(msg)

            self.execution_mgr.listeners.append(sse_cb)
            try:
                # Send initial state
                initial_data = json.dumps(self.execution_mgr.get_state())
                self.wfile.write(f"event: state\ndata: {initial_data}\n\n".encode("utf-8"))
                self.wfile.flush()

                while True:
                    time.sleep(0.1)
                    with lock:
                        items = list(queue)
                        queue.clear()
                    for item in items:
                        payload = json.dumps({"log": item})
                        self.wfile.write(f"event: log\ndata: {payload}\n\n".encode("utf-8"))
                    # Send state update every second
                    st_json = json.dumps(self.execution_mgr.get_state())
                    self.wfile.write(f"event: state\ndata: {st_json}\n\n".encode("utf-8"))
                    self.wfile.flush()
            except (BrokenPipeError, ConnectionResetError):
                pass
            finally:
                if sse_cb in self.execution_mgr.listeners:
                    self.execution_mgr.listeners.remove(sse_cb)
            return

        if path == "/api/reports/latest":
            json_file = ROOT_DIR / "reports" / "regression_summary.json"
            if json_file.is_file():
                try:
                    with open(json_file, "r") as f:
                        self.send_json_response(json.load(f))
                        return
                except Exception as e:
                    self.send_error_response(f"Failed to read report: {str(e)}")
                    return
            self.send_json_response({"error": "No regression summary found", "summary": None})
            return

        if path == "/api/reports/file":
            ftype = query.get("type", ["json"])[0]
            if ftype == "csv":
                target = ROOT_DIR / "reports" / "regression_summary.csv"
                ctype = "text/csv"
            elif ftype == "md":
                target = ROOT_DIR / "reports" / "regression_report.md"
                ctype = "text/markdown; charset=utf-8"
            else:
                target = ROOT_DIR / "reports" / "regression_summary.json"
                ctype = "application/json"

            if not target.is_file():
                self.send_error_response(f"Report file {target.name} not found.", 404)
                return

            with open(target, "rb") as f:
                content = f.read()
            self.send_response(200)
            self.send_header("Content-Type", ctype)
            self.send_header("Content-Length", str(len(content)))
            self.send_header("Access-Control-Allow-Origin", "*")
            self.end_headers()
            self.wfile.write(content)
            return

        if path.startswith("/api/logs/"):
            test_name = path[len("/api/logs/"):].strip()
            # Validate test_name safe alphanumeric
            if not re.match(r"^[a-zA-Z0-9_]+$", test_name):
                self.send_error_response("Invalid test name", 400)
                return
            log_file = ROOT_DIR / "reports" / "logs" / f"{test_name}.log"
            if not log_file.is_file():
                self.send_error_response(f"Log file for '{test_name}' not found.", 404)
                return
            with open(log_file, "r", encoding="utf-8", errors="replace") as f:
                log_text = f.read()
            self.send_json_response({"test_name": test_name, "log": log_text})
            return

        if path.startswith("/api/waves/parse"):
            test_name = query.get("test", [""])[0]
            if not test_name or not re.match(r"^[a-zA-Z0-9_]+$", test_name):
                self.send_error_response("Missing or invalid test query parameter", 400)
                return
            vcd_path = ROOT_DIR / "waves" / f"{test_name}.vcd"
            if not vcd_path.is_file():
                self.send_error_response(f"Waveform waves/{test_name}.vcd not found. Run test with waveform enabled first.", 404)
                return
            wave_data = parse_vcd_waveform(vcd_path)
            self.send_json_response(wave_data)
            return

        if path == "/api/defects":
            # List available defect injection macros
            self.send_json_response({"defects": VALID_BUG_MACROS})
            return

        # ---------------------------------------------------------------------
        # Static Frontend File Serving
        # ---------------------------------------------------------------------
        if path == "/" or path == "":
            rel_path = "index.html"
        else:
            rel_path = path.lstrip("/")

        target_file = self.dashboard_dir / rel_path
        # Prevent directory traversal
        try:
            target_file.resolve().relative_to(self.dashboard_dir.resolve())
        except ValueError:
            self.send_error_response("Access Denied", 403)
            return

        if target_file.is_file():
            ctype, _ = mimetypes.guess_type(str(target_file))
            if not ctype:
                ctype = "application/octet-stream"
            with open(target_file, "rb") as f:
                content = f.read()
            self.send_response(200)
            self.send_header("Content-Type", ctype)
            self.send_header("Content-Length", str(len(content)))
            self.send_header("Access-Control-Allow-Origin", "*")
            self.end_headers()
            self.wfile.write(content)
        else:
            self.send_error_response("File Not Found", 404)

    def do_POST(self):
        parsed = urlparse(self.path)
        path = parsed.path

        # Read JSON body
        content_len = int(self.headers.get("Content-Length", 0))
        body = {}
        if content_len > 0:
            raw_body = self.rfile.read(content_len)
            try:
                body = json.loads(raw_body.decode("utf-8"))
            except Exception:
                self.send_error_response("Invalid JSON payload", 400)
                return

        # ---------------------------------------------------------------------
        # Run Single Test
        # ---------------------------------------------------------------------
        if path == "/api/run-test":
            test_name = body.get("test_name") or body.get("test")
            seed = int(body.get("seed", 42))
            wave = bool(body.get("wave", False))
            bug = body.get("bug_macro") or body.get("bug")

            if not test_name or not re.match(r"^[a-zA-Z0-9_]+$", test_name):
                self.send_error_response("Invalid test_name", 400)
                return

            if bug and bug not in VALID_BUG_MACROS:
                self.send_error_response(f"Invalid bug_macro. Must be one of: {list(VALID_BUG_MACROS.keys())}", 400)
                return

            try:
                self.execution_mgr.run_single_test_async(test_name, seed, wave, bug)
                self.send_json_response({"message": f"Started test '{test_name}'", "status": "STARTED"})
            except RuntimeError as e:
                self.send_error_response(str(e), 409)
            return

        # ---------------------------------------------------------------------
        # Run Full Regression
        # ---------------------------------------------------------------------
        if path == "/api/run-regression":
            tests = body.get("tests")
            seed = int(body.get("seed", 42))
            wave = bool(body.get("wave", False))
            bug = body.get("bug_macro")

            if tests and not isinstance(tests, list):
                self.send_error_response("tests must be a list of strings", 400)
                return

            if bug and bug not in VALID_BUG_MACROS:
                self.send_error_response(f"Invalid bug_macro: {bug}", 400)
                return

            try:
                self.execution_mgr.run_regression_async(tests, seed, wave, bug)
                self.send_json_response({"message": "Started regression suite", "status": "STARTED"})
            except RuntimeError as e:
                self.send_error_response(str(e), 409)
            return

        # ---------------------------------------------------------------------
        # Run Defect Demo
        # ---------------------------------------------------------------------
        if path == "/api/defect-demo/run":
            bug = body.get("bug_macro", "BUG_INJECT_OVERFLOW")
            if bug not in VALID_BUG_MACROS:
                self.send_error_response(f"Invalid bug_macro: {bug}", 400)
                return

            try:
                self.execution_mgr.run_defect_demo_async(bug)
                self.send_json_response({"message": f"Started defect demo for {bug}", "status": "STARTED"})
            except RuntimeError as e:
                self.send_error_response(str(e), 409)
            return

        # ---------------------------------------------------------------------
        # Cancel Running Job
        # ---------------------------------------------------------------------
        if path == "/api/cancel-job":
            cancelled = self.execution_mgr.cancel_job()
            self.send_json_response({"cancelled": cancelled})
            return

        # ---------------------------------------------------------------------
        # Open Waveform in GTKWave Desktop
        # ---------------------------------------------------------------------
        if path == "/api/waves/open":
            test_name = body.get("test_name")
            if not test_name or not re.match(r"^[a-zA-Z0-9_]+$", test_name):
                self.send_error_response("Invalid test_name", 400)
                return

            vcd_path = ROOT_DIR / "waves" / f"{test_name}.vcd"
            ok, msg = launch_gtkwave(vcd_path)
            if ok:
                self.send_json_response({"success": True, "message": msg})
            else:
                self.send_error_response(msg, 404)
            return

        # ---------------------------------------------------------------------
        # Clean Workspace
        # ---------------------------------------------------------------------
        if path == "/api/workspace/clean":
            try:
                subprocess.run(["make", "clean"], cwd=ROOT_DIR, capture_output=True, timeout=10)
                self.send_json_response({"success": True, "message": "Workspace cleaned successfully."})
            except Exception as e:
                self.send_error_response(f"Clean failed: {str(e)}", 500)
            return

        self.send_error_response("Unknown API endpoint", 404)


def find_free_port(start_port: int = 8080) -> int:
    """Find available TCP port starting from start_port."""
    import socket
    port = start_port
    while port < start_port + 100:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            if s.connect_ex(("127.0.0.1", port)) != 0:
                return port
        port += 1
    return start_port


def main():
    is_deployed = bool(os.environ.get("RENDER") or os.environ.get("PORT"))
    default_port = int(os.environ["PORT"]) if os.environ.get("PORT", "").isdigit() else 8080

    parser = argparse.ArgumentParser(description="Launch Verification Framework Web Dashboard")
    parser.add_argument("--port", type=int, default=default_port, help=f"Port to bind dashboard server (default: {default_port})")
    parser.add_argument("--no-browser", action="store_true", help="Do not open web browser automatically")
    args = parser.parse_args()

    port = args.port if is_deployed else find_free_port(args.port)
    host = "0.0.0.0" if is_deployed else "127.0.0.1"
    server_addr = (host, port)

    # Initialize execution manager
    mgr = ExecutionManager(ROOT_DIR)
    DashboardHandler.execution_mgr = mgr

    httpd = ThreadingHTTPServer(server_addr, DashboardHandler)
    url = f"http://{host}:{port}"

    print("=" * 80)
    print("   RTL VERIFICATION & AUTOMATED REGRESSION FRAMEWORK DASHBOARD")
    print("=" * 80)
    print(f"  Primary Control Surface : {url}")
    print(f"  Project Root             : {ROOT_DIR}")
    print(f"  Simulator                : {find_tool('iverilog') or 'NOT FOUND'}")
    print(f"  Runtime Engine           : {find_tool('vvp') or 'NOT FOUND'}")
    print("=" * 80)
    print("  Press Ctrl+C to stop the dashboard server.")
    print("=" * 80 + "\n")

    if not args.no_browser and not is_deployed:
        def open_browser():
            time.sleep(0.8)
            webbrowser.open(url)
        threading.Thread(target=open_browser, daemon=True).start()

    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print("\n[SHUTDOWN] Stopping dashboard server...")
        httpd.shutdown()
        sys.exit(0)


if __name__ == "__main__":
    main()
