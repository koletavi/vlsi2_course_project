# Shared Vivado launcher helpers for timing_compare scripts

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

    throw "Could not find vivado.bat. Set XILINX_VIVADO or open Vivado GUI once."
}

function Test-VivadoLock {
    param([string]$LockFile)

    if (-not (Test-Path $LockFile)) { return }

    $lockPid = Get-Content $LockFile -ErrorAction SilentlyContinue
    if ($lockPid -and (Get-Process -Id $lockPid -ErrorAction SilentlyContinue)) {
        throw "Another timing_compare Vivado run is active (pid=$lockPid). Wait for it to finish."
    }
    Remove-Item $LockFile -Force -ErrorAction SilentlyContinue
}

function Test-VivadoRunSuccess {
    param(
        [string]$LogFile,
        [datetime]$StartedAt
    )

    if (-not (Test-Path $LogFile)) { return $false }

    $info = Get-Item $LogFile
    if ($info.LastWriteTime -lt $StartedAt.AddSeconds(-5)) { return $false }

    $text = Get-Content $LogFile -Raw -ErrorAction SilentlyContinue
    if (-not $text) { return $false }

    return ($text -match "SUCCESS: (Synthesis|Implementation) complete\.")
}

function Invoke-VivadoTcl {
    param(
        [string]$RootDir,
        [string]$TclScript,
        [string]$LogName,
        [int]$TimeoutMinutes = 45
    )

    $LogDir = Join-Path $RootDir "log"
    New-Item -ItemType Directory -Force -Path $LogDir | Out-Null

    $LockFile   = Join-Path $LogDir ".vivado.lock"
    $LogFile    = Join-Path $LogDir $LogName
    $JouFile    = Join-Path $LogDir ($LogName -replace '\.log$', '.jou')
    $WrapperCmd = Join-Path $LogDir "_vivado_invoke.cmd"
    Test-VivadoLock -LockFile $LockFile
    Set-Content -Path $LockFile -Value $PID

    $VivadoBat = Find-VivadoBat
    $TclForVivado = ($TclScript -replace '\\', '/')
    $LogForVivado = ($LogFile -replace '\\', '/')
    $JouForVivado = ($JouFile -replace '\\', '/')

    Write-Host "Using Vivado: $VivadoBat"
    Write-Host "Running:      $TclScript"
    Write-Host "Timeout:      $TimeoutMinutes min"
    Write-Host ""

    @"
@echo off
call "$VivadoBat" -mode batch -notrace -source "$TclForVivado" -log "$LogForVivado" -journal "$JouForVivado"
exit /b %ERRORLEVEL%
"@ | Set-Content -Path $WrapperCmd -Encoding ASCII

    $startedAt = Get-Date

    $proc = $null
    Push-Location $RootDir
    try {
        $proc = Start-Process -FilePath $WrapperCmd `
            -WorkingDirectory $RootDir `
            -PassThru -NoNewWindow -Wait:$false

        Set-Content -Path $LockFile -Value $proc.Id

        $timeoutMs = $TimeoutMinutes * 60 * 1000
        if (-not $proc.WaitForExit($timeoutMs)) {
            Write-Host "ERROR: Vivado timed out after $TimeoutMinutes minutes (pid=$($proc.Id))"
            Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
            Get-Process vivado -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
            return 124
        }

        if (Test-VivadoRunSuccess -LogFile $LogFile -StartedAt $startedAt) {
            return 0
        }

        Write-Host "ERROR: Vivado exited $($proc.ExitCode) without SUCCESS in log. See $LogFile"
        return [Math]::Max($proc.ExitCode, 1)
    }
    catch {
        Write-Host "ERROR: $($_.Exception.Message)"
        if ($proc -and -not $proc.HasExited) {
            Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
        }
        return 1
    }
    finally {
        Remove-Item $LockFile -Force -ErrorAction SilentlyContinue
        Remove-Item $WrapperCmd -Force -ErrorAction SilentlyContinue
        Pop-Location
    }
}