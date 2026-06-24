# run_synth.ps1 — Run Vivado synthesis for timing benchmark
$ErrorActionPreference = "Stop"
$ScriptsDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RootDir    = Split-Path -Parent $ScriptsDir

. (Join-Path $ScriptsDir "vivado_common.ps1")

$BuildDir  = Join-Path $RootDir "build\synth"
$XprFile   = Join-Path $BuildDir "compressor_timing_synth.xpr"
$TimingRpt = Join-Path $RootDir "synth_vs_sw\reports\timing_summary.rpt"

if (-not (Test-Path $XprFile) -and (Test-Path $BuildDir)) {
    Write-Host "Cleaning stale build directory (no .xpr): $BuildDir"
    try {
        Remove-Item -Recurse -Force $BuildDir -ErrorAction Stop
    }
    catch {
        Write-Error "Cannot clean $BuildDir (files locked?). Close other Vivado sessions and retry."
        exit 1
    }
}

Write-Host "Timing compare root: $RootDir"
$TclScript = Join-Path $ScriptsDir "run_synth.tcl"

$exitCode = Invoke-VivadoTcl -RootDir $RootDir -TclScript $TclScript -LogName "vivado_synth.log" -TimeoutMinutes 30
if ($exitCode -ne 0) {
    Write-Error "Synthesis failed (exit $exitCode). See timing_compare\log\vivado_synth.log"
    exit $exitCode
}

if (-not (Test-Path $TimingRpt)) {
    Write-Error "Synthesis reported success but missing $TimingRpt"
    exit 1
}

Write-Host "Synthesis reports: $RootDir\synth_vs_sw\reports"
exit 0