# open_wave.tcl — Add key signals and open waveform viewer (run inside xsim GUI)

# Re-run simulation so waves are populated (snapshot is already elaborated)
run all

# Top-level control signals
add_wave -divider "Control"
add_wave {{/compressor_tb/clk}}
add_wave {{/compressor_tb/nrst}}
add_wave {{/compressor_tb/start}}
add_wave {{/compressor_tb/valid}}

# Compressor outputs
add_wave -divider "Outputs"
add_wave -radix unsigned {{/compressor_tb/out_count}}
add_wave -radix hex {{/compressor_tb/key_out}}
add_wave -radix hex {{/compressor_tb/packed_planes[0]}}
add_wave -radix hex {{/compressor_tb/packed_planes[1]}}

# Sample input words
add_wave -divider "Input packet (sample)"
add_wave -radix hex {{/compressor_tb/data_packet[0]}}
add_wave -radix hex {{/compressor_tb/data_packet[1]}}
add_wave -radix hex {{/compressor_tb/data_packet[63]}}

# Internal pipeline handshakes
add_wave -divider "Pipeline"
add_wave {{/compressor_tb/dut/dn_valid}}
add_wave {{/compressor_tb/dut/bit_valid}}

# Zoom to full run
wave zoom full