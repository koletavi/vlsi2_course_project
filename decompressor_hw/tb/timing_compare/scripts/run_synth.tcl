# run_synth.tcl — Synthesize decompressor for Pynq-Z2 timing benchmark

set scripts_dir [file normalize [file dirname [info script]]]
set root_dir    [file normalize [file join $scripts_dir ..]]
set tb_dir      [file normalize [file join $root_dir ..]]
set rtl_dir     [file normalize [file join $tb_dir ../rtl]]
set src_dir     [file join $root_dir src]

set part        xc7z020clg400-1
set build_dir   [file join $root_dir build synth]
set reports_dir [file join $root_dir synth_vs_sw reports]
set log_dir     [file join $root_dir log]
set xpr_file    [file join $build_dir decompressor_timing_synth.xpr]

set RUN_TIMEOUT_SEC 1800

proc wait_for_run {run_name {timeout_sec 1800}} {
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

foreach d [list $build_dir $reports_dir $log_dir] {
    file mkdir $d
}

set top_file [file join $src_dir decompressor_timing_top.sv]
set rtl_files [list \
    [file join $rtl_dir unpack_group.sv] \
    [file join $rtl_dir urze.sv] \
    [file join $rtl_dir bit_transpose.sv] \
    [file join $rtl_dir undiffnb.sv] \
    [file join $rtl_dir decompressor.sv] \
]

set xdc_file [file join $root_dir constraints decompressor.xdc]

puts "=== Synthesis timing benchmark ==="
puts "Part:    $part"
puts "Top:     decompressor_timing_top"
puts "RTL:     $rtl_dir"
puts "Build:   $build_dir"
puts "Reports: $reports_dir"
puts ""

if {[file exists $xpr_file]} {
    puts "Reopening existing project: $xpr_file"
    open_project $xpr_file
    if {[llength [get_files -quiet [file tail $top_file]]] == 0} {
        add_files -norecurse $top_file
    }
    set_property top decompressor_timing_top [current_fileset]
    set_property top_file $top_file [current_fileset]
    update_compile_order -fileset sources_1
    reset_run synth_1
} else {
    create_project decompressor_timing_synth $build_dir -part $part
    add_files -norecurse [concat [list $top_file] $rtl_files]
    add_files -fileset constrs_1 -norecurse $xdc_file
    set_property top decompressor_timing_top [current_fileset]
    set_property top_file $top_file [current_fileset]
    update_compile_order -fileset sources_1
}

launch_runs synth_1 -jobs 2
if {[wait_for_run synth_1 $RUN_TIMEOUT_SEC]} {
    catch {close_project}
    exit 1
}

set status [get_property STATUS [get_runs synth_1]]
if {![string match *Complete* $status]} {
    puts "ERROR: Synthesis status: $status"
    close_project
    exit 1
}

open_run synth_1

report_timing_summary -file [file join $reports_dir timing_summary.rpt]
report_utilization     -file [file join $reports_dir utilization.rpt]
report_clocks          -file [file join $reports_dir clocks.rpt]

close_project

puts ""
puts "SUCCESS: Synthesis complete."
puts "  Reports: $reports_dir"
exit 0