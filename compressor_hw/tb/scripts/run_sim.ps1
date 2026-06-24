# run_sim.ps1 — Run compressor testbench through Vivado (sets license + PATH like the GUI)
$ErrorActionPreference = "Stop"
$ScriptsDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$TbDir      = Split-Path -Parent $ScriptsDir

function Find-VivadoBat {
    if ($env:XILINX_VIVADO) {
        $bat = Join-Path $env:XILINX_VIVADO "bin\vivado.bat"
        if (Test-Path $bat) { return $bat }
    }

    $roots = @(
        "C:\Xilinx\Vivado\2024.1",
        "C:\Xilinx\Vivado\2023.2",
        "C:\AMD\Vivado\2024.1"
    )
    foreach ($root in $roots) {
        $bat = Join-Path $root "bin\vivado.bat"
        if (Test-Path $bat) { return $bat }
    }

    $found = Get-ChildItem "C:\Xilinx\Vivado" -Recurse -Filter "vivado.bat" -ErrorAction SilentlyContinue |
             Select-Object -First 1
    if ($found) { return $found.FullName }

    throw @"
Could not find vivado.bat.

Fix options:
  1. Open AMD/Xilinx Vivado once (GUI) so the installer environment is available.
  2. Set XILINX_VIVADO to your install, e.g. C:\Xilinx\Vivado\2024.1
  3. From Vivado Tcl Console instead:
       cd $TbDir
       source run_sim.tcl
"@
}

New-Item -ItemType Directory -Force -Path (Join-Path $TbDir "log") | Out-Null

$VivadoBat = Find-VivadoBat
$LogFile   = Join-Path $TbDir "log\vivado_batch.log"
$JouFile   = Join-Path $TbDir "log\compressor_sim.jou"
$TclScript = Join-Path $ScriptsDir "run_sim.tcl"

Write-Host "TB root:      $TbDir"
Write-Host "Using Vivado: $VivadoBat"
Write-Host "Running:      $TclScript"
Write-Host ""

& $VivadoBat -mode batch -notrace -source $TclScript -log $LogFile -journal $JouFile
$exitCode = $LASTEXITCODE

if ($exitCode -ne 0) {
    Write-Error "Vivado exited with code $exitCode. See $LogFile and log\xsim.log"
    exit $exitCode
}

$XsimLog = Join-Path $TbDir "log\xsim.log"
if (Test-Path $XsimLog) {
    $xsimLog = Get-Content $XsimLog -Raw
    if ($xsimLog -match "ALL TESTS PASSED") {
        Write-Host "SUCCESS: All tests passed."
        Write-Host "  Logs:  $TbDir\log"
        Write-Host "  Build: $TbDir\sim_out"
        Write-Host "  Waves: $TbDir\wave"
        exit 0
    }
}

Write-Warning "Simulation finished but pass/fail could not be confirmed. Check log\xsim.log"
exit 1