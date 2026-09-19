#!/usr/bin/env python3
"""
regression.py - Automated Regression Harness for Synchronous FIFO Verification

Features:
- Dynamic discovery of test cases from tests/ directory.
- Batch compilation with optional defect injection flags.
- Sequential test execution with per-test timeout and watchdog.
- Generation of machine-readable reports:
    - reports/regression_summary.json
    - reports/regression_summary.csv
- Generation of human-readable Markdown summary:
    - reports/regression_report.md
- Colored terminal status dashboard.
- Exit code propagation for CI/CD automation:
    0 = 100% Tests Passed
    1 = One or more tests failed
    2 = Compilation failure
"""

import argparse
import csv
import json
import os
import re
import shutil
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path


def find_tool(tool_name: str) -> str:
    """Locate tool in PATH or macOS Homebrew directories."""
    path = shutil.which(tool_name)
    if path:
        return path
    for p in ["/opt/homebrew/bin", "/usr/local/bin"]:
        cand = Path(p) / tool_name
        if cand.is_file() and os.access(cand, os.X_OK):
            return str(cand)
    return ""


def discover_tests(tests_dir: Path) -> list:
    """Discover all test files in tests/ directory matching test_*.sv."""
    tests = []
    for f in sorted(tests_dir.glob("test_*.sv")):
        if f.name == "test_base.sv":
            continue
        test_name = f.stem
        tests.append(test_name)
    return tests


def compile_testbench(root_dir: Path, sim_dir: Path, bug_macro: str = None) -> tuple:
    """Compile RTL and Testbench using iverilog."""
    iverilog = find_tool("iverilog")
    if not iverilog:
        return False, "Error: 'iverilog' compiler executable not found.", 2

    sim_dir.mkdir(parents=True, exist_ok=True)
    binary_name = "tb_top_" + (bug_macro if bug_macro else "clean") + ".vvp"
    out_binary = sim_dir / binary_name

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
        return False, "Compilation timed out after 60 seconds.", 2
    except Exception as e:
        return False, f"Compilation error: {str(e)}", 2


def run_single_test(
    vvp_path: str,
    binary_path: str,
    test_name: str,
    seed: int,
    dump_wave: bool,
    log_file: Path,
    timeout_sec: int,
) -> dict:
    """Execute one test and parse log output."""
    cmd = [vvp_path, binary_path, f"+TESTNAME={test_name}", f"+SEED={seed}"]
    if dump_wave:
        cmd.append("+DUMP_WAVE=1")

    log_file.parent.mkdir(parents=True, exist_ok=True)
    start_t = time.time()

    try:
        proc = subprocess.run(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            timeout=timeout_sec,
        )
        duration = time.time() - start_t
        stdout = proc.stdout
        exit_code = proc.returncode
        timed_out = False
    except subprocess.TimeoutExpired as te:
        duration = time.time() - start_t
        stdout = (te.stdout or "") + f"\n*** FATAL: Simulator process timed out after {timeout_sec}s! ***\n"
        exit_code = 124
        timed_out = True

    with open(log_file, "w") as f:
        f.write(stdout)

    pass_sig = bool(re.search(rf"=== TEST PASSED:\s+{re.escape(test_name)}\s+===", stdout))
    fail_sig = bool(re.search(r"=== TEST FAILED", stdout))
    mismatches = len(re.findall(r"Scoreboard: Data MISMATCH", stdout))
    state_errors = len(re.findall(r"Scoreboard: .* MISMATCH", stdout))
    assertion_fails = len(re.findall(r"ASSERTION FAILED|failed:", stdout))

    passed = pass_sig and (exit_code == 0) and not timed_out

    details = "PASSED"
    if not passed:
        if timed_out:
            details = f"TIMEOUT (exceeded {timeout_sec}s)"
        elif mismatches > 0:
            details = f"{mismatches} data mismatch(es)"
        elif assertion_fails > 0:
            details = f"{assertion_fails} assertion failure(s)"
        elif state_errors > 0:
            details = f"{state_errors} state/flag mismatch(es)"
        elif exit_code != 0:
            details = f"Exit code {exit_code}"
        else:
            details = "Unknown failure"

    return {
        "test_name": test_name,
        "passed": passed,
        "status": "PASS" if passed else "FAIL",
        "duration_sec": round(duration, 4),
        "data_mismatches": mismatches,
        "state_errors": state_errors,
        "assertion_failures": assertion_fails,
        "exit_code": exit_code,
        "details": details,
        "log_path": str(log_file),
    }


def write_json_summary(results: dict, out_file: Path):
    """Write structured regression summary to JSON."""
    out_file.parent.mkdir(parents=True, exist_ok=True)
    with open(out_file, "w") as f:
        json.dump(results, f, indent=2)


def write_csv_summary(results: dict, out_file: Path):
    """Write CSV table of regression results."""
    out_file.parent.mkdir(parents=True, exist_ok=True)
    with open(out_file, "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["Test Name", "Status", "Duration (s)", "Data Mismatches", "State Errors", "Assertion Failures", "Details", "Log File"])
        for t in results["test_results"]:
            writer.writerow([
                t["test_name"],
                t["status"],
                f"{t['duration_sec']:.4f}",
                t["data_mismatches"],
                t["state_errors"],
                t["assertion_failures"],
                t["details"],
                t["log_path"],
            ])


def write_markdown_report(results: dict, out_file: Path):
    """Write comprehensive human-readable Markdown report."""
    out_file.parent.mkdir(parents=True, exist_ok=True)
    overall_status = results["summary"]["overall_status"]
    badge = "🟢 **PASSED**" if overall_status == "PASSED" else "🔴 **FAILED**"
    bug_info = results["configuration"].get("bug_macro") or "None (Golden RTL)"

    md = []
    md.append("# Synchronous FIFO Verification Regression Report\n")
    md.append(f"**Execution Timestamp:** {results['timestamp']}\n")
    md.append(f"**Overall Result:** {badge}\n")
    md.append(f"**Defect Injection Configuration:** `{bug_info}`\n\n")

    md.append("## Executive Summary\n")
    md.append("| Metric | Value |")
    md.append("| :--- | :--- |")
    md.append(f"| **Total Tests** | {results['summary']['total_tests']} |")
    md.append(f"| **Passed Tests** | {results['summary']['passed']} |")
    md.append(f"| **Failed Tests** | {results['summary']['failed']} |")
    md.append(f"| **Pass Rate** | {results['summary']['pass_rate']} |")
    md.append(f"| **Total Duration** | {results['summary']['total_duration_sec']:.3f} s |")
    md.append(f"| **Overall Status** | `{overall_status}` |\n\n")

    md.append("## Detailed Test Results\n")
    md.append("| Test Identifier | Status | Duration (s) | Data Mismatches | Assertion Fails | Diagnostic Details |")
    md.append("| :--- | :---: | :---: | :---: | :---: | :--- |")
    for t in results["test_results"]:
        st = "✅ PASS" if t["passed"] else "❌ FAIL"
        md.append(f"| `{t['test_name']}` | {st} | {t['duration_sec']:.3f} | {t['data_mismatches']} | {t['assertion_failures']} | {t['details']} |")

    md.append("\n## Log Artifacts\n")
    md.append("All individual test execution logs are preserved in `reports/logs/`:\n")
    for t in results["test_results"]:
        md.append(f"- [`{t['test_name']}.log`]({t['log_path']})")

    md.append("\n---\n*Report generated by `scripts/regression.py`*")

    with open(out_file, "w") as f:
        f.write("\n".join(md))


def print_dashboard(results: dict):
    """Print clean aligned terminal dashboard."""
    use_color = sys.stdout.isatty()
    green = "\033[92m" if use_color else ""
    red = "\033[91m" if use_color else ""
    bold = "\033[1m" if use_color else ""
    reset = "\033[0m" if use_color else ""

    print("\n" + "=" * 95)
    print(f"{bold}                 SYNCHRONOUS FIFO REGRESSION EXECUTION DASHBOARD{reset}")
    print("=" * 95)
    print(f"{'Test Identifier':<28} | {'Status':<8} | {'Time (s)':<10} | {'Mismatches':<10} | {'Details':<25}")
    print("-" * 95)

    for t in results["test_results"]:
        color = green if t["passed"] else red
        st_str = f"{color}{t['status']:<8}{reset}"
        print(f"{t['test_name']:<28} | {st_str} | {t['duration_sec']:<10.3f} | {t['data_mismatches']:<10} | {t['details']:<25}")

    print("-" * 95)
    s = results["summary"]
    status_color = green if s["overall_status"] == "PASSED" else red
    print(f"Total Tests: {s['total_tests']}  |  "
          f"{green}Passed: {s['passed']}{reset}  |  "
          f"{red}Failed: {s['failed']}{reset}  |  "
          f"Pass Rate: {s['pass_rate']}  |  "
          f"Duration: {s['total_duration_sec']:.3f}s")
    print(f"Overall Regression Status: {status_color}{bold}{s['overall_status']}{reset}")
    print("=" * 95 + "\n")


def main():
    parser = argparse.ArgumentParser(description="Automated Regression Runner for sync_fifo")
    parser.add_argument("--tests", default=None, help="Comma-separated test names to run (default: all discovered tests)")
    parser.add_argument("--seed", type=int, default=42, help="Random seed (default: 42)")
    parser.add_argument("--wave", action="store_true", help="Enable waveform dumping for all tests")
    parser.add_argument("--bug", default=None, help="Defect injection macro (e.g. BUG_INJECT_OVERFLOW)")
    parser.add_argument("--timeout", type=int, default=30, help="Per-test timeout in seconds (default: 30)")
    parser.add_argument("--sim-dir", default="sim", help="Build directory")
    parser.add_argument("--out-dir", default="reports", help="Reports output directory")
    parser.add_argument("--fail-fast", action="store_true", help="Abort on first test failure")
    args = parser.parse_args()

    root_dir = Path(__file__).resolve().parent.parent
    sim_dir = root_dir / args.sim_dir
    reports_dir = root_dir / args.out_dir
    log_dir = reports_dir / "logs"

    vvp = find_tool("vvp")
    if not vvp:
        print("[ERROR] 'vvp' simulator runtime not found. Please install icarus-verilog.")
        sys.exit(2)

    # 1. Discover or parse tests
    if args.tests:
        test_list = [t.strip() for t in args.tests.split(",") if t.strip()]
    else:
        test_list = discover_tests(root_dir / "tests")

    if not test_list:
        print("[ERROR] No verification tests found to execute.")
        sys.exit(1)

    print(f"\n[REGRESSION START] Discovered {len(test_list)} tests for regression suite.")
    if args.bug:
        print(f"[DEFECT INJECTION] Active bug injection macro: {args.bug}")

    # 2. Compile simulation snapshot
    print("[COMPILATION] Compiling RTL and testbench suite...")
    compile_success, msg, code = compile_testbench(root_dir, sim_dir, args.bug)
    if not compile_success:
        print(f"[COMPILATION FAILED]\n{msg}")
        sys.exit(code)
    binary_path = msg
    print(f"[COMPILATION OK] Simulation binary ready: {binary_path}")

    # 3. Execute all tests
    test_results = []
    regression_start = time.time()

    for idx, test_name in enumerate(test_list, start=1):
        log_file = log_dir / f"{test_name}.log"
        print(f"  [{idx}/{len(test_list)}] Running {test_name}...", end="", flush=True)
        res = run_single_test(
            vvp,
            binary_path,
            test_name,
            args.seed,
            args.wave,
            log_file,
            args.timeout,
        )
        test_results.append(res)
        tag = "\033[92mPASS\033[0m" if res["passed"] else "\033[91mFAIL\033[0m"
        print(f" {tag} ({res['duration_sec']:.3f}s)")

        if args.fail_fast and not res["passed"]:
            print(f"[FAIL-FAST] Aborting regression suite due to failure in {test_name}.")
            break

    total_duration = time.time() - regression_start
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
            "seed": args.seed,
            "wave_dump": args.wave,
            "bug_macro": args.bug,
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

    # 4. Generate report outputs
    json_path = reports_dir / "regression_summary.json"
    csv_path = reports_dir / "regression_summary.csv"
    md_path = reports_dir / "regression_report.md"

    write_json_summary(summary_data, json_path)
    write_csv_summary(summary_data, csv_path)
    write_markdown_report(summary_data, md_path)

    # 5. Display terminal dashboard
    print_dashboard(summary_data)
    print(f"[REPORTS] JSON Summary : {json_path}")
    print(f"[REPORTS] CSV Summary  : {csv_path}")
    print(f"[REPORTS] Markdown     : {md_path}\n")

    sys.exit(0 if overall_status == "PASSED" else 1)


if __name__ == "__main__":
    main()
