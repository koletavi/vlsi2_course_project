#!/usr/bin/env python3
"""
posit_compress.py - Best known simple posit-data compression baseline (Python reference)

Based on:
- Rodriguez & Burtscher, "On the Compressibility of Floating-Point Data in Posit and
  IEEE-754 Representation", SC Workshops / DRBSD 2025.
  The LC-synthesized pipeline DIFFNB -> BIT -> RZE was the best general-purpose
  combination measured on real scientific posit<32,3> data.

- Jonnalagadda et al., "Closing the Gap Between Float and Posit Hardware Efficiency"
  (b-posit, 2026). The code style deliberately mirrors the simplicity of the
  b-posit mux/priority-encoder decoder (bounded cases, explicit widths, no deep
  sequential logic in the hot path).

Goal: The simplest possible correct, round-trippable, HW-mappable implementation
for a human to later translate to RTL/Verilog/Chisel. Zero external dependencies.
Pure stdlib + int/bitwise only. es=0 default, fully configurable.

Usage (self-test):
    python posit_compress.py --test

Primary API:
    compress(posit_words: list[int], nbits=32, es=0, block_size=64) -> bytes
    decompress(data: bytes) -> list[int]

The compressor implements the complete 3-stage pipeline used by the hardware:
    DIFFNB (delta + cheap NB_MASK transform) -> BIT (per-packet bit transpose)
    -> RZE (zero-plane elimination on the transposed bit-planes, with group packing).

Designed for 32-bit words and 64-word packets (WORD_SIZE=32, PACKET_SIZE=64)
while remaining configurable. All stages are pure integer/bitwise and map
directly to the RTL blocks in compressor_hw/rtl/.

All internal stages operate on the raw posit bit patterns (re-interpreted as
unsigned integers of 'nbits' width). This is exactly what the 2025 paper did
with LC and is the most hardware-friendly approach (no need to decode regime/
exponent/fraction inside the compressor).
"""

from __future__ import annotations
import struct
import sys
import json
from typing import List, Tuple, Optional

# =============================================================================
# Binary format (little-endian, designed for trivial HW parsing)
# =============================================================================
#
# Offset  Size   Field
# 0       4      Magic: b'PZ01'
# 4       1      Version (1)
# 5       1      nbits (8,16,32,64 supported in v1 for simple byte packing)
# 6       1      es (0..8, stored for metadata / future posit-semantic stages)
# 7       1      (reserved, 0)
# 8       2      block_size (uint16)
# 10      6      (reserved, 0)
# 16      8      orig_word_count (uint64)
# 24      8      (reserved for future: e.g. b-posit rS or flags)
# 32      ...    Payload = RZE output of BIT(DIFFNB(input_words))
#
# RZE payload (after header) when using the full DIFFNB->BIT->RZE pipeline:
#   uint32  num_nonzero_planes
#   uint32  bitmap_nbytes
#   bitmap_nbytes bytes   (packed bitmap over the *plane slots* = nblocks*nbits ;
#                          bit i = 1 if the i-th bit-plane (across all packets) was NONZERO)
#   then exactly num_nonzero_planes * (block_size//8) bytes for the nonzero planes.
#     Each plane is a (block_size)-bit vector (e.g. 8 bytes for 64-word packets) stored LSB-first.
#
# The outer header still carries orig_word_count and block_size so the decompressor
# can compute the expected number of plane slots (nblocks * nbits) and trim the
# final partial packet back to the original word count.
#
# This layout is deliberately regular and has no variable-length codes inside
# the hot data path. It directly models the data produced by the RTL pipeline
# (diffnb -> bit_transpose -> rze with its key + packed nonzero planes + count).
# =============================================================================

MAGIC = b'PZ01'
VERSION = 1
HEADER_SIZE = 32

# Supported word sizes (must be multiple of 8 for trivial packing in v1)
SUPPORTED_NBITS = (8, 16, 32, 64)


# =============================================================================
# Low-level pack/unpack (nbits % 8 == 0)
# =============================================================================

def _word_to_bytes(w: int, nbits: int) -> bytes:
    """Pack one nbit word into exactly (nbits//8) little-endian bytes."""
    nbytes = nbits // 8
    return w.to_bytes(nbytes, 'little', signed=False)

def _bytes_to_word(b: bytes, nbits: int) -> int:
    """Unpack (nbits//8) little-endian bytes into one nbit word."""
    return int.from_bytes(b, 'little', signed=False)

def pack_words_to_bytes(words: List[int], nbits: int) -> bytes:
    """Pack a list of nbit words into a tight byte string."""
    if nbits not in SUPPORTED_NBITS:
        raise ValueError(f"nbits={nbits} not supported in v1 (must be in {SUPPORTED_NBITS})")
    nbytes = nbits // 8
    out = bytearray(len(words) * nbytes)
    for i, w in enumerate(words):
        out[i*nbytes : (i+1)*nbytes] = _word_to_bytes(w & ((1 << nbits) - 1), nbits)
    return bytes(out)

def unpack_bytes_to_words(b: bytes, nbits: int, count: int) -> List[int]:
    """Unpack exactly 'count' nbit words from bytes."""
    nbytes = nbits // 8
    if len(b) < count * nbytes:
        raise ValueError("truncated word data")
    mask = (1 << nbits) - 1
    return [int.from_bytes(b[i*nbytes:(i+1)*nbytes], 'little') & mask for i in range(count)]


# =============================================================================
# Stage 1: DIFFNB (delta + negabinary) - the key predictor for posit data
# =============================================================================
#
# HW mapping notes:
#   - Subtractor (current - previous) is a normal nbit subtractor.
#   - Negabinary conversion is a small iterative bit loop (or unrolled FSM in HW).
#     It has fixed iteration count = nbits, perfect for pipelining.
#   - First word is passed through (standard for delta codecs).
#   - Inverse is mathematically identical to forward (negabinary is its own
#     inverse under the same width-bounded procedure in this implementation).
#
# This matches the exact component used in the 2025 paper's best posit pipeline.

def _hw_nb_mask(width: int) -> int:
    """NB_MASK used by the hardware diffnb.sv: {width/2 {2'b10}} e.g. 0xAAAAAAAA for 32b."""
    if width <= 0 or (width % 2 != 0):
        raise ValueError("width must be positive and even for HW NB_MASK pattern")
    return int('10' * (width // 2), 2)

def diff_nb_encode(words: List[int], nbits: int) -> List[int]:
    """DIFFNB forward, *exactly* matching compressor_hw/rtl/diffnb.sv .

    delta[0] = in[0]
    delta[i] = in[i] - in[i-1]   (bit pattern subtract)
    nb[i]   = (delta[i] + NB_MASK) ^ NB_MASK   for every i (including 0)
    """
    if not words:
        return []
    mask = (1 << nbits) - 1
    NB_MASK = _hw_nb_mask(nbits)
    out: List[int] = []
    prev = words[0] & mask
    # Position 0: delta = raw word (as in HW)
    delta = prev
    nb = ((delta + NB_MASK) & mask) ^ NB_MASK
    out.append(nb)
    for w in words[1:]:
        curr = w & mask
        delta = (curr - prev) & mask
        nb = ((delta + NB_MASK) & mask) ^ NB_MASK
        out.append(nb)
        prev = curr
    return out

def diff_nb_decode(words: List[int], nbits: int) -> List[int]:
    """Inverse of the HW-matched diff_nb_encode."""
    if not words:
        return []
    mask = (1 << nbits) - 1
    NB_MASK = _hw_nb_mask(nbits)
    out: List[int] = []
    # Recover delta0
    nb0 = words[0] & mask
    delta = ((nb0 ^ NB_MASK) - NB_MASK) & mask
    prev = delta
    out.append(prev)
    for nb in words[1:]:
        delta = ((nb ^ NB_MASK) - NB_MASK) & mask
        curr = (prev + delta) & mask
        out.append(curr)
        prev = curr
    return out


# =============================================================================
# Stage 2: BIT (bit transpose / bit shuffle)
# =============================================================================
#
# HW mapping notes:
#   - Pure wiring / crossbar. For a block of B words of W bits this is a
#     B x W bit matrix transpose.
#   - In hardware this is literally "route bit (i,j) to position (j,i)".
#     No logic, only routing (or a small number of 2:1 muxes if pipelined).
#   - The fast version below uses the classic "swizzle" trick for 32/64-bit
#     words and power-of-2 blocks; still pure integer ops.

def bit_transpose_encode(words: List[int], nbits: int, block_size: int) -> List[int]:
    """BIT forward on blocks of 'block_size' words.
    Emits exactly nbits 'plane' values per block (MSB plane first).
    Each plane value uses the low 'blk_len' bits.
    """
    if not words:
        return []
    mask = (1 << nbits) - 1
    out: List[int] = []
    for start in range(0, len(words), block_size):
        raw_block = [w & mask for w in words[start : start + block_size]]
        blk_len = len(raw_block)
        # Always process a full block_size "packet" (pad trailing positions with 0).
        # This matches the fixed PACKET_SIZE arrays in hardware.
        block = raw_block + [0] * (block_size - blk_len) if blk_len < block_size else raw_block
        full_len = block_size
        for bitpos in range(nbits - 1, -1, -1):  # MSB first
            plane = 0
            for i in range(full_len):
                if (block[i] >> bitpos) & 1:
                    plane |= (1 << i)
            out.append(plane & ((1 << full_len) - 1))
    return out

def bit_transpose_decode(planes: List[int], nbits: int, block_size: int) -> List[int]:
    """Inverse of bit_transpose_encode.
    We know how many original words existed because the caller tracks orig_count.
    Here we reconstruct block-by-block using the fact that we emitted exactly
    nbits planes per original block.
    """
    if not planes:
        return []
    out: List[int] = []
    plane_idx = 0
    while plane_idx < len(planes):
        remaining_planes = len(planes) - plane_idx
        planes_this_block = min(nbits, remaining_planes)
        if planes_this_block == 0:
            break

        # Encoder always emitted using the full block_size packet dimension (with 0 pads).
        # We therefore always reconstruct exactly block_size words per group of nbits planes.
        # The caller (top-level decompress) trims the final list using the stored orig_count.
        blk_len = block_size

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
# Stage 3: RZE (zero-run / bitmap reducer)
# =============================================================================
#
# HW mapping notes:
#   - Bitmap generation = per-word zero test + bit-set (trivial).
#   - Packing nonzeros = simple FIFO + address generator driven by bitmap popcount.
#   - This is the only stage that actually reduces size.
#   - Decoder is a scatter: for each bit in bitmap, if 1 emit next nonzero,
#     else emit 0. Extremely regular control (counter + mux).

def rze_encode(words: List[int], nbits: int) -> Tuple[bytes, bytes, int]:
    """
    RZE forward.
    Returns: (packed_bitmap, packed_nonzero_words, original_count)
    Bitmap bit i == 1  means  "word i was NON-ZERO" (so we store it).
    This matches the exact definition in the LC README and the 2025 paper.
    """
    count = len(words)
    if count == 0:
        return b'', b'', 0

    # Build bitmap as a big integer then to bytes (simple & correct)
    bitmap_int = 0
    nonzeros: List[int] = []
    for i, w in enumerate(words):
        if w != 0:
            bitmap_int |= (1 << i)
            nonzeros.append(w)

    nbytes_bitmap = (count + 7) // 8
    bitmap_bytes = bitmap_int.to_bytes(nbytes_bitmap, 'little')

    nonzero_bytes = pack_words_to_bytes(nonzeros, nbits) if nonzeros else b''
    return bitmap_bytes, nonzero_bytes, count

def rze_decode(bitmap: bytes, nonzeros: bytes, count: int, nbits: int) -> List[int]:
    """Inverse of rze_encode."""
    if count == 0:
        return []

    bitmap_int = int.from_bytes(bitmap, 'little')
    nonzero_list = unpack_bytes_to_words(nonzeros, nbits, (nonzeros.__len__() * 8) // nbits) if nonzeros else []

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
# Top-level compress / decompress
# =============================================================================

def compress(posit_words: List[int], nbits: int = 32, es: int = 0,
             block_size: int = 64) -> bytes:
    """
    Full posit-optimized compression (DIFFNB -> BIT -> RZE).
    Returns a self-describing byte string (header + payload).
    """
    if nbits not in SUPPORTED_NBITS:
        raise ValueError(f"nbits must be one of {SUPPORTED_NBITS}")
    if not (0 <= es <= 8):
        raise ValueError("es must be 0..8")
    if block_size <= 0 or block_size > 65535:
        raise ValueError("block_size must be 1..65535")

    orig_count = len(posit_words)
    if orig_count == 0:
        # Minimal header for empty input
        return struct.pack('<4sBBBBH6sQ8s', MAGIC, VERSION, nbits, es, 0,
                           block_size, b'\0'*6, 0, b'\0'*8)

    # Full 3-stage pipeline as implemented in hardware (compressor_hw/rtl/compressor.sv):
    #   DIFFNB (hw NB) -> BIT (bit_transpose per 64-word packet) -> RZE (plane packing)
    # We process the input in block_size (64-word) packets so that BIT + RZE
    # operate exactly as the RTL (32-bit words + 64-word packets by default).
    stage1 = diff_nb_encode(posit_words, nbits)
    stage2 = bit_transpose_encode(stage1, nbits, block_size)

    # RZE is now applied to the *planes* produced by BIT.
    # - There are (approximately) nbits planes per block.
    # - Each plane value is conceptually 'block_size' bits wide.
    #   We pass block_size as the item storage width to rze so that nonzero planes
    #   are packed as (block_size//8) bytes each (8 bytes for 64-word packets).
    plane_item_width = block_size
    bitmap_b, nz_b, _ = rze_encode(stage2, plane_item_width)

    # Assemble header + payload.
    # The inner (num_nz, bitmap_nbytes) now refers to nonzero *planes* (not original words).
    # The bitmap covers the plane slots (num_blocks * nbits bits total).
    header = struct.pack('<4sBBBBH6sQ8s',
                         MAGIC, VERSION, nbits, es, 0,
                         block_size, b'\0'*6, orig_count, b'\0'*8)
    num_nz_planes = (len(nz_b) // (plane_item_width // 8)) if nz_b else 0
    payload = struct.pack('<II', num_nz_planes, len(bitmap_b)) + bitmap_b + nz_b
    return header + payload

def decompress(data: bytes) -> List[int]:
    """Recover the original list of posit bit patterns."""
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

    # Reconstruct full DIFFNB <- BIT <- RZE pipeline (all 3 steps).
    # After BIT we have (num_blocks * nbits) "plane slots".
    # RZE (in this mode) was applied to those planes; each plane is stored
    # using (block_size // 8) bytes.
    nblocks = (orig_count + block_size - 1) // block_size if block_size > 0 else 1
    plane_slots = nblocks * nbits
    plane_item_width = block_size

    # rze_decode's 4th arg is used as the item width for unpacking the nonzero planes.
    # We pass block_size so the nz planes (64-bit for 64-word packets) are unpacked correctly.
    planes = rze_decode(bitmap, nz_bytes, plane_slots, plane_item_width)

    # Invert bit transpose (per block) to recover the post-DIFFNB words
    stage1 = bit_transpose_decode(planes, nbits, block_size)

    # Final DIFFNB inverse
    words = diff_nb_decode(stage1, nbits)
    # The bit-transpose decoder may return a padded length for the last block; trim.
    if len(words) > orig_count:
        words = words[:orig_count]
    return words


# =============================================================================
# File I/O utilities for saving/loading results
# =============================================================================

def save_words_to_txt(words: List[int], filename: str) -> None:
    """Save a list of words as JSON to a text file."""
    with open(filename, 'w') as f:
        json.dump({"words": words, "count": len(words)}, f, indent=2)
    print(f"Saved {len(words)} words to {filename}")

def load_words_from_txt(filename: str) -> List[int]:
    """Load a list of words from a JSON text file."""
    with open(filename, 'r') as f:
        data = json.load(f)
    words = data.get("words", [])
    print(f"Loaded {len(words)} words from {filename}")
    return words

def save_compression_result(original_words: List[int], compressed_bytes: bytes, 
                            filename: str, nbits: int, es: int) -> None:
    """Save compression result with metadata to a text file."""
    result = {
        "compression_result": {
            "original_count": len(original_words),
            "original_bytes": len(original_words) * (nbits // 8),
            "compressed_bytes": len(compressed_bytes),
            "compression_ratio": len(compressed_bytes) / max(1, len(original_words) * (nbits // 8)),
            "nbits": nbits,
            "es": es,
            "original_words": original_words,
            "compressed_hex": compressed_bytes.hex()
        }
    }
    with open(filename, 'w') as f:
        json.dump(result, f, indent=2)
    print(f"Saved compression result to {filename}")
    print(f"  Original: {result['compression_result']['original_bytes']} bytes")
    print(f"  Compressed: {result['compression_result']['compressed_bytes']} bytes")
    print(f"  Ratio: {result['compression_result']['compression_ratio']:.3f}")

def load_compression_result(filename: str) -> Tuple[List[int], bytes, int, int]:
    """Load compression result from text file. Returns (words, compressed_bytes, nbits, es)."""
    with open(filename, 'r') as f:
        data = json.load(f)
    result = data["compression_result"]
    words = result["original_words"]
    compressed = bytes.fromhex(result["compressed_hex"])
    return words, compressed, result["nbits"], result["es"]


# =============================================================================
# Self-test and CLI
# =============================================================================

def _make_synthetic(n: int, nbits: int, kind: str = "sine") -> List[int]:
    """Tiny synthetic generators that produce posit-like bit patterns."""
    import math
    mask = (1 << nbits) - 1
    if kind == "zero":
        return [0] * n
    if kind == "ramp":
        return [(i * 17) & mask for i in range(n)]
    if kind == "sine":
        # Values clustered near "1.0" (small regimes for es=0/2/3)
        out = []
        for i in range(n):
            v = int(0.97 + 0.03 * math.sin(i * 0.0314159) * 1000) & mask
            out.append(v)
        return out
    if kind == "sparse":
        out = [0] * n
        for i in range(0, n, 7):
            out[i] = (0xA5 << (nbits // 2)) & mask
        return out
    return [(i & 0xFF) for i in range(n)]  # fallback

def self_test(verbose: bool = True) -> bool:
    """Run comprehensive roundtrip and edge-case tests. Returns True on success."""
    ok = True
    test_cases = [
        (32, 0, 64, "zero"),
        (32, 0, 64, "ramp"),
        (32, 0, 1000, "sine"),
        (32, 3, 64, "sine"),      # matches paper's es=3 experiments
        (16, 0, 200, "sparse"),
        (8, 0, 50, "ramp"),
        (64, 0, 30, "sine"),
    ]

    for nbits, es, length, kind in test_cases:
        words = _make_synthetic(length, nbits, kind)
        comp = compress(words, nbits=nbits, es=es, block_size=64)
        rec = decompress(comp)
        if rec != words:
            print(f"FAIL roundtrip: nbits={nbits} es={es} kind={kind} len={length}")
            ok = False
            continue
        if verbose:
            ratio = len(comp) / max(1, (length * (nbits // 8)))
            print(f"OK  n={nbits} es={es} {kind:5s} len={length:5d}  comp={len(comp):6d}B  ratio={ratio:.3f}")

    # Header fidelity spot check
    words = _make_synthetic(17, 32, "sine")
    c = compress(words, 32, 0, 32)
    assert c[0:4] == MAGIC
    assert c[4] == VERSION
    assert c[5] == 32
    assert c[6] == 0
    assert struct.unpack('<H', c[8:10])[0] == 32
    assert struct.unpack('<Q', c[16:24])[0] == 17

    if ok and verbose:
        print("\nAll self-tests PASSED.")
    return ok

def main(argv: Optional[List[str]] = None) -> int:
    argv = argv or sys.argv[1:]
    if "--test" in argv or "-t" in argv:
        return 0 if self_test() else 1
    if "--help" in argv or "-h" in argv or not argv:
        print(__doc__)
        print("Commands:\n"
              "  python posit_compress.py --test                                        Run built-in verification\n"
              "  python posit_compress.py --compress <input.txt> <output.txt>          Compress and save result\n"
              "                            [--nbits 32] [--es 0]\n"
              "  python posit_compress.py --decompress <input.txt> <output.txt>        Decompress and save result\n"
              "  python posit_compress.py                                              Show this help\n"
              "\nFile format: JSON with word arrays and metadata")
        return 0
    
    # Handle --compress command
    if "--compress" in argv:
        try:
            idx = argv.index("--compress")
            if idx + 2 >= len(argv):
                print("Error: --compress requires <input_file> <output_file>")
                return 1
            input_file = argv[idx + 1]
            output_file = argv[idx + 2]
            nbits = 32  # default
            es = 0      # default
            # Check for optional --nbits and --es arguments
            if "--nbits" in argv:
                nbits_idx = argv.index("--nbits")
                if nbits_idx + 1 < len(argv):
                    nbits = int(argv[nbits_idx + 1])
            if "--es" in argv:
                es_idx = argv.index("--es")
                if es_idx + 1 < len(argv):
                    es = int(argv[es_idx + 1])
            words = load_words_from_txt(input_file)
            compressed = compress(words, nbits=nbits, es=es)
            save_compression_result(words, compressed, output_file, nbits, es)
            return 0
        except FileNotFoundError as e:
            print(f"Error: {e}")
            return 1
        except Exception as e:
            print(f"Error during compression: {e}")
            return 1
    
    # Handle --decompress command
    if "--decompress" in argv:
        try:
            idx = argv.index("--decompress")
            if idx + 2 >= len(argv):
                print("Error: --decompress requires <input_file> <output_file>")
                return 1
            input_file = argv[idx + 1]
            output_file = argv[idx + 2]
            words, compressed, nbits, es = load_compression_result(input_file)
            decompressed = decompress(compressed)
            save_words_to_txt(decompressed, output_file)
            if decompressed == words:
                print("✓ Roundtrip verification PASSED")
            else:
                print("✗ Roundtrip verification FAILED")
                return 1
            return 0
        except FileNotFoundError as e:
            print(f"Error: {e}")
            return 1
        except Exception as e:
            print(f"Error during decompression: {e}")
            return 1
    
    print("Unknown arguments. Use --test, --compress, --decompress, or --help.")
    return 1

if __name__ == "__main__":
    sys.exit(main())
