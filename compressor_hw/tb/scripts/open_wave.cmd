@echo off
REM open_wave.cmd — Open saved waveforms in Vivado xsim GUI
setlocal EnableExtensions

set "SCRIPTS_DIR=%~dp0"
for %%I in ("%SCRIPTS_DIR%..") do set "TB_DIR=%%~fI"
set "SIM_DIR=%TB_DIR%\sim_out"

if not exist "%SIM_DIR%\xsim.dir\compressor_sim" (
    echo Simulation snapshot missing. Running simulation first...
    call "%SCRIPTS_DIR%run_sim.cmd"
    if errorlevel 1 exit /b 1
)

if not exist "%TB_DIR%\wave\compressor_tb.vcd" if not exist "%TB_DIR%\wave\compressor_sim.wdb" (
    echo ERROR: No waveform files in wave\
    echo Run run_sim.cmd first.
    pause
    exit /b 1
)

if defined XILINX_VIVADO (
    set "VIVADO_ROOT=%XILINX_VIVADO%"
    goto :launch
)
set "VIVADO_ROOT=C:\Xilinx\Vivado\2024.1"
if exist "%VIVADO_ROOT%\settings64.bat" goto :launch
set "VIVADO_ROOT=C:\Xilinx\Vivado\2023.2"
if exist "%VIVADO_ROOT%\settings64.bat" goto :launch

echo ERROR: Could not find Vivado settings64.bat
pause
exit /b 1

:launch
echo Opening Vivado xsim GUI...
echo   VCD: %TB_DIR%\wave\compressor_tb.vcd
echo   WDB: %TB_DIR%\wave\compressor_sim.wdb
echo.

set "SIM_DIR=%SIM_DIR%"
set "VIVADO_ROOT=%VIVADO_ROOT%"
start "compressor waves" "%SCRIPTS_DIR%launch_wave_gui.cmd"

exit /b 0