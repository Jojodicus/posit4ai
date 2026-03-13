# Quick Build Flow: Synthesis + Verification
# Uses simpler pau_fpu_harness top (no AXI overhead) for faster iteration
# Configurable clock frequency via environment variable CLOCK_FREQ_MHZ

set proj_name "posit_research"
set proj_dir "./vivado_proj"
set root_dir [file normalize [file join [file dirname [info script]] ..]]

# Get clock frequency from environment (default: 100 MHz)
if {[info exists env(CLOCK_FREQ_MHZ)]} {
    set clock_freq_mhz $env(CLOCK_FREQ_MHZ)
} else {
    set clock_freq_mhz 100
}

set clock_period_ns [expr {1000.0 / $clock_freq_mhz}]

puts "=========================================="
puts "Quick Build Flow (Synthesis Only)"
puts "Target: pau_fpu_harness"
puts "Clock: ${clock_freq_mhz} MHz (${clock_period_ns} ns period)"
puts "=========================================="

# Open or create project
# Close any existing open project first to avoid conflicts
catch {close_project -quiet}

if {[file exists ${proj_dir}/${proj_name}.xpr]} {
    open_project ${proj_dir}/${proj_name}.xpr
} else {
    puts "Project not found. Creating new project..."
    source [file join $root_dir scripts project_setup.tcl]
    # Project is already open after create_project in project_setup.tcl
}

# Set top-level to simple harness (faster synthesis, no AXI overhead)
set_property top pau_fpu_harness [current_fileset]

# Update clocking wizard IP with requested frequency
puts "Updating clocking wizard to ${clock_freq_mhz} MHz output..."
set_property -dict [list \
    CONFIG.PRIM_IN_FREQ {100.000} \
    CONFIG.CLKOUT1_REQUESTED_OUT_FREQ "$clock_freq_mhz" \
] [get_ips clk_wiz_0]
generate_target all [get_ips clk_wiz_0]

update_compile_order -fileset sources_1

# Create reports directory
file mkdir [file normalize $root_dir/reports]

puts "\n=========================================="
puts "Running Synthesis..."
puts "=========================================="

# Reset and launch synthesis
reset_run synth_1
launch_runs synth_1 -jobs 8
wait_on_run synth_1

# Check synthesis results
set synth_status [get_property STATUS [get_runs synth_1]]
set synth_progress [get_property PROGRESS [get_runs synth_1]]

if {$synth_progress != "100%"} {
    puts "\nERROR: Synthesis did not complete!"
    puts "Status: $synth_status"
    exit 1
}

puts "\nSynthesis complete: $synth_status"

# Open synthesized design
open_run synth_1

puts "\n=========================================="
puts "Generating Reports..."
puts "=========================================="

# Quick timing report (without full implementation)
report_timing_summary -file [file normalize $root_dir/reports/build_timing.rpt]

# Utilization report
report_utilization -file [file normalize $root_dir/reports/build_utilization.rpt]

# Get timing estimates (approximate, not final)
set wns [get_property SLACK [get_timing_paths]]

puts "\n=========================================="
puts "Build Results"
puts "=========================================="
puts "Estimated WNS: $wns ns"

if {$wns < 0} {
    puts "Status: TIMING LIKELY WILL NOT MEET (run impl.sh for accurate results)"
} else {
    puts "Status: TIMING LOOKS GOOD (run impl.sh to verify)"
}

# Get utilization summary
set lut_cells [get_cells -quiet -hierarchical -filter {REF_NAME =~ "LUT*"}]
set luts [llength $lut_cells]
set ff_cells [get_cells -quiet -hierarchical -filter {IS_SEQUENTIAL}]
set ffs [llength $ff_cells]

puts "\nResource Usage:"
puts "  LUTs: $luts"
puts "  FFs:  $ffs"

puts "\nReports available in: $root_dir/reports/"
puts "=========================================="
