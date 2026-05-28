# Paper Trace: b-posit Compressor Implementation

This file maps the Python code in `posit_compressor.py` directly to the
"Closing the Gap Between Float and Posit Hardware Efficiency" paper
(arXiv:2603.01615, §3.2, Fig. 13, Tables 3 & 4).

The goal is that a hardware designer can look at this file + the paper and
instantly see the corresponding RTL.

## Core Compressor Function
- `compress()` (public entry) + `_compress_bposit()`  
  → This is the "Proposed B-Posit Encoder" block in Fig. 13.

## Regime Size + MUX Select Generation (Table 3)
- `_regime_size_and_select(reg_val)`  
  Implements the "three least significant bits of the regime value are XORed
  with its most significant bit (MSB)" step + the mapping in Table 3.
  The returned `temp` (3-bit) is exactly the select signal for the 5-way packing MUX.

## 3-to-6 Decoder + Intermediate Regime String (Table 4)
- `_generate_intermediate_regime_string(temp)`  
  Exact combinational 3-to-6 decoder described in the paper.
  Output is 0-padded on MSB to form the 7-bit intermediate string.

- `_extract_regime_bits(interm, size)`  
  Selects the correct prefix length (2..6 bits) from the 7-bit string per Table 4.

## Sign Transform & Exponent Handling
- `_apply_sign_to_regime(...)` → "The final regime is then obtained through an XOR
  operation involving the regime MSB and the sign bit" (paper).
- `_handle_exp_sign_transform(...)` → 1's complement (every bit XOR sign) + the
  special +1 cin when sign=1 and fraction=0.

## 5-Way Packing MUX (Fig. 13)
- The final assembly of `sign + final_reg (size bits) + final_exp + rounded_frac`
  inside `_compress_bposit` is the 5-input MUX.
  For es=0 (user-chosen "best precision near 0") the structure is even simpler:
  no exponent field in the common case.

## Rounding
- `_round_nearest_even()` implements the only posit rounding mode
  (round-to-nearest, ties-to-even) using guard/round/sticky exactly as required
  before the final packing step.

## Decoder (for symmetry / test vectors)
- The decoder in the same file mirrors the paper's §3.1 one-hot + 5-way tap MUX
  + priority encoder structure (simplified Python version for verification only).

## Why This Is "The Best"
See paper abstract + §4 results:
- 16-bit b-posit encoder (this algorithm): 0.13 mW, 418 µm², 0.39 ns (45 nm)
- vs standard posit encoder: 0.26 mW, 610 µm², 0.71 ns
- Competitive with (or better than) IEEE float16 encoder/decoder while keeping
  all posit mathematical advantages + better accuracy distribution for many workloads.

## Notes for Verilog Port
1. The 5 `if size == X:` branches become a 5-to-1 MUX with one-hot select from
   the decoder + Table 3 logic.
2. All shifts are fixed small constants (2..6 bits) → no barrel shifter.
3. The only data-dependent variable is the final concatenation width, which
   is exactly what the 5 MUX inputs already prepare in parallel.
4. es=0 (recommended) removes the exponent field entirely from the datapath
   for the common regime sizes → even smaller/faster.

Primary tested configuration: `<16,6,0>` b-posit (maximum fraction bits near |x|≈1).

This Python file is the golden model for the VLSI2 posit compressor block.
