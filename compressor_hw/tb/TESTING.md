# Compressor Testbench — How to Run All Tests

This directory contains four test flows, built in this order:

1. **Hardware simulation** — self-checking SystemVerilog testbench
2. **Waveform viewing** — inspect signals in Vivado xsim (optional)
3. **HW vs SW comparison** — verify hardware output matches `compressor_sw`
4. **Timing comparison** — software wall-clock time vs Vivado synth/impl timing on Pynq-Z2

All flows assume **AMD/Xilinx Vivado** is installed and **Python 3** is on your PATH.

---

## Directory layout

```
tb/
├── src/                    # compressor_tb.sv, compressor_ref_pkg.sv
├── scripts/                # Vivado Tcl/PowerShell implementation
├── log/                    # Simulation logs (generated)
├── sim_out/                # xsim build snapshot (generated)
├── wave/                   # VCD/WDB waveforms (generated)
├── hw_vs_sw/               # Functional HW vs software comparison
│   ├── hw/                 # Hardware dumps (from simulation)
│   ├── sw/                 # Software dumps (from compressor_sw)
│   └── summary/            # comparison.txt
└── timing_compare/         # Execution-time HW vs SW comparison
    ├── sw/                 # Software timing baseline
    ├── synth_vs_sw/        # Post-synthesis timing vs SW
    └── impl_vs_sw/         # Post-implementation timing vs SW
```

---

## Prerequisites

- Vivado 2023.2 or 2024.1 (or set `XILINX_VIVADO` to your install path)
- Python 3 with access to `../../compressor_sw/posit_compress.py`
- Target FPGA for timing tests: **Pynq-Z2** (`xc7z020clg400-1`) at **100 MHz**

Open a shell in this directory:

```cmd
cd compressor_hw\tb
```

---

## Test 1 — Hardware simulation

Runs the self-checking testbench (`compressor_tb.sv`) through Vivado xsim. Nine test vectors are exercised; on success the log reports `ALL TESTS PASSED`.

**Run:**

```cmd
run_sim.cmd
```

or:

```powershell
.\run_sim.ps1
```

**Pass criteria:** `log\xsim.log` contains `ALL TESTS PASSED`.

**Outputs:**

| Path | Description |
|------|-------------|
| `log/` | xvlog, xelab, xsim, vivado_batch logs |
| `sim_out/` | xsim compile snapshot |
| `wave/compressor_tb.vcd` | Waveform dump |
| `wave/compressor_sim.wdb` | Waveform database |

---

## Test 2 — View waveforms (optional)

Opens the Vivado xsim GUI with signals from the last simulation. Runs simulation first if the snapshot is missing.

**Run (after Test 1):**

```cmd
open_wave.cmd
```

or:

```powershell
.\open_wave.ps1
```

---

## Test 3 — HW vs SW functional comparison

Compares compressed output from hardware simulation against the Python reference in `compressor_sw`. Uses the same 9 test vectors.

**Run everything (simulation → SW dumps → compare):**

```cmd
cd hw_vs_sw
run_all.cmd
```

**Or step by step from `tb/`:**

```cmd
run_sim.cmd
cd hw_vs_sw
python generate_sw_results.py
python compare_results.py
```

**Pass criteria:** `hw_vs_sw\summary\comparison.txt` shows `9 passed, 0 failed`.

**Outputs:**

| Path | Description |
|------|-------------|
| `hw_vs_sw/hw/*.txt` | Per-test hardware compression dumps |
| `hw_vs_sw/sw/*.txt` | Per-test software compression dumps |
| `hw_vs_sw/summary/comparison.txt` | Pass/fail summary |

---

## Test 4 — Timing comparison (SW vs synthesis vs implementation)

Measures software compression time (wall clock) and hardware execution time derived from Vivado timing reports. Hardware time uses 3-cycle pipeline latency at the achievable clock (100 MHz when post-route timing closes).

**Run everything:**

```cmd
cd timing_compare
run_all.cmd
```

This runs, in order:

1. Ensure `hw_vs_sw/hw/*.txt` exist (runs simulation if missing)
2. Benchmark software (`benchmark_sw.py`)
3. Vivado synthesis (`scripts/run_synth.ps1`)
4. Parse synth timing and compare (`parse_vivado_timing.py`, `compare_timing.py`)
5. Vivado place-and-route (`scripts/run_impl.ps1`)
6. Parse impl timing and compare

**Individual steps:**

```cmd
cd timing_compare
python benchmark_sw.py
powershell -File scripts\run_synth.ps1
python parse_vivado_timing.py --stage synth
python compare_timing.py --stage synth
powershell -File scripts\run_impl.ps1
python parse_vivado_timing.py --stage impl
python compare_timing.py --stage impl
```

**Pass criteria:** Scripts exit with code 0; comparison files are written.

**Outputs:**

| Path | Description |
|------|-------------|
| `timing_compare/sw/sw_timing.txt` | Software timing per test vector |
| `timing_compare/synth_vs_sw/comparison.txt` | Synthesis timing vs software |
| `timing_compare/impl_vs_sw/comparison.txt` | Implementation timing vs software |
| `timing_compare/synth_vs_sw/reports/` | Vivado post-synth timing reports |
| `timing_compare/impl_vs_sw/reports/` | Vivado post-route timing reports |

**Notes:**

- Only run one Vivado flow at a time (a lock file prevents overlapping runs).
- Synthesis takes ~1–2 minutes; implementation ~2–3 minutes on a typical workstation.
- If a run is interrupted, delete `timing_compare/log/.vivado.lock` when no `vivado.exe` process is running.

---

## Recommended full test sequence

Run all four flows in the order they were created:

```cmd
cd compressor_hw\tb

REM 1. Hardware simulation
run_sim.cmd

REM 2. (Optional) View waveforms
open_wave.cmd

REM 3. HW vs SW functional comparison
cd hw_vs_sw
run_all.cmd
cd ..

REM 4. Timing comparison
cd timing_compare
run_all.cmd
```

---

## Troubleshooting

| Problem | What to do |
|---------|------------|
| `Could not find vivado.bat` | Open Vivado GUI once, or set `XILINX_VIVADO` |
| Simulation hangs at `xsim%` prompt | Use `run_sim.cmd` / `run_sim.ps1` (batch mode with auto-exit) |
| `Another timing_compare Vivado run is active` | Wait for the other run, or remove `timing_compare/log/.vivado.lock` |
| HW vs SW compare finds no HW dumps | Run `run_sim.cmd` first (Test 1) |
| Tcl path errors on Windows | Scripts use forward slashes in `-tclbatch` paths; use the provided `.cmd`/`.ps1` wrappers |