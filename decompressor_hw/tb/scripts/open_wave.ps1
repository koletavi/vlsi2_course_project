# open_wave.ps1 — Launch Vivado xsim GUI and load saved waveforms
$ErrorActionPreference = "Stop"
$ScriptsDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$TbDir      = (Resolve-Path (Join-Path $ScriptsDir "..")).Path
$SimDir     = Join-Path $TbDir "sim_out"

function Find-VivadoRoot {
    if ($env:XILINX_VIVADO -and (Test-Path $env:XILINX_VIVADO)) {
        return $env:XILINX_VIVADO
    }
    foreach ($root in @("C:\Xilinx\Vivado\2024.1", "C:\Xilinx\Vivado\2023.2")) {
        if (Test-Path (Join-Path $root "bin\xsim.bat")) { return $root }
    }
    throw "Could not find Vivado install. Set XILINX_VIVADO."
}

if (-not (Test-Path (Join-Path $SimDir "xsim.dir\decompressor_sim"))) {
    Write-Host "Simulation snapshot not found. Running simulation first..."
    & (Join-Path $ScriptsDir "run_sim.cmd")
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

$WaveDb  = Join-Path $TbDir "wave\decompressor_sim.wdb"
$VcdFile = Join-Path $TbDir "wave\decompressor_tb.vcd"
if (-not (Test-Path $WaveDb) -and -not (Test-Path $VcdFile)) {
    Write-Error "No waveform files in wave\. Run run_sim.cmd first."
    exit 1
}

$VivadoRoot = Find-VivadoRoot
$env:VIVADO_ROOT = $VivadoRoot
$env:SIM_DIR     = $SimDir

Write-Host "Opening Vivado xsim GUI..."
Write-Host "  VCD: $VcdFile"
Write-Host "  WDB: $WaveDb"

Start-Process -FilePath (Join-Path $ScriptsDir "launch_wave_gui.cmd") -WorkingDirectory $ScriptsDir