#!/usr/bin/env python3
"""
posit_decompress.py - Standalone decompressor for the posit data compression format.

Based on the compressor implementation in ../compressor_sw/posit_compress.py
Implements the inverse of DIFFNB -> RZE pipeline (BIT stage present for future
but not used in v1 default path).

Produces JSON txt output files with the recovered posit word bit patterns.

Usage:
    python posit_decompress.py --decompress <input_compression_result.txt> <output_words.txt>
    python posit_decompress.py                 # bare run: demo using ../compressor_sw/test_output.txt and write txt outputs here

Primary API:
    decompress(data: bytes) -> list[int]

File outputs are written to the same directory as this script.
"""

from __future__ import annotations
import struct
import sys
import json
import os
from typing import List, Tuple, Optional

# =============================================================================
# Binary format (little-endian) - mirrors compressor
# =============================================================================
MAGIC = b'PZ01'
VERSION = 1
HEADER_SIZE = 32

SUPPORTED_NBITS = (8, 16, 32, 64)


# =============================================================================
# Low-level pack/unpack (nbits % 8 == 0)
# =============================================================================

def _bytes_to_word(b: bytes, nbits: int) -> int:
    """Unpack (nbits//8) little-endian bytes into one nbit word."""
    return int.from_bytes(b, 'little', signed=False)


def unpack_bytes_to_words(b: bytes, nbits: int, count: int) -> List[int]:
    """Unpack exactly 'count' nbit words from bytes."""
    nbytes = nbits // 8
    if len(b) < count * nbytes:
        raise ValueError("truncated word data")
    mask = (1 << nbits) - 1
    return [int.from_bytes(b[i*nbytes:(i+1)*nbytes], 'little') & mask for i in range(count)]


# =============================================================================
# Stage 1 inverse: DIFFNB (negabinary delta decoder)
# =============================================================================

def _from_negabinary(bits: int, width: int) -> int:
    """
    Inverse of negabinary encoder.
    Evaluates the base -2 polynomial to recover the 2's-complement value.
    """
    mask = (1 << width) - 1
    bits &= mask
    val = 0
    power = 1  # (-2)^0
    for i in range(width):
        if (bits >> i) & 1:
            val += power
        power *= -2
    return val & mask


def diff_nb_decode(words: List[int], nbits: int) -> List[int]:
    """Inverse of diff_nb_encode."""
    if not words:
        return []
    mask = (1 << nbits) - 1
    out: List[int] = [words[0] & mask]
    prev = words[0] & mask
    for nb in words[1:]:
        signed_diff = _from_negabinary(nb, nbits)
        if signed_diff & (1 << (nbits - 1)):
            signed_diff -= (1 << nbits)
        curr = (prev + signed_diff) & mask
        out.append(curr)
        prev = curr
    return out


# =============================================================================
# Stage 2 inverse: BIT (bit transpose decoder) - included for completeness
# =============================================================================

def bit_transpose_decode(planes: List[int], nbits: int, block_size: int) -> List[int]:
    """Inverse of bit_transpose_encode (unused in v1 default pipeline)."""
    if not planes:
        return []
    out: List[int] = []
    plane_idx = 0
    while plane_idx < len(planes):
        remaining_planes = len(planes) - plane_idx
        planes_this_block = min(nbits, remaining_planes)
        if planes_this_block == 0:
            break

        first_plane = planes[plane_idx]
        blk_len = first_plane.bit_length()
        if blk_len == 0:
            blk_len = 1
        blk_len = min(blk_len, block_size)

        block_out = [0] * blk_len
        for bp in range(nbits - 1, -1, -1):
            if plane_idx >= len(planes):
                break
            plane = planes[plane_idx]
            plane_idx += 1
            for i in range(blk_len):
                if (plane >> i) & 1:
                    block_out[i] |= (1 << bp)
        out.extend(block_out)
    return out


# =============================================================================
# Stage 3 inverse: RZE (zero-run / bitmap scatter)
# =============================================================================

def rze_decode(bitmap: bytes, nonzeros: bytes, count: int, nbits: int) -> List[int]:
    """Inverse of rze_encode. Scatter nonzeros according to bitmap."""
    if count == 0:
        return []

    bitmap_int = int.from_bytes(bitmap, 'little')
    nonzero_list = (
        unpack_bytes_to_words(nonzeros, nbits, (len(nonzeros) * 8) // nbits)
        if nonzeros else []
    )

    out: List[int] = []
    nz_idx = 0
    for i in range(count):
        if (bitmap_int >> i) & 1:
            out.append(nonzero_list[nz_idx])
            nz_idx += 1
        else:
            out.append(0)
    return out


# =============================================================================
# Top-level decompress
# =============================================================================

def decompress(data: bytes) -> List[int]:
    """Recover the original list of posit bit patterns from compressed bytes."""
    if len(data) < HEADER_SIZE:
        raise ValueError("truncated header")

    magic, version, nbits, es, _, block_size, _, orig_count, _ = \
        struct.unpack('<4sBBBBH6sQ8s', data[:HEADER_SIZE])

    if magic != MAGIC or version != VERSION:
        raise ValueError("bad magic or version")
    if nbits not in SUPPORTED_NBITS:
        raise ValueError(f"unsupported nbits={nbits}")
    if orig_count == 0:
        return []

    payload = data[HEADER_SIZE:]
    if len(payload) < 8:
        raise ValueError("truncated RZE header")
    num_nz, bitmap_nbytes = struct.unpack('<II', payload[:8])
    bitmap = payload[8 : 8 + bitmap_nbytes]
    nz_bytes = payload[8 + bitmap_nbytes :]

    # Reverse pipeline: RZE then DIFFNB (BIT not applied in v1)
    stage1 = rze_decode(bitmap, nz_bytes, orig_count, nbits)
    words = diff_nb_decode(stage1, nbits)
    return words


# =============================================================================
# File I/O utilities (txt outputs in same directory)
# =============================================================================

def save_words_to_txt(words: List[int], filename: str) -> None:
    """Save a list of words as JSON to a text file (in CWD / script dir)."""
    with open(filename, 'w') as f:
        json.dump({"words": words, "count": len(words)}, f, indent=2)
    print(f"Saved {len(words)} words to {os.path.abspath(filename)}")


def load_compression_result(filename: str) -> Tuple[List[int], bytes, int, int]:
    """Load compression result (from compressor output txt). Returns (words, compressed_bytes, nbits, es)."""
    with open(filename, 'r') as f:
        data = json.load(f)
    result = data["compression_result"]
    words = result.get("original_words", [])
    compressed = bytes.fromhex(result["compressed_hex"])
    return words, compressed, result["nbits"], result["es"]


def load_raw_compressed(filename: str) -> bytes:
    """Load raw compressed bytes (for future .bin or direct use)."""
    with open(filename, 'rb') as f:
        return f.read()


# =============================================================================
# Self-test / verification using the exact pipeline inverse
# =============================================================================

def self_test(verbose: bool = True) -> bool:
    """Minimal roundtrip sanity using synthetic data (no external files)."""
    # We re-implement a tiny compress subset here only for the self-test of the decompressor
    # to stay self-contained. This mirrors the active v1 pipeline in the compressor.
    def _to_negabinary(val: int, width: int) -> int:
        mask = (1 << width) - 1
        result = 0
        v = val
        for i in range(width):
            rem = v % -2
            if rem < 0:
                rem += 2
            bit = 1 if rem == 1 else 0
            result |= (bit << i)
            v = (v - rem) // -2
        return result & mask

    def diff_nb_encode(words: List[int], nbits: int) -> List[int]:
        if not words:
            return []
        mask = (1 << nbits) - 1
        out: List[int] = [words[0] & mask]
        prev = words[0] & mask
        for w in words[1:]:
            curr = w & mask
            diff = (curr - prev) & mask
            if diff & (1 << (nbits - 1)):
                signed_diff = diff - (1 << nbits)
            else:
                signed_diff = diff
            nb = _to_negabinary(signed_diff, nbits)
            out.append(nb)
            prev = curr
        return out

    def rze_encode(words: List[int], nbits: int):
        count = len(words)
        if count == 0:
            return b'', b'', 0
        bitmap_int = 0
        nonzeros: List[int] = []
        for i, w in enumerate(words):
            if w != 0:
                bitmap_int |= (1 << i)
                nonzeros.append(w)
        nbytes_bitmap = (count + 7) // 8
        bitmap_bytes = bitmap_int.to_bytes(nbytes_bitmap, 'little')
        nbytes = nbits // 8
        nz_bytes = b''.join(w.to_bytes(nbytes, 'little') for w in nonzeros)
        return bitmap_bytes, nz_bytes, count

    def compress_local(posit_words: List[int], nbits: int = 32) -> bytes:
        if nbits not in SUPPORTED_NBITS:
            raise ValueError(f"nbits must be one of {SUPPORTED_NBITS}")
        orig_count = len(posit_words)
        if orig_count == 0:
            return struct.pack('<4sBBBBH6sQ8s', MAGIC, VERSION, nbits, 0, 0,
                               64, b'\0'*6, 0, b'\0'*8)
        stage1 = diff_nb_encode(posit_words, nbits)
        bitmap_b, nz_b, _ = rze_encode(stage1, nbits)
        header = struct.pack('<4sBBBBH6sQ8s',
                             MAGIC, VERSION, nbits, 0, 0,
                             64, b'\0'*6, orig_count, b'\0'*8)
        payload = struct.pack('<II', len(nz_b) // (nbits // 8) if nz_b else 0,
                              len(bitmap_b)) + bitmap_b + nz_b
        return header + payload

    ok = True
    test_cases = [
        (32, 0, 64, "ramp"),
        (32, 0, 31, "sparse"),
        (16, 0, 17, "ramp"),
    ]
    for nbits, es, length, kind in test_cases:
        # simple synthetic
        mask = (1 << nbits) - 1
        if kind == "ramp":
            words = [(i * 17) & mask for i in range(length)]
        else:
            words = [0] * length
            for i in range(0, length, 7):
                words[i] = (0xA5 << (nbits // 2)) & mask

        comp = compress_local(words, nbits=nbits)
        rec = decompress(comp)
        if rec != words:
            print(f"FAIL self-test roundtrip: nbits={nbits} kind={kind} len={length}")
            ok = False
        elif verbose:
            print(f"OK  self-test n={nbits} {kind:6s} len={length:3d}")

    if ok and verbose:
        print("Decompressor self-tests PASSED.")
    return ok


# =============================================================================
# CLI and demo that generates txt outputs in this directory
# =============================================================================

def main(argv: Optional[List[str]] = None) -> int:
    argv = argv or sys.argv[1:]
    script_dir = os.path.dirname(os.path.abspath(__file__))

    if "--test" in argv or "-t" in argv:
        return 0 if self_test() else 1

    if "--help" in argv or "-h" in argv:
        print(__doc__)
        print("Commands:\n"
              "  python posit_decompress.py --test\n"
              "  python posit_decompress.py --decompress <compression_result.txt> <output_words.txt>\n"
              "  python posit_decompress.py   # bare invocation runs demo using ../compressor_sw/test_output.txt\n")
        return 0

    # No explicit command flags: run the demo that generates txt files in this directory.
    if not any(a.startswith("--") for a in argv):
        pass  # fall through to demo below
    else:
        # Unknown flag combination
        print("Unknown arguments. Use --test, --decompress, --help, or run with no arguments for demo.")
        return 1

    # Explicit decompress of a compression_result JSON (produced by compressor)
    if "--decompress" in argv:
        try:
            idx = argv.index("--decompress")
            if idx + 2 >= len(argv):
                print("Error: --decompress requires <input_file> <output_file>")
                return 1
            input_file = argv[idx + 1]
            output_file = argv[idx + 2]
            orig_words, compressed, nbits, es = load_compression_result(input_file)
            decompressed = decompress(compressed)
            # Always write output relative to this script's directory
            out_path = output_file if os.path.isabs(output_file) else os.path.join(script_dir, output_file)
            save_words_to_txt(decompressed, out_path)
            if decompressed == orig_words:
                print("✓ Roundtrip verification PASSED")
            else:
                print("✗ Roundtrip verification FAILED")
                return 1
            return 0
        except Exception as e:
            print(f"Error during decompression: {e}")
            return 1

    # Default behavior: generate output txt files in the same (decompressor_sw) directory
    # by decompressing the known test data produced by the compressor.
    print("No arguments supplied - running demo to generate txt outputs in this directory...")
    try:
        # Locate the test compression result from the compressor_sw sibling
        compressor_dir = os.path.abspath(os.path.join(script_dir, "..", "compressor_sw"))
        test_output = os.path.join(compressor_dir, "test_output.txt")

        if not os.path.exists(test_output):
            print(f"Could not find {test_output}")
            print("Falling back to internal self-test only.")
            self_test()
            return 0

        orig_words, compressed, nbits, es = load_compression_result(test_output)
        decompressed = decompress(compressed)

        # Generate outputs directly in decompressor_sw (script dir)
        out_words = os.path.join(script_dir, "test_decompressed.txt")
        save_words_to_txt(decompressed, out_words)

        # Also generate a clean "decompressed_output.txt" (simple list of recovered words)
        clean_out = os.path.join(script_dir, "decompressed_output.txt")
        with open(clean_out, 'w') as f:
            json.dump({"words": decompressed, "count": len(decompressed), "nbits": nbits, "es": es}, f, indent=2)
        print(f"Saved clean decompressed output to {os.path.abspath(clean_out)}")

        # Verification against the original words stored in the compression result
        if decompressed == orig_words:
            print("✓ Demo roundtrip verification PASSED (matches original from compressor)")
        else:
            print("✗ Demo roundtrip verification FAILED")
            # Still write a mismatch report for debugging
            mismatch = os.path.join(script_dir, "decompress_mismatch.txt")
            with open(mismatch, 'w') as f:
                f.write("Decompressed does not match original words\n")
                for i, (d, o) in enumerate(zip(decompressed, orig_words)):
                    if d != o:
                        f.write(f"index {i}: got {d} expected {o}\n")
            print(f"Wrote details to {mismatch}")
            return 1

        # Extra: also write a tiny "recovered_posit_words.txt" alias for convenience
        alias = os.path.join(script_dir, "recovered_posit_words.txt")
        save_words_to_txt(decompressed, alias)

        print("\nGenerated files in decompressor_sw/:")
        print("  - test_decompressed.txt")
        print("  - decompressed_output.txt")
        print("  - recovered_posit_words.txt")
        return 0

    except Exception as e:
        print(f"Demo failed: {e}")
        import traceback
        traceback.print_exc()
        return 1


if __name__ == "__main__":
    sys.exit(main())
