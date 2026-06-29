#!/usr/bin/env python3
"""Benchmark software decompression time using the hw_vs_sw reference pipeline."""

from __future__ import annotations

import statistics
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parent
HW_VS_SW = ROOT.parent / "hw_vs_sw"
sys.path.insert(0, str(HW_VS_SW))

from generate_sw_results import decompress_packet_sw, parse_compressed_input, parse_original_packet  # noqa: E402

WARMUP_ITER = 100
TIMED_ITER = 10_000


def bench_one(hw_text: str) -> dict[str, float]:
    key_in, in_count, packed = parse_compressed_input(hw_text)
    for _ in range(WARMUP_ITER):
        decompress_packet_sw(packed, key_in, in_count)

    samples: list[float] = []
    t0 = time.perf_counter()
    for _ in range(TIMED_ITER):
        t_start = time.perf_counter()
        decompress_packet_sw(packed, key_in, in_count)
        samples.append(time.perf_counter() - t_start)
    total = time.perf_counter() - t0

    return {
        "mean_s": statistics.mean(samples),
        "median_s": statistics.median(samples),
        "min_s": min(samples),
        "max_s": max(samples),
        "total_batch_s": total,
        "iterations": TIMED_ITER,
    }


def format_report(results: list[tuple[str, dict[str, float]]]) -> str:
    sep = "=" * 80
    dash = "-" * 80
    now = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S UTC")

    lines = [
        sep,
        "SOFTWARE TIMING BENCHMARK",
        sep,
        "Source:      decompressor_ref_pkg pipeline (URZE -> BIT -> UNDIFFNB)",
        f"Generated:   {now}",
        f"Warmup:      {WARMUP_ITER} iterations per test",
        f"Timed:       {TIMED_ITER} iterations per test",
        "",
        dash,
        "PER-TEST RESULTS (seconds per packet)",
        dash,
        f"{'Test':<20} {'mean_s':>14} {'median_s':>14} {'min_s':>14} {'max_s':>14}",
    ]

    total_mean = 0.0
    for name, r in results:
        lines.append(
            f"{name:<20} {r['mean_s']:14.6e} {r['median_s']:14.6e} "
            f"{r['min_s']:14.6e} {r['max_s']:14.6e}"
        )
        total_mean += r["mean_s"]

    lines += [
        "",
        dash,
        "SUMMARY",
        dash,
        f"NUM_TESTS:          {len(results)}",
        f"TOTAL_MEAN_S:       {total_mean:.6e}",
        f"MEAN_PER_PACKET_S:  {total_mean / len(results):.6e}" if results else "MEAN_PER_PACKET_S:  n/a",
        sep,
    ]
    return "\n".join(lines) + "\n"


def main() -> int:
    hw_dir = HW_VS_SW / "hw"
    sw_dir = ROOT / "sw"
    sw_dir.mkdir(parents=True, exist_ok=True)

    hw_files = sorted(hw_dir.glob("*.txt"))
    if not hw_files:
        print(f"No HW dumps in {hw_dir}. Run run_sim.cmd first.")
        return 1

    results: list[tuple[str, dict[str, float]]] = []
    for hw_path in hw_files:
        name = hw_path.stem
        text = hw_path.read_text(encoding="utf-8")
        parse_original_packet(text)
        stats = bench_one(text)
        results.append((name, stats))
        print(f"Benchmarked {name}: mean={stats['mean_s']:.6e} s/packet")

    out = sw_dir / "sw_timing.txt"
    out.write_text(format_report(results), encoding="utf-8")
    print(f"\nWrote {out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())