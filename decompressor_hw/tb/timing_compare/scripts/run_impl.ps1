# run_impl.ps1 — Run Vivado implementation for timing benchmark
$ErrorActionPreference = "Stop"
$ScriptsDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RootDir    = Split-Path -Parent $ScriptsDir

. (Join-Path $ScriptsDir "vivado_common.ps1")

$XprFile   = Join-Path $RootDir "build\synth\decompressor_timing_synth.xpr"
$TimingRpt = Join-Path $RootDir "impl_vs_sw\reports\timing_summary.rpt"

if (-not (Test-Path $XprFile)) {
    Write-Error "Synthesis project not found. Run run_synth.ps1 first."
    exit 1
}

Write-Host "Timing compare root: $RootDir"
$TclScript = Join-Path $ScriptsDir "run_impl.tcl"

$exitCode = Invoke-VivadoTcl -RootDir $RootDir -TclScript $TclScript -LogName "vivado_impl.log" -TimeoutMinutes 45
if ($exitCode -ne 0) {
    Write-Error "Implementation failed (exit $exitCode). See timing_compare\log\vivado_impl.log"
    exit $exitCode
}

if (-not (Test-Path $TimingRpt)) {
    Write-Error "Implementation reported success but missing $TimingRpt"
    exit 1
}

Write-Host "Implementation reports: $RootDir\impl_vs_sw\reports"
exit 0