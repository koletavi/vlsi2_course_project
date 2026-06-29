# sim_with_waves.tcl — Run simulation, record key signals, then exit (batch mode)
# NOTE: must end with "quit" or xsim stays at the interactive "xsim%" prompt.

log_wave /decompressor_tb/clk
log_wave /decompressor_tb/nrst
log_wave /decompressor_tb/start
log_wave /decompressor_tb/valid
log_wave /decompressor_tb/in_count
log_wave /decompressor_tb/key_in
log_wave /decompressor_tb/dut/urze_valid
log_wave /decompressor_tb/dut/bit_valid

run all
quit