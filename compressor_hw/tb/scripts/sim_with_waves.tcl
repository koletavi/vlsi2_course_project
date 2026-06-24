# sim_with_waves.tcl — Run simulation, record key signals, then exit (batch mode)
# NOTE: must end with "quit" or xsim stays at the interactive "xsim%" prompt.

log_wave /compressor_tb/clk
log_wave /compressor_tb/nrst
log_wave /compressor_tb/start
log_wave /compressor_tb/valid
log_wave /compressor_tb/out_count
log_wave /compressor_tb/key_out
log_wave /compressor_tb/dut/dn_valid
log_wave /compressor_tb/dut/bit_valid

run all
quit