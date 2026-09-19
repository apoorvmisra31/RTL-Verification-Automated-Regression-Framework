#!/usr/bin/env python3
"""
generate_report.py - Standalone Report Generator for Synchronous FIFO Regression

Reads regression_summary.json and generates:
- Formatted terminal table
- Markdown report file
- CSV file
"""

import argparse
import csv
import json
import sys
from pathlib import Path


def generate_reports(json_path: Path, md_path: Path = None, csv_path: Path = None):
    if not json_path.exists():
        print(f"Error: JSON summary file not found at {json_path}")
        sys.exit(1)

    with open(json_path, "r") as f:
        data = json.load(f)

    s = data["summary"]
    cfg = data.get("configuration", {})

    print("\n" + "=" * 80)
    print("                     REGRESSION SUMMARY REPORT")
    print("=" * 80)
    print(f"Timestamp   : {data.get('timestamp', 'N/A')}")
    print(f"Simulator   : {cfg.get('simulator', 'Icarus Verilog')}")
    print(f"DUT         : {cfg.get('dut', 'sync_fifo')}")
    print(f"Defect Mode : {cfg.get('bug_macro') or 'None (Clean)'}")
    print(f"Total Tests : {s['total_tests']}")
    print(f"Passed      : {s['passed']}")
    print(f"Failed      : {s['failed']}")
    print(f"Pass Rate   : {s['pass_rate']}")
    print(f"Total Time  : {s['total_duration_sec']:.3f} s")
    print(f"Status      : {s['overall_status']}")
    print("-" * 80)
    print(f"{'Test Identifier':<28} | {'Status':<8} | {'Time (s)':<10} | {'Details':<25}")
    print("-" * 80)

    for t in data["test_results"]:
        print(f"{t['test_name']:<28} | {t['status']:<8} | {t['duration_sec']:<10.3f} | {t['details']:<25}")
    print("=" * 80 + "\n")

    if md_path:
        md_path.parent.mkdir(parents=True, exist_ok=True)
        md = [
            "# Synchronous FIFO Regression Report",
            f"\n**Execution Timestamp:** {data.get('timestamp')}",
            f"**Overall Result:** `{s['overall_status']}`",
            f"**Defect Injection:** `{cfg.get('bug_macro') or 'None'}`\n",
            "## Summary Metrics",
            "| Metric | Value |",
            "| :--- | :--- |",
            f"| Total Tests | {s['total_tests']} |",
            f"| Passed Tests | {s['passed']} |",
            f"| Failed Tests | {s['failed']} |",
            f"| Pass Rate | {s['pass_rate']} |",
            f"| Duration | {s['total_duration_sec']:.3f} s |\n",
            "## Test Breakdown",
            "| Test Name | Status | Time (s) | Mismatches | Assertion Fails | Details |",
            "| :--- | :---: | :---: | :---: | :---: | :--- |",
        ]
        for t in data["test_results"]:
            md.append(f"| `{t['test_name']}` | {t['status']} | {t['duration_sec']:.3f} | {t['data_mismatches']} | {t['assertion_failures']} | {t['details']} |")
        
        with open(md_path, "w") as f:
            f.write("\n".join(md) + "\n")
        print(f"Generated Markdown report at: {md_path}")

    if csv_path:
        csv_path.parent.mkdir(parents=True, exist_ok=True)
        with open(csv_path, "w", newline="") as f:
            writer = csv.writer(f)
            writer.writerow(["Test Name", "Status", "Duration (s)", "Mismatches", "Assertion Fails", "Details", "Log Path"])
            for t in data["test_results"]:
                writer.writerow([t["test_name"], t["status"], t["duration_sec"], t["data_mismatches"], t["assertion_failures"], t["details"], t["log_path"]])
        print(f"Generated CSV report at: {csv_path}")


def main():
    parser = argparse.ArgumentParser(description="Generate regression reports from JSON summary")
    parser.add_argument("--json", default="reports/regression_summary.json", help="Path to input JSON summary")
    parser.add_argument("--md", default="reports/regression_report.md", help="Path to output Markdown file")
    parser.add_argument("--csv", default="reports/regression_summary.csv", help="Path to output CSV file")
    args = parser.parse_args()

    generate_reports(Path(args.json), Path(args.md) if args.md else None, Path(args.csv) if args.csv else None)


if __name__ == "__main__":
    main()
