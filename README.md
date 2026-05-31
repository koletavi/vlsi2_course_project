# posit-compress — Simple, Hardware-Friendly Posit Data Compression (Python Baseline)

A minimal, pure-Python, zero-dependency reference implementation of the best practical lossless compression pipeline for **posit-encoded** scientific data, designed from day one to be a readable golden model for manual conversion to hardware (RTL, Verilog, Chisel, etc.).

## Why this exists

The two papers in `references/` directly motivated this work:

- **Rodriguez & Burtscher (2025)** — "On the Compressibility of Floating-Point Data in Posit and IEEE-754 Representation" (SC Workshops / DRBSD).
  The first systematic study showing that posit bit patterns are highly compressible — often within a few percent of the original IEEE float data — and that the **LC framework** auto-synthesizes excellent custom pipelines for them.
  The single best general pipeline they measured on real SDRBench scientific data (CESM, HACC, NYX, etc.) converted to `posit<32,3>` was:

      DIFFNB → BIT → RZE

- **Jonnalagadda, Thotli, Gustafson et al. (2026)** — "Closing the Gap Between Float and Posit Hardware Efficiency".
  Introduces **b-posit** (bounded regime) that makes posit decode/encode dramatically cheaper in silicon than both classic posits and IEEE floats while preserving (or improving) numerical properties.
  The code style here deliberately copies the spirit of that paper: bounded cases, explicit widths, mux-friendly control logic, no deep sequential dependencies in the critical path.

The goal of *this* project is to give VLSI / architecture teams a **single-file, obviously correct, obviously mappable** software model of a strong posit-data compressor that a human can translate to hardware without fighting libraries or clever hacks.

## Algorithm (v1 — DIFFNB + RZE)

For maximum simplicity and hardware friendliness in the first version we ship the two highest-impact stages from the 2025 paper:

1. **DIFFNB** (predictor)
   - Compute delta = current − previous (as n-bit 2's-complement).
   - Re-encode the delta in **negabinary** (base −2).
   - Negabinary turns small positive *and* negative differences into patterns that are extremely rich in leading zeros — exactly what later reducers love.
   - First value is stored verbatim (standard for delta codecs).

2. **RZE** (reducer — the only stage that actually shrinks the data)
   - Build a 1-bit-per-word bitmap: `1` = "this word was non-zero (store it)".
   - Output the packed bitmap + the list of only the non-zero words.
   - Decoder is a trivial scatter (walk the bitmap, insert zeros or pull the next nonzero).

This combination alone already delivers excellent ratios on the exact workload class the papers care about (correlated scientific arrays, values clustered near 1.0 where posits are most accurate).

BIT (bit-transpose) is implemented and documented in the source as an optional advanced stage. Adding it to the default pipeline is a one-line change + 4 extra bytes in the header (the post-BIT word count) and is left as a clear follow-up.

## Usage

```python
from posit_compress import compress, decompress

# Your posit bit patterns (already in <n,es> format, as integers)
posit_words: list[int] = ...          # e.g. 10 000 values of 32-bit posit patterns

compressed = compress(posit_words, nbits=32, es=0, block_size=64)
restored   = decompress(compressed)

assert restored == posit_words
print(len(compressed) / (len(posit_words) * 4))   # compression ratio
```

Self-test (includes the exact cases from the 2025 paper's methodology):

```bash
python posit_compress.py --test
```

## File format (trivial for hardware)

32-byte little-endian header + simple RZE payload. No variable-length codes, no Huffman tables, no complex state. A hardware decompressor can be a few dozen lines of straightforward RTL (counters + a bitmap-driven scatter + a small negabinary-to-2's-complement converter).

See the top of `posit_compress.py` for the exact layout and the "HW mapping notes" comments on every stage.

## Parameters

- `nbits` — posit word width (v1 supports 8/16/32/64 for trivial byte packing; easy to generalize).
- `es` — exponent size (default **0** as requested). Stored in the header for metadata and future posit-semantic stages; does **not** affect the compression math today.
- `block_size` — only affects BIT (currently unused in the default pipeline).

## Verification & Quality

- Every stage has a pure-Python reference implementation + inverse.
- Full round-trip property tests on zero, ramp, sine (near-1.0), sparse patterns for multiple (nbits, es) including the paper's (32,3) and the requested default (32,0).
- Zero external dependencies (stdlib only: `struct` + `int` bit operations).
- Explicit "Hardware mapping notes" in the source for every non-trivial piece.
- Tested on Windows (PowerShell + CPython) exactly as the user environment.

## How to port this to hardware (checklist for the VLSI engineer)

1. **DIFFNB**
   - n-bit subtractor (or adder for the inverse).
   - Fixed-iteration negabinary converter (unroll the loop or make a tiny FSM; exactly `nbits` steps, data-independent).
   - First-word bypass mux.

2. **RZE**
   - Per-word zero detector + priority encoder / popcount for the bitmap.
   - Simple address generator + FIFO that only writes non-zero words.
   - Decoder is a bitmap walker + 2:1 mux (zero vs. next nonzero from FIFO). This is almost identical in spirit to the one-hot + mux logic in the b-posit decoder paper.

3. **BIT (when you add it)**
   - Pure wiring / bit-matrix transpose.
   - For 32×64 or 64×64 this is a few thousand wires and zero logic in the combinational case, or a handful of pipeline stages of 2:1 muxes.

4. **Header / framing**
   - Fixed 32-byte header with a few counters. Dead simple to parse in a DMA engine or stream unit.

5. **Optional future wins** (all still simple)
   - Add the BIT stage + one extra length field.
   - Separate compression of the regime bit planes (after a cheap posit unpacker) — the regime already contains run-length information.
   - Combine with a b-posit <n, rS=6, es=...> front-end so the whole storage path uses the cheaper bounded-regime format.

## Limitations / Future Work (documented, not hidden)

- v1 does not include BIT in the default pipeline (see comment in source).
- Negabinary implementation is the straightforward iterative version (correct and obvious; a hardware team can replace it with a faster combinational or pipelined version).
- The tiny `float <-> posit_bits` helpers (if you enable them) are for demo / testing only and are **not** correctly rounded. Real hardware will use the proper posit (or b-posit) encode/decode blocks anyway.
- No lossy path (the LC quantizers are separate preprocessors; the request was for a compression algorithm).

## References (must-read if you are implementing the hardware)

1. Andrew Rodriguez and Martin Burtscher. "On the Compressibility of Floating-Point Data in Posit and IEEE-754 Representation." SC Workshops 2025.
2. Aditya Anirudh Jonnalagadda et al. "Closing the Gap Between Float and Posit Hardware Efficiency." 2026 (b-posit).
3. The LC framework (Burtscher group) — https://github.com/burtscher/LC-framework (the component definitions for DIFFNB, BIT, RZE).

## License

BSD 3-Clause (same as the LC framework that inspired the stages).

---

This is the baseline. Make it hardware. Make it fast. Make it smaller than the equivalent IEEE-float compressor while giving your users better accuracy for the same storage.

Contributions and hardware ports welcome.