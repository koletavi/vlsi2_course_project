#!/usr/bin/env python3
"""
Generate software decompression dumps for hw_vs_sw comparison.

Uses the same per-packet pipeline as decompressor_ref_pkg.sv:
  ref_urze -> ref_bit_transpose_to_words -> ref_undiffnb
"""

from __future__ import annotations

import re
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parent

WORD_SIZE = 32
PACKET_SIZE = 64
GROUP_SIZE = 8
GROUPS = WORD_SIZE // GROUP_SIZE
PLANE_WIDTH = 64
NB_MASK = int("10" * (WORD_SIZE // 2), 2)
MASK = (1 << WORD_SIZE) - 1


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


def parse_compressed_input(text: str) -> tuple[int, int, list[int]]:
    key_m = re.search(r"key_in:\s+0x([0-9A-Fa-f]+)", text)
    count_m = re.search(r"in_count:\s+(\d+)", text)
    if not key_m or not count_m:
        raise ValueError("missing key_in or in_count")

    in_section = False
    past_header_rule = False
    planes: list[int] = []
    for line in text.splitlines():
        if line.startswith("COMPRESSED INPUT"):
            in_section = True
            past_header_rule = False
            continue
        if in_section and line.startswith("DECOMPRESSED OUTPUT"):
            break
        if in_section and line.startswith("---"):
            if past_header_rule:
                continue
            past_header_rule = True
            continue
        m = re.search(r"hex:\s+0x([0-9A-Fa-f]+)", line)
        if in_section and past_header_rule and m:
            planes.append(int(m.group(1), 16))

    return int(key_m.group(1), 16), int(count_m.group(1)), planes


def decompress_packet_sw(packed_planes: list[int], key_in: int, in_count: int) -> list[int]:
    """Mirror decompressor_ref_pkg ref_decompress_packet."""
    transposed = [0] * WORD_SIZE
    packed_group = [[0] * GROUP_SIZE for _ in range(GROUPS)]
    group_count: list[int] = []
    ptr = 0

    for g in range(GROUPS):
        key_slice = [(key_in >> (g * GROUP_SIZE + j)) & 1 for j in range(GROUP_SIZE)]
        group_count.append(sum(key_slice))

    dense = (packed_planes + [0] * WORD_SIZE)[:WORD_SIZE]
    for g in range(GROUPS):
        for j in range(group_count[g]):
            packed_group[g][j] = dense[ptr]
            ptr += 1

    for g in range(GROUPS):
        key_slice = [(key_in >> (g * GROUP_SIZE + j)) & 1 for j in range(GROUP_SIZE)]
        unpack_ptr = 0
        for i in range(GROUP_SIZE):
            if key_slice[i]:
                transposed[g * GROUP_SIZE + i] = packed_group[g][unpack_ptr] & ((1 << PLANE_WIDTH) - 1)
                unpack_ptr += 1

    encoded = [0] * PACKET_SIZE
    for word in range(PACKET_SIZE):
        for bit_idx in range(WORD_SIZE):
            if (transposed[bit_idx] >> word) & 1:
                encoded[word] |= 1 << bit_idx

    words: list[int] = []
    delta = ((encoded[0] ^ NB_MASK) - NB_MASK) & MASK
    prev = delta
    words.append(prev)
    for i in range(1, PACKET_SIZE):
        delta = ((encoded[i] ^ NB_MASK) - NB_MASK) & MASK
        curr = (prev + delta) & MASK
        words.append(curr)
        prev = curr
    return words


def format_dump(
    *,
    source: str,
    test_name: str,
    words_orig: list[int],
    key_in: int,
    in_count: int,
    packed_planes: list[int],
    words_recovered: list[int],
) -> str:
    sep = "=" * 80
    dash = "-" * 80
    lines = [
        sep,
        "DECOMPRESSION RESULT",
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
    for i, w in enumerate(words_orig):
        w &= MASK
        lines.append(f"  [{i:2d}] 0x{w:08X}  ({w})")
    lines += [
        "",
        dash,
        "COMPRESSED INPUT (URZE payload)",
        dash,
        f"  key_in:     0x{key_in:08X}",
        f"  in_count:   {in_count}",
        "",
    ]
    key_bits = [i for i in range(WORD_SIZE) if (key_in >> i) & 1]
    if key_bits:
        lines.append("  key_in bit map (bit i = 1 => original bit-plane i was non-zero):")
        for i in key_bits:
            lines.append(f"    plane[{i:2d}] : NON-ZERO")
    else:
        lines.append("  key_in bit map: (all planes zero)")
    lines += ["", f"  packed_planes ({in_count} dense entries):"]
    if in_count == 0:
        lines.append("    (empty)")
    else:
        src = 0
        for p in range(in_count):
            while src < WORD_SIZE and not ((key_in >> src) & 1):
                src += 1
            plane = packed_planes[p] & ((1 << PLANE_WIDTH) - 1)
            lines.append(f"    [{p}] from plane[{src}]")
            lines.append(f"         hex: 0x{plane:016X}")
            lines.append(f"         bin: {plane:064b}")
            src += 1
    lines += [
        "",
        dash,
        "DECOMPRESSED OUTPUT (URZE -> BIT -> UNDIFFNB)",
        dash,
        f"RECOVERED PACKET ({PACKET_SIZE} x {WORD_SIZE}-bit words)",
        dash,
    ]
    for i, w in enumerate(words_recovered):
        w &= MASK
        lines.append(f"  [{i:2d}] 0x{w:08X}  ({w})")
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
        text = hw_path.read_text(encoding="utf-8")
        words_orig = parse_original_packet(text)
        key_in, in_count, packed = parse_compressed_input(text)
        recovered = decompress_packet_sw(packed, key_in, in_count)
        out_text = format_dump(
            source="SOFTWARE (decompressor_ref_pkg pipeline)",
            test_name=test_name,
            words_orig=words_orig,
            key_in=key_in,
            in_count=in_count,
            packed_planes=packed,
            words_recovered=recovered,
        )
        out = sw_dir / f"{test_name}.txt"
        out.write_text(out_text, encoding="utf-8")
        print(f"Wrote {out}")

    print(f"\nGenerated {len(hw_files)} SW file(s) in {sw_dir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())