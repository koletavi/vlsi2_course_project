@echo off
REM Internal launcher — called by open_wave.cmd
REM Use forward-slash relative path so Tcl does not eat backslash escapes (\U \t \s ...).

call "%VIVADO_ROOT%\settings64.bat"
cd /d "%SIM_DIR%"

REM sim_out/../scripts/open_wave_view.tcl — forward slashes only for -tclbatch
"%VIVADO_ROOT%\bin\xsim.bat" compressor_sim -gui -tclbatch ../scripts/open_wave_view.tcl