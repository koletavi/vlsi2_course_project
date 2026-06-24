#!/usr/bin/env python3
"""
Generate software compression dumps for hw_vs_sw comparison.

Uses the existing compressor in ../../compressor_sw/posit_compress.py:
  diff_nb_encode -> bit_transpose_encode -> rze_encode
"""

from __future__ import annotations

import re
import sys
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT.parents[2] / "compressor_sw"))

from posit_compress import (  # noqa: E402
    diff_nb_encode,
    bit_transpose_encode,
    rze_encode,
    unpack_bytes_to_words,
)

WORD_SIZE = 32
PACKET_SIZE = 64
PLANE_WIDTH = 64


def parse_original_packet(text: str) -> list[int]:
    words: list[int] = []
    in_section = False
    past_header_rule = False
    for line in text.splitlines():
        if line.startswith("ORIGINAL PACKET"):
            in_section = True
            past_header_rule = False
            continue
        if in_section and line.startswith("---"):
            if past_header_rule:
                break
            past_header_rule = True
            continue
        m = re.match(r"\s*\[\s*\d+\]\s+0x([0-9A-Fa-f]+)", line)
        if in_section and past_header_rule and m:
            words.append(int(m.group(1), 16))
    if len(words) != PACKET_SIZE:
        raise ValueError(f"expected {PACKET_SIZE} words, parsed {len(words)}")
    return words


def compress_packet_sw(words: list[int]) -> tuple[int, int, list[int]]:
    """Run existing SW stages; remap BIT planes to HW bit-index order for RZE."""
    stage1 = diff_nb_encode(words, WORD_SIZE)
    stage2 = bit_transpose_encode(stage1, WORD_SIZE, PACKET_SIZE)
    # bit_transpose_encode emits MSB plane first; HW plane[i] = bit i (LSB=0)
    hw_planes = [stage2[WORD_SIZE - 1 - i] for i in range(WORD_SIZE)]
    bitmap_b, nz_b, _ = rze_encode(hw_planes, PLANE_WIDTH)
    key_out = int.from_bytes(bitmap_b, "little")
    num_nz = (len(nz_b) // (PLANE_WIDTH // 8)) if nz_b else 0
    packed = unpack_bytes_to_words(nz_b, PLANE_WIDTH, num_nz) if num_nz else []
    return key_out, len(packed), packed


def format_dump(
    *,
    source: str,
    test_name: str,
    words: list[int],
    key_out: int,
    out_count: int,
    packed_planes: list[int],
) -> str:
    sep = "=" * 80
    dash = "-" * 80
    lines = [
        sep,
        "COMPRESSION RESULT",
        sep,
        f"Source:      {source}",
        f"Test:        {test_name}",
        f"Generated:   {datetime.now(timezone.utc).strftime('%Y-%m-%d %H:%M:%S UTC')}",
        "",
        "CONFIGURATION",
        f"  WORD_SIZE:   {WORD_SIZE}",
        f"  PACKET_SIZE: {PACKET_SIZE}",
        "",
        dash,
        f"ORIGINAL PACKET ({PACKET_SIZE} x {WORD_SIZE}-bit words)",
        dash,
    ]
    for i, w in enumerate(words):
        w &= 0xFFFFFFFF
        lines.append(f"  [{i:2d}] 0x{w:08X}  ({w})")
    lines += [
        "",
        dash,
        "COMPRESSED OUTPUT (DIFFNB -> BIT -> RZE)",
        dash,
        f"  key_out:    0x{key_out:08X}",
        f"  out_count:  {out_count}",
        "",
    ]
    key_bits = [i for i in range(WORD_SIZE) if (key_out >> i) & 1]
    if key_bits:
        lines.append("  key_out bit map (bit i = 1 => original bit-plane i was non-zero):")
        for i in key_bits:
            lines.append(f"    plane[{i:2d}] : NON-ZERO")
    else:
        lines.append("  key_out bit map: (all planes zero)")
    lines += ["", f"  packed_planes ({out_count} dense entries):"]
    if out_count == 0:
        lines.append("    (empty)")
    else:
        src = 0
        for p in range(out_count):
            while src < WORD_SIZE and not ((key_out >> src) & 1):
                src += 1
            plane = packed_planes[p] & ((1 << PLANE_WIDTH) - 1)
            lines.append(f"    [{p}] from plane[{src}]")
            lines.append(f"         hex: 0x{plane:016X}")
            lines.append(f"         bin: {plane:064b}")
            src += 1
    lines += ["", sep]
    return "\n".join(lines) + "\n"


def main() -> int:
    hw_dir = ROOT / "hw"
    sw_dir = ROOT / "sw"
    sw_dir.mkdir(parents=True, exist_ok=True)

    hw_files = sorted(hw_dir.glob("*.txt"))
    if not hw_files:
        print(f"No HW dumps found in {hw_dir}")
        print("Run run_sim.cmd first to generate hw/*.txt")
        return 1

    for hw_path in hw_files:
        test_name = hw_path.stem
        words = parse_original_packet(hw_path.read_text(encoding="utf-8"))
        key, count, packed = compress_packet_sw(words)
        text = format_dump(
            source="SOFTWARE (compressor_sw/posit_compress.py)",
            test_name=test_name,
            words=words,
            key_out=key,
            out_count=count,
            packed_planes=packed,
        )
        out = sw_dir / f"{test_name}.txt"
        out.write_text(text, encoding="utf-8")
        print(f"Wrote {out}")

    print(f"\nGenerated {len(hw_files)} SW file(s) in {sw_dir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())