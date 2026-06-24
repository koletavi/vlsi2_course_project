#!/usr/bin/env python3
"""Compare hw_vs_sw/hw/*.txt vs hw_vs_sw/sw/*.txt compressed outputs."""

from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent


def parse_compressed(text: str) -> dict:
    key_m = re.search(r"key_out:\s+0x([0-9A-Fa-f]+)", text)
    count_m = re.search(r"out_count:\s+(\d+)", text)
    if not key_m or not count_m:
        raise ValueError("missing key_out or out_count")

    planes: list[int] = []
    for m in re.finditer(r"hex:\s+0x([0-9A-Fa-f]+)", text):
        planes.append(int(m.group(1), 16))

    return {
        "key_out": int(key_m.group(1), 16),
        "out_count": int(count_m.group(1)),
        "packed_planes": planes,
    }


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

        hw = parse_compressed(hw_path.read_text(encoding="utf-8"))
        sw = parse_compressed(sw_path.read_text(encoding="utf-8"))

        ok = True
        diffs: list[str] = []
        if hw["key_out"] != sw["key_out"]:
            ok = False
            diffs.append(f"  key_out: HW=0x{hw['key_out']:08X}  SW=0x{sw['key_out']:08X}")
        if hw["out_count"] != sw["out_count"]:
            ok = False
            diffs.append(f"  out_count: HW={hw['out_count']}  SW={sw['out_count']}")
        if hw["packed_planes"] != sw["packed_planes"]:
            ok = False
            for i in range(max(len(hw["packed_planes"]), len(sw["packed_planes"]))):
                hv = hw["packed_planes"][i] if i < len(hw["packed_planes"]) else None
                sv = sw["packed_planes"][i] if i < len(sw["packed_planes"]) else None
                if hv != sv:
                    diffs.append(f"  packed_planes[{i}]: HW={hv}  SW={sv}")

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