#!/usr/bin/env python3
"""Parse Vivado timing reports and compute HW execution time."""

from __future__ import annotations

import argparse
import re
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parent

PART = "xc7z020clg400-1"
BOARD = "Pynq-Z2"
TARGET_MHZ = 100.0
TARGET_PERIOD_NS = 1000.0 / TARGET_MHZ
LATENCY_CYCLES = 3
CLOCK_NAME = "clk"


def parse_timing_summary(text: str) -> tuple[float, float]:
    """Return (wns_ns, tns_ns) from report_timing_summary.rpt."""
    lines = text.splitlines()

    in_clock_summary = False
    for line in lines:
        if "Clock Summary" in line:
            in_clock_summary = True
            continue
        if in_clock_summary and re.match(rf"^\s*{re.escape(CLOCK_NAME)}\s", line):
            parts = line.split()
            if len(parts) >= 3:
                return float(parts[1]), float(parts[2])
        if in_clock_summary and line.strip() == "":
            in_clock_summary = False

    seen_header = False
    for line in lines:
        stripped = line.strip()
        if "WNS(ns)" in stripped and "TNS(ns)" in stripped:
            seen_header = True
            continue
        if not seen_header:
            continue
        m = re.match(r"^(-?\d+(?:\.\d+)?)\s+(-?\d+(?:\.\d+)?)", stripped)
        if m:
            return float(m.group(1)), float(m.group(2))

    raise ValueError("could not parse WNS/TNS from timing summary")


def max_achievable_mhz(wns_ns: float) -> float:
    period_ns = TARGET_PERIOD_NS - wns_ns
    if period_ns <= 0:
        raise ValueError(f"invalid achieved period {period_ns} ns (WNS={wns_ns})")
    return 1000.0 / period_ns


def execution_mhz(wns_ns: float) -> float:
    if wns_ns >= 0:
        return TARGET_MHZ
    return max_achievable_mhz(wns_ns)


def format_hw_report(
    *,
    stage: str,
    wns_ns: float,
    tns_ns: float,
    max_mhz: float,
    exec_mhz: float,
    num_tests: int,
) -> str:
    timing_met = wns_ns >= 0
    sec_per_packet = LATENCY_CYCLES / (exec_mhz * 1e6)
    sec_all = sec_per_packet * num_tests
    now = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S UTC")
    stage_label = "SYNTHESIS" if stage == "synth" else "IMPLEMENTATION"

    sep = "=" * 80
    return "\n".join(
        [
            sep,
            f"HARDWARE TIMING — {stage_label}",
            sep,
            f"Board:              {BOARD} ({PART})",
            f"Generated:          {now}",
            f"Target MHz:         {TARGET_MHZ:.1f}",
            f"Max achievable MHz: {max_mhz:.3f}",
            f"Execution MHz:      {exec_mhz:.3f}",
            f"WNS ns:             {wns_ns:.3f}",
            f"TNS ns:             {tns_ns:.3f}",
            f"Timing met:         {'yes' if timing_met else 'no'}",
            f"Latency cycles:     {LATENCY_CYCLES}",
            f"Seconds per packet: {sec_per_packet:.6e}",
            f"Seconds for {num_tests} packets: {sec_all:.6e}",
            f"NUM_TESTS:          {num_tests}",
            sep,
            "",
        ]
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--stage", choices=["synth", "impl"], required=True)
    args = parser.parse_args()

    if args.stage == "synth":
        reports_dir = ROOT / "synth_vs_sw" / "reports"
        out_dir = ROOT / "synth_vs_sw"
    else:
        reports_dir = ROOT / "impl_vs_sw" / "reports"
        out_dir = ROOT / "impl_vs_sw"

    rpt = reports_dir / "timing_summary.rpt"
    if not rpt.exists():
        print(f"Missing {rpt}. Run run_synth.ps1 / run_impl.ps1 first.")
        return 1

    wns, tns = parse_timing_summary(rpt.read_text(encoding="utf-8", errors="replace"))
    max_mhz = max_achievable_mhz(wns)
    exec_mhz = execution_mhz(wns)

    hw_vs_sw_hw = ROOT.parent / "hw_vs_sw" / "hw"
    num_tests = len(list(hw_vs_sw_hw.glob("*.txt"))) or 9

    out = out_dir / "hw_timing.txt"
    out.write_text(
        format_hw_report(
            stage=args.stage,
            wns_ns=wns,
            tns_ns=tns,
            max_mhz=max_mhz,
            exec_mhz=exec_mhz,
            num_tests=num_tests,
        ),
        encoding="utf-8",
    )
    print(
        f"Wrote {out}  (exec={exec_mhz:.3f} MHz, max={max_mhz:.3f} MHz, WNS={wns:.3f} ns)"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())