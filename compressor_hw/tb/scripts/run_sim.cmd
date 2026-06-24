@echo off
REM run_sim.cmd — Double-clickable simulation launcher (no PowerShell policy issues)
setlocal EnableExtensions

set "SCRIPTS_DIR=%~dp0"
set "TB_DIR=%SCRIPTS_DIR%.."
cd /d "%TB_DIR%"

if not exist "%TB_DIR%\log" mkdir "%TB_DIR%\log"

if defined XILINX_VIVADO (
    set "VIVADO_BAT=%XILINX_VIVADO%\bin\vivado.bat"
    if exist "%VIVADO_BAT%" goto :run
)

set "VIVADO_BAT=C:\Xilinx\Vivado\2024.1\bin\vivado.bat"
if exist "%VIVADO_BAT%" goto :run

set "VIVADO_BAT=C:\Xilinx\Vivado\2023.2\bin\vivado.bat"
if exist "%VIVADO_BAT%" goto :run

echo ERROR: Could not find vivado.bat
echo.
echo Try: cd %TB_DIR% ^&^& source scripts/run_sim.tcl  (from Vivado Tcl Console)
pause
exit /b 1

:run
echo TB root: %TB_DIR%
echo Using Vivado: %VIVADO_BAT%
echo.

call "%VIVADO_BAT%" -mode batch -notrace -source "%SCRIPTS_DIR%run_sim.tcl" -log "%TB_DIR%\log\vivado_batch.log" -journal "%TB_DIR%\log\compressor_sim.jou"
set "RC=%ERRORLEVEL%"

if %RC% neq 0 (
    echo FAILED: Vivado exited with code %RC%
    echo Check log\vivado_batch.log and log\xsim.log
    pause
    exit /b %RC%
)

findstr /C:"ALL TESTS PASSED" "%TB_DIR%\log\xsim.log" >nul 2>&1
if %ERRORLEVEL% equ 0 (
    echo SUCCESS: All tests passed.
    echo   Logs:  %TB_DIR%\log
    echo   Build: %TB_DIR%\sim_out
    echo   Waves: %TB_DIR%\wave
    echo.
    echo To view waveforms, run: open_wave.cmd
    pause
    exit /b 0
)

echo WARNING: Check log\xsim.log for results.
pause
exit /b 1