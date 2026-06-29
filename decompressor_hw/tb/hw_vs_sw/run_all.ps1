# run_all.ps1 — Run HW sim, generate SW dumps, compare results
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$TbDir = Split-Path -Parent $Root

Write-Host "Step 1/3: Run hardware simulation..."
& (Join-Path $TbDir "scripts\run_sim.cmd")
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host ""
Write-Host "Step 2/3: Generate software dumps (decompressor reference)..."
python (Join-Path $Root "generate_sw_results.py")
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host ""
Write-Host "Step 3/3: Compare HW vs SW..."
python (Join-Path $Root "compare_results.py")
exit $LASTEXITCODE