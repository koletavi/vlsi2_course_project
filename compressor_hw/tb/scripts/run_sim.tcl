# run_sim.tcl — Run compressor testbench (use from Vivado Tcl console or batch mode)
#
# From Vivado GUI Tcl Console:
#   cd C:/Users/kolet/projects/vlsi2/compressor_hw/tb
#   source run_sim.tcl
#
# From command line:
#   run_sim.cmd   or   powershell -File run_sim.ps1

set scripts_dir [file normalize [file dirname [info script]]]
set tb_dir      [file normalize [file join $scripts_dir ..]]
set src_dir     [file join $tb_dir src]
set sim_dir     [file join $tb_dir sim_out]
set log_dir     [file join $tb_dir log]
set wave_dir    [file join $tb_dir wave]
set rtl_dir     [file normalize [file join $tb_dir ../rtl]]

foreach d [list $log_dir $sim_dir $wave_dir] {
    file mkdir $d
}

if {![info exists ::env(XILINX_VIVADO)]} {
    puts "ERROR: XILINX_VIVADO is not set."
    puts "Run via run_sim.cmd / run_sim.ps1, or launch Vivado GUI first."
    exit 1
}

set vivado_bin [file normalize [file join $::env(XILINX_VIVADO) bin]]
set xvlog  [file join $vivado_bin xvlog]
set xelab  [file join $vivado_bin xelab]
set xsim   [file join $vivado_bin xsim]

proc run_cmd {name argv} {
    puts ""
    puts "=== $name ==="
    puts [join $argv " "]
    if {[catch {eval exec $argv} msg]} {
        puts stderr $msg
        exit 1
    }
    if {$msg ne ""} {
        puts $msg
    }
}

foreach item {xsim.dir xelab.pb xvlog.pb} {
    catch {file delete -force [file join $sim_dir $item]}
}
foreach logname {xvlog.log xelab.log xsim.log} {
    catch {file delete -force [file join $log_dir $logname]}
}

cd $sim_dir

set sv_files [list \
    [file join $rtl_dir pack_group.sv] \
    [file join $rtl_dir diffnb.sv] \
    [file join $rtl_dir bit_transpose.sv] \
    [file join $rtl_dir rze.sv] \
    [file join $rtl_dir compressor.sv] \
    [file join $src_dir compressor_ref_pkg.sv] \
    [file join $src_dir compressor_tb.sv] \
]

set xvlog_log [file join $log_dir xvlog.log]
set xelab_log [file join $log_dir xelab.log]
set xsim_log  [file join $log_dir xsim.log]

run_cmd "Compiling (xvlog)" [list $xvlog -sv {*}$sv_files -log $xvlog_log]
run_cmd "Elaborating (xelab)" [list $xelab -debug typical compressor_tb -s compressor_sim -log $xelab_log]
# Forward slashes in -tclbatch path — backslashes break Tcl (\U \t \s ...).
set sim_tcl [file normalize [file join $scripts_dir sim_with_waves.tcl]]
regsub -all {\\} $sim_tcl {/} sim_tcl
run_cmd "Simulating (xsim)" [list $xsim compressor_sim -tclbatch $sim_tcl -log $xsim_log]

# Copy WDB snapshot(s) from sim_out into wave/ for offline viewing
foreach wdb [glob -nocomplain -directory $sim_dir *.wdb] {
    set dest [file join $wave_dir compressor_sim.wdb]
    catch {file copy -force $wdb $dest}
}

if {[file exists $xsim_log]} {
    set fh [open $xsim_log r]
    set log_data [read $fh]
    close $fh
    if {[string match *ALL\ TESTS\ PASSED* $log_data]} {
        puts ""
        puts "SUCCESS: All tests passed."
        puts "  Logs:  $log_dir"
        puts "  Build: $sim_dir"
        puts "  Waves: $wave_dir"
        puts "  View:  run open_wave.cmd (or open_wave.ps1)"
        exit 0
    }
    if {[string match *SOME\ TESTS\ FAILED* $log_data] || [string match *\$fatal* $log_data]} {
        puts ""
        puts "FAILURE: Simulation reported test failures. See $xsim_log"
        exit 1
    }
}

puts ""
puts "WARNING: Could not confirm pass/fail from $xsim_log"
exit 1