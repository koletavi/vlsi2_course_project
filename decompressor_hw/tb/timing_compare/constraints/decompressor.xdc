# Timing constraints for decompressor_timing_top on Pynq-Z2 (xc7z020clg400-1)
# Target: 100 MHz (matches decompressor_tb CLK_PERIOD = 10 ns)

create_clock -period 10.000 -name clk [get_ports clk]

set_false_path -from [get_ports nrst]

# Preserve decompressor hierarchy for accurate stage-level timing
set_property KEEP_HIERARCHY TRUE [get_cells u_decompressor]