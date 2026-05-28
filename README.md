# 16-bit Posit Compressor (The Best One)

Pure-Python, 100% bitwise, hardware-mirroring implementation of the **best known 16-bit posit compressor (encoder/packer)** algorithm.

**Primary configuration (user requirement):** `<16, rs=6, es=0>` b-posit  
→ Maximum fraction bits near |x| ≈ 1 ("best precision near zero").

Based on the 2026 state-of-the-art paper:
> **"Closing the Gap Between Float and Posit Hardware Efficiency"**  
> Aditya Anirudh Jonnalagadda, Rishi Thotli, John L. Gustafson  
> arXiv:2603.01615

## Why This Is the Best

Standard posit encoders require leading-bit counters + barrel shifters + variable-length logic.  
The **b-posit** (bounded-regime) version limits the regime to 6 bits → only **5 possible widths**.

Result (paper, 45 nm post-layout, 16-bit encoder):

| Design              | Power | Area   | Delay |
|---------------------|-------|--------|-------|
| Standard posit<16,2> | 0.26 mW | 610 µm² | 0.71 ns |
| **b-posit (this algo)** | **0.13 mW** | **418 µm²** | **0.39 ns** |
| IEEE float16        | 0.06 mW | 297 µm² | 0.29 ns |

The b-posit version is ~2× better than a classic posit encoder in every metric while preserving (and often improving) posit's accuracy advantages for AI/HPC workloads. It is also competitive with IEEE float hardware.

Later work (EULER-ADAS, arXiv:2605.06875) adopted the same bounded-encoder ideas.

## What You Get

- `compress(sign, regime_k, exp, frac, g, r, s, cfg)` — **the core algorithm**
  - Pure integer/bitwise only (shifts, masks, XOR, 5 explicit cases)
  - Direct transliteration of paper Fig. 13 + Tables 3 & 4
  - Ready for 1:1 Verilog port (no magic Python tricks)

- Full b-posit16 decoder (symmetric)
- float ↔ posit helpers (for test vectors and demos)
- CLI for quick experiments
- Tests that exercise every one of the 5 hardware MUX cases
- `paper_trace.md` — line-by-line mapping from this code to the paper (for the VLSI designer)

## Quick Start (Windows PowerShell)

```powershell
cd C:\Users\kolet\projects\vlsi2

# Demo (es=0 = best precision near zero)
python posit_compressor.py

# Specific encode / decode
python posit_compressor.py --encode 3.14159 --format b16e0
python posit_compressor.py --decode 0x2C91 --format b16e0
```

No external packages required for the core compressor.

## The Compressor API (What Goes into RTL)

```python
from posit_compressor import compress, B16   # <16,6,0> es=0 = best precision

# After your posit arithmetic unit has produced:
#   sign (0/1)
#   regime_k (signed integer, roughly -6..+5)
#   exp (0..2**es-1)
#   frac (normalized fraction bits, hidden 1 already removed)
#   g, r, s (guard/round/sticky for rounding)

bits = compress(sign, regime_k, exp, frac, g, r, s, cfg=B16)
# bits is a 16-bit integer ready to write to a register / memory
```

All internal operations inside `compress` are shifts, masks, XORs and five `if size == N:` branches — exactly what you want in a Verilog `always @*` block.

## Verilog Porting Guide

See `paper_trace.md` for the detailed mapping.

High-level recipe:

1. The 5-case logic + `temp` generation becomes a 5-to-1 MUX with one-hot select.
2. The 3-to-6 decoder is a tiny combinational block (6 AND/NOT gates).
3. All shifts are constant (2..6 bits) — no barrel shifter needed.
4. With `es=0` (recommended) the exponent field disappears from the critical path for the common cases.
5. Rounding decision is pure combinational on the three round bits + LSB (classic round-to-nearest-even).

The Python code was deliberately written to be the simplest possible faithful rendering of the paper so that the correspondence is obvious.

## Project Layout

```
vlsi2/
├── posit_compressor.py     # The entire implementation (single file, VLSI-friendly)
├── README.md
├── paper_trace.md          # Exact mapping to arXiv:2603.01615
├── tests/
│   └── test_posit_compressor.py
└── (future)                # Your Verilog implementation of the same algorithm
```

## References

- Primary paper: https://arxiv.org/abs/2603.01615
- Follow-up using the same ideas: EULER-ADAS (arXiv:2605.06875)
- Posit Standard (2022): https://posithub.org

## Status

The **compressor algorithm itself** (the part that matters for VLSI2) is complete, tested, and matches the paper's structure.

The Python float<->posit conversion layer is "good enough" for generating test vectors and demos. In a real flow you will drive the compressor directly from your fixed-point posit arithmetic datapath.

---

Built for Avishai Kolet's VLSI2 project (follow-up to the systolic-array configurable PE work).
