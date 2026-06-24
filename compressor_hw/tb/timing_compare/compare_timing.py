#!/usr/bin/env python3
"""Compare software vs hardware execution time for synth or impl stage."""

from __future__ import annotations

import argparse
import re
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parent


def parse_sw_timing(text: str) -> dict[str, float]:
    tests: dict[str, float] = {}
    for line in text.splitlines():
        m = re.match(r"^(\S+)\s+([\d.eE+-]+)\s+[\d.eE+-]+\s+[\d.eE+-]+\s+[\d.eE+-]+", line)
        if m:
            tests[m.group(1)] = float(m.group(2))
    total_m = re.search(r"TOTAL_MEAN_S:\s+([\d.eE+-]+)", text)
    num_m = re.search(r"NUM_TESTS:\s+(\d+)", text)
    return {
        "tests": tests,
        "total_mean_s": float(total_m.group(1)) if total_m else sum(tests.values()),
        "num_tests": int(num_m.group(1)) if num_m else len(tests),
    }


def parse_hw_timing(text: str) -> dict[str, float | str | int | bool]:
    def grab(pattern: str, cast=float):
        m = re.search(pattern, text)
        if not m:
            raise ValueError(f"missing field: {pattern}")
        return cast(m.group(1))

    return {
        "board": grab(r"Board:\s+(.+)", str),
        "target_mhz": grab(r"Target MHz:\s+([\d.]+)"),
        "max_mhz": grab(r"Max achievable MHz:\s+([\d.]+)"),
        "exec_mhz": grab(r"Execution MHz:\s+([\d.]+)"),
        "wns_ns": grab(r"WNS ns:\s+([-\d.]+)"),
        "timing_met": grab(r"Timing met:\s+(\w+)", str) == "yes",
        "latency_cycles": grab(r"Latency cycles:\s+(\d+)", int),
        "sec_per_packet": grab(r"Seconds per packet:\s+([\d.eE+-]+)"),
        "sec_all_packets": grab(r"Seconds for \d+ packets:\s+([\d.eE+-]+)"),
        "num_tests": grab(r"NUM_TESTS:\s+(\d+)", int),
    }


def format_comparison(stage: str, sw: dict, hw: dict) -> str:
    stage_label = "SYNTHESIS" if stage == "synth" else "IMPLEMENTATION"
    now = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S UTC")
    hw_per = float(hw["sec_per_packet"])
    hw_all = float(hw["sec_all_packets"])
    sep = "=" * 80
    dash = "-" * 80

    lines = [
        sep,
        f"TIMING COMPARISON — {stage_label} vs SOFTWARE",
        sep,
        f"Generated:   {now}",
        f"Board:       {hw['board']}",
        f"Target:      {hw['target_mhz']:.1f} MHz",
        f"Execution:   {hw['exec_mhz']:.3f} MHz (at 100 MHz target when timing met)",
        f"Max Fmax:    {hw['max_mhz']:.3f} MHz",
        f"WNS:         {hw['wns_ns']:.3f} ns",
        f"Timing met:  {'yes' if hw['timing_met'] else 'NO — results use achievable Fmax'}",
        f"HW latency:  {hw['latency_cycles']} cycles",
        f"HW per pkt:  {hw_per:.6e} s",
        f"HW {hw['num_tests']} pkts: {hw_all:.6e} s",
        "",
        dash,
        f"{'Test':<20} {'SW (s)':>14} {f'HW {stage_label[:5].lower()} (s)':>14} {'Speedup':>12}",
        dash,
    ]

    speedups: list[float] = []
    for name in sorted(sw["tests"]):
        sw_s = sw["tests"][name]
        ratio = sw_s / hw_per if hw_per > 0 else float("inf")
        speedups.append(ratio)
        lines.append(f"{name:<20} {sw_s:14.6e} {hw_per:14.6e} {ratio:11.1f}x")

    total_sw = float(sw["total_mean_s"])
    total_ratio = total_sw / hw_all if hw_all > 0 else float("inf")
    lines += [
        dash,
        f"{'TOTAL (all tests)':<20} {total_sw:14.6e} {hw_all:14.6e} {total_ratio:11.1f}x",
        "",
        "Notes:",
        "  SW time = wall-clock mean per packet (compressor_sw pipeline).",
        "  HW time = pipeline latency (3 cycles) at achieved post-route/synth Fmax.",
        "  Speedup = SW / HW (values >1 mean hardware is faster).",
        sep,
        "",
    ]
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--stage", choices=["synth", "impl"], required=True)
    args = parser.parse_args()

    sw_path = ROOT / "sw" / "sw_timing.txt"
    if not sw_path.exists():
        print(f"Missing {sw_path}. Run benchmark_sw.py first.")
        return 1

    out_dir = ROOT / ("synth_vs_sw" if args.stage == "synth" else "impl_vs_sw")
    hw_path = out_dir / "hw_timing.txt"
    if not hw_path.exists():
        print(f"Missing {hw_path}. Run parse_vivado_timing.py --stage {args.stage} first.")
        return 1

    sw = parse_sw_timing(sw_path.read_text(encoding="utf-8"))
    hw = parse_hw_timing(hw_path.read_text(encoding="utf-8"))

    report = format_comparison(args.stage, sw, hw)
    out = out_dir / "comparison.txt"
    out.write_text(report, encoding="utf-8")
    print(report, end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())