# open_wave_gui.tcl — Launch xsim GUI with waves (called via vivado.bat)
set scripts_dir [file normalize [file dirname [info script]]]
set tb_dir      [file normalize [file join $scripts_dir ..]]
set sim_dir     [file join $tb_dir sim_out]

if {![file exists [file join $sim_dir xsim.dir compressor_sim]]} {
    puts "Snapshot missing. Run: source run_sim.tcl"
    exit 1
}

cd $sim_dir
set xsim [file join $::env(XILINX_VIVADO) bin xsim]
exec $xsim compressor_sim -gui -tclbatch [file join $scripts_dir open_wave.tcl] &