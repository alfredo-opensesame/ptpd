#!/usr/bin/env python3
"""
summarize-comparison.py
Reads servo.csv from each sub-directory of a comparison run and prints
a side-by-side statistics table.

Usage:
    python3 summarize-comparison.py <comparison_dir>
"""

import sys
import os
import csv
import math
from collections import defaultdict

RUNS = ["current", "option-a", "option-b"]

LABELS = {
    "current":  "Current  (kp=0.01 ki=0.0001)",
    "option-a": "Option-A (kp=0.1  ki≈0     )",
    "option-b": "Option-B (kp=0.1  ki=0.001 )",
}

METRICS = [
    ("ptpd_offset_input_ns",       "Offset (ns)       mean"),
    ("ptpd_offset_input_ns",       "Offset (ns)       std"),
    ("ptpd_offset_input_ns",       "Offset (ns)       |max|"),
    ("ptpd_observed_drift_ppb",    "Drift (ppb)       mean"),
    ("ptpd_observed_drift_ppb",    "Drift (ppb)       std"),
    ("ptpd_drift_mean_ppb",        "Drift mean stat   ppb"),
    ("ptpd_drift_std_ppb",         "Drift std stat    ppb"),
    ("swclock_remaining_phase_ns", "swclock phase res ns"),
    ("swclock_mean_te_ns",         "swclock mean TE   ns"),
    ("swclock_std_te_ns",          "swclock std TE    ns"),
    ("swclock_max_te_ns",          "swclock max TE    ns"),
    ("swclock_mtie_1s_ns",         "swclock MTIE 1s   ns"),
    ("swclock_mtie_10s_ns",        "swclock MTIE 10s  ns"),
    ("swclock_tdev_1s_ns",         "swclock TDEV 1s   ns"),
]


def safe_float(v):
    try:
        return float(v)
    except (ValueError, TypeError):
        return None


def stats(values):
    vals = [v for v in values if v is not None]
    if not vals:
        return dict(mean=None, std=None, max_abs=None, count=0, last=None)
    n = len(vals)
    mean = sum(vals) / n
    std = math.sqrt(sum((x - mean) ** 2 for x in vals) / n) if n > 1 else 0.0
    max_abs = max(abs(v) for v in vals)
    return dict(mean=mean, std=std, max_abs=max_abs, count=n, last=vals[-1])


def load_servo_csv(path):
    """Return (active_data, total_rows, active_rows, last_elapsed).
    active_data: dict of column_name -> list of float values for ptp_active=1 rows.
    Falls back to all rows if ptp_active column is absent (backward compat).
    """
    data = defaultdict(list)
    total_rows = 0
    active_rows = 0
    last_elapsed = 0.0
    if not os.path.exists(path):
        return data, 0, 0, 0.0
    with open(path, newline="") as f:
        reader = csv.DictReader(f)
        has_active_col = None
        for row in reader:
            if has_active_col is None:
                has_active_col = "ptp_active" in row
            total_rows += 1
            # Filter to PTP-active rows when column present
            if has_active_col and row.get("ptp_active", "1") != "1":
                elapsed = safe_float(row.get("elapsed_s", 0))
                if elapsed is not None:
                    last_elapsed = max(last_elapsed, elapsed)
                continue
            active_rows += 1
            for k, v in row.items():
                fv = safe_float(v)
                if fv is not None:
                    data[k].append(fv)
            elapsed = safe_float(row.get("elapsed_s", 0))
            if elapsed is not None:
                last_elapsed = max(last_elapsed, elapsed)
    return data, total_rows, active_rows, last_elapsed


def fmt(v, decimals=1):
    if v is None:
        return "   N/A  "
    return f"{v:+10.{decimals}f}"


def main():
    if len(sys.argv) < 2:
        print(f"Usage: {sys.argv[0]} <comparison_dir>", file=sys.stderr)
        sys.exit(1)

    comp_dir = sys.argv[1]
    run_data = {}
    run_meta = {}  # total_rows, active_rows, last_elapsed

    for run in RUNS:
        csv_path = os.path.join(comp_dir, run, "servo.csv")
        data, total, active, last_e = load_servo_csv(csv_path)
        run_data[run] = data
        run_meta[run] = (total, active, last_e)
        print(f"  Loaded {run}: {csv_path} ({active}/{total} ptp_active rows)")

    print()
    print("=" * 80)
    print("  SERVO GAINS COMPARISON")
    print("=" * 80)

    # Header
    col_w = 14
    header = f"{'Metric':<34}"
    for run in RUNS:
        header += f"  {LABELS[run][:col_w]:>{col_w}}"
    print(header)
    print("-" * 80)

    # Rows
    prev_col = None
    for col, label in METRICS:
        if col != prev_col and prev_col is not None:
            print()
        prev_col = col

        row = f"  {label:<32}"
        for run in RUNS:
            vals = run_data[run].get(col, [])
            s = stats(vals)

            if "mean" in label:
                val = s["mean"]
            elif "std" in label:
                val = s["std"]
            elif "|max|" in label:
                val = s["max_abs"]
            elif "last" in label:
                val = s["last"]
            else:
                val = s["mean"]

            row += f"  {fmt(val, decimals=1):>{col_w}}"
        print(row)

    print()
    print("=" * 80)

    # Final sample counts
    print("\nSample counts per run:")
    for run in RUNS:
        total, active, last_e = run_meta[run]
        print(f"  {run:12s}: {active} ptp_active rows / {total} total, {last_e:.0f}s elapsed")

    print()
    print("Notes:")
    print("  All stats computed over ptp_active=1 rows only (PTP master present).")
    print("  swclock metrics require PTPD_USE_SWCLOCK at build time.")


if __name__ == "__main__":
    main()
