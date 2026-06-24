# run_all.ps1 — SW benchmark + Vivado synth/impl timing comparison
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$TbDir = Split-Path -Parent $Root
$HwDir = Join-Path $TbDir "hw_vs_sw\hw"

function Step([string]$Title) {
    Write-Host ""
    Write-Host "=== $Title ==="
}

function Invoke-Step {
    param(
        [string]$Name,
        [scriptblock]$Action
    )
    Step $Name
    try {
        & $Action
        if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) {
            Write-Error "$Name failed (exit $LASTEXITCODE)"
            exit $LASTEXITCODE
        }
    }
    catch {
        Write-Error "$Name failed: $($_.Exception.Message)"
        exit 1
    }
}

Invoke-Step "Step 1/6: Ensure HW test vectors exist" {
    $hwFiles = @(Get-ChildItem -Path $HwDir -Filter "*.txt" -ErrorAction SilentlyContinue)
    if ($hwFiles.Count -eq 0) {
        Write-Host "No hw_vs_sw/hw/*.txt found - running simulation..."
        & (Join-Path $TbDir "run_sim.ps1")
    } else {
        Write-Host "Found $($hwFiles.Count) HW dump(s) in hw_vs_sw/hw/"
    }
}

Invoke-Step "Step 2/6: Benchmark software compression" {
    python (Join-Path $Root "benchmark_sw.py")
}

Invoke-Step "Step 3/6: Vivado synthesis (Pynq-Z2)" {
    & (Join-Path $Root "scripts\run_synth.ps1")
}

Invoke-Step "Step 4/6: Parse synthesis timing and compare vs SW" {
    python (Join-Path $Root "parse_vivado_timing.py") --stage synth
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    python (Join-Path $Root "compare_timing.py") --stage synth
}

Invoke-Step "Step 5/6: Vivado implementation (place and route)" {
    & (Join-Path $Root "scripts\run_impl.ps1")
}

Invoke-Step "Step 6/6: Parse implementation timing and compare vs SW" {
    python (Join-Path $Root "parse_vivado_timing.py") --stage impl
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    python (Join-Path $Root "compare_timing.py") --stage impl
}

Write-Host ""
Write-Host "DONE. Results:"
Write-Host ("  SW baseline:  " + (Join-Path $Root "sw\sw_timing.txt"))
Write-Host ("  Synth vs SW:  " + (Join-Path $Root "synth_vs_sw\comparison.txt"))
Write-Host ("  Impl vs SW:   " + (Join-Path $Root "impl_vs_sw\comparison.txt"))
exit 0