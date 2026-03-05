
source ./scripts/project_setup.tcl

proc run_synth {freq} {
    puts "========================================"
    puts "TESTING FREQUENCY: $freq MHz"
    puts "========================================"
    
    # Update Clocking Wizard Frequency
    set_property -dict [list CONFIG.CLKOUT1_REQUESTED_OUT_FREQ $freq] [get_ips clk_wiz_0]
    generate_target all [get_ips clk_wiz_0]
    
    # Run Synthesis
    reset_run synth_1
    launch_runs synth_1 -jobs 4
    wait_on_run synth_1
    
    if {[get_property PROGRESS [get_runs synth_1]] != "100%"} {
        return -1
    }
    
    open_run synth_1
    set wns [get_property SLACK [get_timing_paths -max_paths 1 -setup]]
    close_design
    
    return $wns
}

# Binary Search for Fmax
set low 10
set high 200
set best_f 10

for {set i 0} {$i < 4} {incr i} {
    set mid [expr ($low + $high) / 2.0]
    set wns [run_synth $mid]
    
    if {$wns >= 0} {
        puts "SUCCESS at $mid MHz (WNS: $wns)"
        set best_f $mid
        set low $mid
    } else {
        puts "FAILURE at $mid MHz"
        set high $mid
    }
}

puts "========================================"
puts "FINAL ESTIMATED FMAX: $best_f MHz"
puts "========================================"
