# Bitstream Generation
# Checks whether the implementation is current before generating the bitstream.
# Re-runs synthesis and implementation automatically when any of the following
# is true:
#   - source files have changed since the last synthesis run (NEEDS_REFRESH)
#   - no completed implementation run exists
#   - the configured clock frequency differs from what was last synthesised
#
# CLOCK_FREQ_MHZ is read from the environment (default: 100).
# Called by bit.sh; do not invoke directly.

set proj_name "posit_research"
set proj_dir  "./vivado_proj"
set root_dir  [file normalize [file join [file dirname [info script]] ..]]

if {[info exists env(CLOCK_FREQ_MHZ)]} {
    set clock_freq_mhz $env(CLOCK_FREQ_MHZ)
} else {
    set clock_freq_mhz 100
}
set bram_freq_mhz [expr {$clock_freq_mhz * 2}]

puts "=========================================="
puts "Bitstream Generation"
puts "Target: zynq_accel_top"
puts "Clock: ${clock_freq_mhz} MHz"
puts "=========================================="

catch {close_project -quiet}

if {[file exists ${proj_dir}/${proj_name}.xpr]} {
    open_project ${proj_dir}/${proj_name}.xpr
} else {
    puts "Project not found -- creating..."
    source -notrace [file join $root_dir scripts project_setup.tcl]
}

set_property top zynq_accel_top [current_fileset]

# BD is frequency-independent; rebuild only if missing.
if {[get_files -quiet "zynq_ps.bd"] eq ""} {
    source -notrace [file join $root_dir scripts create_bd.tcl]
    set_property top zynq_accel_top [current_fileset]
}

# --------------------------------------------------------------------------
# Decide whether implementation needs to be (re-)run.
# --------------------------------------------------------------------------
set need_impl 0
set impl_reason ""

# 1. Source files changed since the last synthesis?
if {[get_property NEEDS_REFRESH [get_runs synth_1]]} {
    set need_impl 1
    set impl_reason "sources changed since last synthesis"
}

# 2. No completed implementation run?
set impl_progress [get_property PROGRESS [get_runs impl_1]]
if {$impl_progress ne "100%"} {
    set need_impl 1
    set impl_reason "implementation not complete (progress: $impl_progress)"
}

# 3. Clock frequency changed?  Only worth checking when impl otherwise looks
#    current -- changing the IP config itself would set NEEDS_REFRESH, but we
#    read the IP property before touching anything to keep the check clean.
if {!$need_impl} {
    set cur_freq_str \
        [get_property CONFIG.CLKOUT1_REQUESTED_OUT_FREQ [get_ips clk_wiz_0]]
    # Vivado stores the value as a float string, e.g. "100.000".
    set cur_freq_int [expr {int(double($cur_freq_str))}]
    if {$cur_freq_int != $clock_freq_mhz} {
        set need_impl 1
        set impl_reason \
            "frequency changed (was ${cur_freq_int} MHz, now ${clock_freq_mhz} MHz)"
    }
}

# --------------------------------------------------------------------------
# Run implementation if required.
# --------------------------------------------------------------------------
if {$need_impl} {
    puts "\nRe-running implementation: $impl_reason"

    puts "\n=========================================="
    puts "Running Implementation..."
    puts "=========================================="

    puts "Updating clk_wiz_0: ${clock_freq_mhz} MHz (core) / ${bram_freq_mhz} MHz (BRAM)..."
    set_property -dict [list \
        CONFIG.PRIM_IN_FREQ              {100.000} \
        CONFIG.CLKOUT1_REQUESTED_OUT_FREQ "$clock_freq_mhz" \
        CONFIG.CLKOUT2_USED              {true} \
        CONFIG.CLKOUT2_REQUESTED_OUT_FREQ "$bram_freq_mhz" \
    ] [get_ips clk_wiz_0]
    generate_target all [get_ips clk_wiz_0]
    update_compile_order -fileset sources_1

    file mkdir [file normalize $root_dir/reports]

    set_property -name {STEPS.SYNTH_DESIGN.ARGS.RETIMING}          \
                 -value true  -objects [get_runs synth_1]
    set_property -name {STEPS.SYNTH_DESIGN.ARGS.FLATTEN_HIERARCHY} \
                 -value full  -objects [get_runs synth_1]

    reset_run synth_1
    launch_runs synth_1 -jobs 8
    wait_on_run synth_1
    if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} {
        puts "ERROR: Synthesis failed."
        exit 1
    }

    reset_run impl_1
    launch_runs impl_1 -jobs 8
    wait_on_run impl_1
    if {[get_property PROGRESS [get_runs impl_1]] ne "100%"} {
        puts "ERROR: Implementation failed."
        exit 1
    }

    open_run impl_1

    puts "\n=========================================="
    puts "Generating Reports..."
    puts "=========================================="
    report_timing_summary \
        -file [file normalize $root_dir/reports/timing_summary.rpt]
    report_timing -sort_by slack -max_paths 10 \
        -file [file normalize $root_dir/reports/timing_detailed.rpt]
    report_utilization \
        -file [file normalize $root_dir/reports/utilization.rpt]
    report_utilization -hierarchical \
        -file [file normalize $root_dir/reports/utilization_hierarchical.rpt]
    report_power \
        -file [file normalize $root_dir/reports/power.rpt]
    report_clock_networks \
        -file [file normalize $root_dir/reports/clock_networks.rpt]

    set wns [get_property SLACK [get_timing_paths]]
    set whs [get_property SLACK [get_timing_paths -hold]]
    puts "\n=========================================="
    puts "Timing Results"
    puts "=========================================="
    puts "WNS (Setup): $wns ns"
    puts "WHS (Hold):  $whs ns"
    if {$wns < 0} { puts "WARNING: Setup timing NOT MET!" } \
    else           { puts "Setup timing: MET" }
    if {$whs < 0} { puts "WARNING: Hold timing NOT MET!" } \
    else           { puts "Hold timing: MET" }

} else {
    puts "Implementation is up-to-date at ${clock_freq_mhz} MHz -- skipping impl."
    open_run impl_1
}

# --------------------------------------------------------------------------
# Generate bitstream.
# --------------------------------------------------------------------------
puts "\n=========================================="
puts "Generating Bitstream..."
puts "=========================================="

launch_runs impl_1 -to_step write_bitstream -jobs 8
wait_on_run impl_1

set bitstream_file [file normalize \
    $root_dir/vivado_proj/posit_research.runs/impl_1/zynq_accel_top.bit]
if {![file exists $bitstream_file]} {
    puts "\nERROR: Bitstream generation failed!"
    exit 1
}

puts "\n=========================================="
puts "Bitstream Complete!"
puts "=========================================="
puts "Location: $bitstream_file"
puts ""
puts "AXI Slave Register Map (base: 0x43C00000):"
puts "  0x00: CTRL         \[0\]=START, \[1\]=RESET"
puts "  0x04: STATUS        \[0\]=DONE,  \[1\]=RUNNING"
puts "  0x08: IBRAM_ADDR    instruction BRAM word index"
puts "  0x0C: IBRAM_DATA_LO instruction bits \[31:0\]"
puts "  0x10: IBRAM_DATA_HI instruction bits \[63:32\] (write triggers BRAM write)"
puts "  0x14: DBRAM_ADDR    data BRAM word index"
puts "  0x18: DBRAM_DATA    data BRAM word (32-bit)"
puts "  0x1C: DBRAM_DATA_HI data BRAM high word (DATA_WIDTH=64 only)"
puts "=========================================="
