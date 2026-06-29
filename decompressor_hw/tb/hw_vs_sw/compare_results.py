#!/usr/bin/env python3
"""Compare hw_vs_sw/hw/*.txt vs hw_vs_sw/sw/*.txt decompression outputs."""

from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent


def parse_recovered_packet(text: str) -> list[int]:
    words: list[int] = []
    in_section = False
    past_header_rule = False
    for line in text.splitlines():
        if line.startswith("RECOVERED PACKET"):
            in_section = True
            past_header_rule = False
            continue
        if in_section and line.startswith("==="):
            break
        if in_section and line.startswith("---"):
            if past_header_rule:
                continue
            past_header_rule = True
            continue
        m = re.match(r"\s*\[\s*\d+\]\s+0x([0-9A-Fa-f]+)", line)
        if in_section and past_header_rule and m:
            words.append(int(m.group(1), 16))
    if len(words) != 64:
        raise ValueError(f"expected 64 recovered words, parsed {len(words)}")
    return words


def main() -> int:
    hw_dir = ROOT / "hw"
    sw_dir = ROOT / "sw"
    summary_dir = ROOT / "summary"
    summary_dir.mkdir(exist_ok=True)

    hw_files = sorted(hw_dir.glob("*.txt"))
    if not hw_files:
        print("No HW results. Run run_all.ps1 or run_sim.cmd first.")
        return 1

    passed = 0
    failed = 0
    lines = []

    for hw_path in hw_files:
        name = hw_path.stem
        sw_path = sw_dir / f"{name}.txt"
        if not sw_path.exists():
            lines.append(f"FAIL {name}: missing {sw_path.name}")
            failed += 1
            continue

        try:
            hw = parse_recovered_packet(hw_path.read_text(encoding="utf-8"))
            sw = parse_recovered_packet(sw_path.read_text(encoding="utf-8"))
        except ValueError as exc:
            lines.append(f"FAIL {name}: {exc}")
            failed += 1
            continue

        ok = True
        diffs: list[str] = []
        for i, (hv, sv) in enumerate(zip(hw, sw)):
            if hv != sv:
                ok = False
                diffs.append(f"  word[{i}]: HW=0x{hv:08X}  SW=0x{sv:08X}")

        if ok:
            lines.append(f"PASS {name}")
            passed += 1
        else:
            lines.append(f"FAIL {name}")
            lines.extend(diffs)
            failed += 1

    report = "\n".join(lines) + f"\n\n{passed} passed, {failed} failed\n"
    (summary_dir / "comparison.txt").write_text(report, encoding="utf-8")
    print(report, end="")
    return 0 if failed == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())