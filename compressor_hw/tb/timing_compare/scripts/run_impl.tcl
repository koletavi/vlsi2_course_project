# run_impl.tcl — Place-and-route compressor for Pynq-Z2 timing benchmark

set scripts_dir [file normalize [file dirname [info script]]]
set root_dir    [file normalize [file join $scripts_dir ..]]

set build_dir   [file join $root_dir build synth]
set reports_dir [file join $root_dir impl_vs_sw reports]
set log_dir     [file join $root_dir log]
set xpr_file    [file join $build_dir compressor_timing_synth.xpr]

set RUN_TIMEOUT_SEC 2700

proc wait_for_run {run_name {timeout_sec 2700}} {
    set start [clock seconds]
    while {1} {
        set elapsed [expr {[clock seconds] - $start}]
        set remaining [expr {$timeout_sec - $elapsed}]
        if {$remaining <= 0} {
            puts "ERROR: Timeout after ${timeout_sec}s waiting for $run_name"
            return 1
        }
        set slice [expr {$remaining > 60 ? 60 : $remaining}]
        wait_on_run $run_name -timeout $slice
        set prog [get_property PROGRESS [get_runs $run_name]]
        set status [get_property STATUS [get_runs $run_name]]
        if {$prog eq "100%"} {
            return 0
        }
        if {[string match *ERROR* $status] || [string match *Failed* $status]} {
            puts "ERROR: Run $run_name failed with status: $status"
            return 1
        }
    }
}

foreach d [list $reports_dir $log_dir] {
    file mkdir $d
}

if {![file exists $xpr_file]} {
    puts "ERROR: Project not found: $xpr_file"
    puts "Run run_synth.tcl first."
    exit 1
}

puts "=== Implementation timing benchmark ==="
puts "Project: $xpr_file"
puts "Reports: $reports_dir"
puts ""

open_project $xpr_file

set_property SEVERITY {Warning} [get_drc_checks NSTD-1]
set_property SEVERITY {Warning} [get_drc_checks UCIO-1]

if {[llength [get_runs impl_1]] > 0} {
    set impl_status [get_property STATUS [get_runs impl_1]]
    if {$impl_status ne "not started"} {
        reset_run impl_1
    }
}

launch_runs impl_1 -to_step route_design -jobs 2
if {[wait_for_run impl_1 $RUN_TIMEOUT_SEC]} {
    catch {close_project}
    exit 1
}

set status [get_property STATUS [get_runs impl_1]]
if {![string match *Complete* $status]} {
    puts "ERROR: Implementation status: $status"
    close_project
    exit 1
}

open_run impl_1

report_timing_summary -file [file join $reports_dir timing_summary.rpt]
report_utilization     -file [file join $reports_dir utilization.rpt]
report_clocks          -file [file join $reports_dir clocks.rpt]

close_project

puts ""
puts "SUCCESS: Implementation complete."
puts "  Reports: $reports_dir"
exit 0