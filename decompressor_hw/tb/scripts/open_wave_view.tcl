# open_wave_view.tcl — Load waveforms in xsim GUI (-gui -tclbatch)
# Uses [info script] for paths (always forward slashes when sourced via ../scripts/...).

set scripts_dir [file normalize [file dirname [info script]]]
set tb_dir      [file normalize [file join $scripts_dir ..]]
set vcd_file    [file normalize [file join $tb_dir wave decompressor_tb.vcd]]
set wave_db     [file normalize [file join $tb_dir wave decompressor_sim.wdb]]

proc load_waves_from_snapshot {} {
    add_wave {{/decompressor_tb/clk}}
    add_wave {{/decompressor_tb/nrst}}
    add_wave {{/decompressor_tb/start}}
    add_wave {{/decompressor_tb/valid}}
    add_wave -radix unsigned {{/decompressor_tb/in_count}}
    add_wave -radix hex {{/decompressor_tb/key_in}}
    add_wave {{/decompressor_tb/dut/urze_valid}}
    add_wave {{/decompressor_tb/dut/bit_valid}}
    run all
}

set opened 0

if {[file exists $vcd_file]} {
    if {![catch {open_vcd $vcd_file} err]} {
        puts "Opened VCD: $vcd_file"
        set opened 1
    } else {
        puts "VCD open failed: $err"
    }
}

if {!$opened && [file exists $wave_db]} {
    if {![catch {open_wave_database $wave_db} err]} {
        puts "Opened WDB: $wave_db"
        set opened 1
    } else {
        puts "WDB open failed: $err"
    }
}

if {!$opened} {
    puts "Loading waves from snapshot (re-running simulation)..."
    load_waves_from_snapshot
    set opened 1
}

catch {wave zoom full}
puts "Waveform viewer ready."