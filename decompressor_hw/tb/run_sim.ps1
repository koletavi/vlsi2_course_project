# Wrapper — delegates to scripts/run_sim.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\scripts\run_sim.ps1"
exit $LASTEXITCODE