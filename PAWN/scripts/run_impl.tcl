# Full Implementation Flow: Synthesis -> Place -> Route -> Bitstream
# Uses Zynq PS block design wrapper as top module.
# Configurable clock frequency via environment variable CLOCK_FREQ_MHZ.
# The impl top (zynq_accel_top) is clocked by PS7 FCLK_CLK0, whose period is
# set by the block design (see scripts/create_bd.tcl). If CLOCK_FREQ_MHZ
# differs from the currently-built BD, the BD is rebuilt automatically.

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
puts "Full Implementation Flow"
puts "Target: zynq_accel_top (PS7 + accel_axi)"
puts "Clock: ${clock_freq_mhz} MHz (clk_wiz_0 CLKOUT1) + 2x BRAM (CLKOUT2)"
puts "=========================================="

# Open or create project
# Close any existing open project first to avoid conflicts
catch {close_project -quiet}

if {[file exists ${proj_dir}/${proj_name}.xpr]} {
    open_project ${proj_dir}/${proj_name}.xpr
} else {
    puts "Project not found. Creating new project..."
    source -notrace [file join $root_dir scripts project_setup.tcl]
    # Project is already open after create_project in project_setup.tcl
}

# Set top-level to BD wrapper for implementation
set_property top zynq_accel_top [current_fileset]

# Always rebuild the block design so that edits to create_bd.tcl are never
# silently skipped when impl.sh is run without a preceding clean.sh.
# The BD is frequency-independent and takes ~1 min to regenerate -- negligible
# compared to the full P&R run.
puts "Rebuilding block design (picks up any create_bd.tcl changes)..."
source -notrace [file join $root_dir scripts create_bd.tcl]
set_property top zynq_accel_top [current_fileset]

# Configure clk_wiz_0: 100 MHz crystal -> CLKOUT1=core freq, CLKOUT2=2x (BRAM).
# Same configuration as run_build.tcl; both tops share the one clk_wiz_0 IP.
set bram_freq_mhz [expr {$clock_freq_mhz * 2}]
puts "Updating clk_wiz_0: 100 MHz (in) / ${clock_freq_mhz} MHz (core) / ${bram_freq_mhz} MHz (BRAM)..."
set_property -dict [list \
    CONFIG.PRIM_IN_FREQ {100.000} \
    CONFIG.CLKOUT1_REQUESTED_OUT_FREQ "$clock_freq_mhz" \
    CONFIG.CLKOUT2_USED {true} \
    CONFIG.CLKOUT2_REQUESTED_OUT_FREQ "$bram_freq_mhz" \
    CONFIG.CLKOUT2_REQUESTED_PHASE {180.000} \
] [get_ips clk_wiz_0]
generate_target all [get_ips clk_wiz_0]

update_compile_order -fileset sources_1

# Create reports directory
file mkdir [file normalize $root_dir/reports]

puts "\n=========================================="
puts "Running Synthesis..."
puts "=========================================="

set_property -name {STEPS.SYNTH_DESIGN.ARGS.GLOBAL_RETIMING} -value on -objects [get_runs synth_1]
# set_property -name {STEPS.SYNTH_DESIGN.ARGS.FLATTEN_HIERARCHY} -value full -objects [get_runs synth_1]

# Force clk_wiz_0 to re-synthesize so STA uses the updated clock periods.
# Without this Vivado reuses the stale DCP from the previous frequency.
# Guard: run name may not exist if the IP was never out-of-context synthesised yet.
if {[llength [get_runs -quiet clk_wiz_0_synth_1]] > 0} {
    reset_run clk_wiz_0_synth_1
    launch_runs clk_wiz_0_synth_1 -jobs 8
    wait_on_run clk_wiz_0_synth_1
}

# Reset synthesis run
reset_run synth_1
launch_runs synth_1 -jobs 8
wait_on_run synth_1

# Check synthesis results
set synth_status [get_property STATUS [get_runs synth_1]]
set synth_progress [get_property PROGRESS [get_runs synth_1]]

if {$synth_progress != "100%"} {
    puts "ERROR: Synthesis did not complete!"
    puts "Status: $synth_status"
    exit 1
}

puts "Synthesis complete: $synth_status"

# Open synthesized design to check initial timing
open_run synth_1
set synth_wns [get_property SLACK [get_timing_paths]]
puts "Post-Synthesis WNS: $synth_wns ns"

if {$synth_wns < 0} {
    puts "WARNING: Negative slack after synthesis. Implementation may not meet timing."
}

puts "\n=========================================="
puts "Running Implementation..."
puts "=========================================="

# Reset implementation run
reset_run impl_1
launch_runs impl_1 -jobs 8
wait_on_run impl_1

# Check implementation results
set impl_status [get_property STATUS [get_runs impl_1]]
set impl_progress [get_property PROGRESS [get_runs impl_1]]

if {$impl_progress != "100%"} {
    puts "ERROR: Implementation did not complete!"
    puts "Status: $impl_status"
    exit 1
}

puts "Implementation complete: $impl_status"

# Open implemented design and generate reports
open_run impl_1

puts "\n=========================================="
puts "Generating Reports..."
puts "=========================================="

# Timing Summary Report
report_timing_summary -file [file normalize $root_dir/reports/timing_summary.rpt]
report_timing -sort_by slack -max_paths 10 -file [file normalize $root_dir/reports/timing_detailed.rpt]

# Utilization Report
report_utilization -file [file normalize $root_dir/reports/utilization.rpt]
report_utilization -hierarchical -file [file normalize $root_dir/reports/utilization_hierarchical.rpt]

# Power Report
report_power -file [file normalize $root_dir/reports/power.rpt]

# Clock Networks
report_clock_networks -file [file normalize $root_dir/reports/clock_networks.rpt]

# Get final timing results
set final_wns [get_property SLACK [get_timing_paths]]
set final_whs [get_property SLACK [get_timing_paths -hold]]

# XSA
write_hw_platform -fixed -force -file $root_dir/zedboard.xsa

puts "\n=========================================="
puts "Final Timing Results"
puts "=========================================="
puts "WNS (Setup): $final_wns ns"
puts "WHS (Hold):  $final_whs ns"

if {$final_wns < 0} {
    puts "WARNING: Setup timing NOT MET!"
} else {
    puts "Setup timing: MET"
}

if {$final_whs < 0} {
    puts "WARNING: Hold timing NOT MET!"
} else {
    puts "Hold timing: MET"
}

puts "\n=========================================="
puts "Implementation Complete!"
puts "=========================================="
puts "Reports available in: $root_dir/reports/"
puts "To generate the bitstream run:  ./bit.sh ${clock_freq_mhz}"
puts "=========================================="
