# Automated Testbench Execution
# Runs all simulation filesets (one per config variant) and reports results

set proj_name "posit_research"
set proj_dir "./vivado_proj"
set root_dir [file normalize [file join [file dirname [info script]] ..]]

puts "=========================================="
puts "Running All Testbenches"
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

# List of simulation filesets to run.
# Each sim_pau*/sim_fpu* fileset compiles tb_accel_core against its own config_pkg
# override, so the full comparison matrix is covered in one test run.
set sim_filesets [list \
    sim_pau8             \
    sim_pau16            \
    sim_pau16_approx     \
    sim_pau32            \
    sim_pau32_approx     \
    sim_pau32_approx_div \
    sim_pau32_approx_sqrt \
    sim_pau64            \
    sim_fpu32            \
    sim_fpu64            \
    sim_pau8_noquire     \
    sim_pau16_noquire    \
    sim_pau32_noquire    \
    sim_flo_pau32         \
    sim_flo_pau32_approx  \
    sim_flo_pau32_noquire \
    sim_flo_pau32_nodiv   \
    sim_pau32_disabled    \
    sim_axi               \
    sim_axi_pau64        \
    sim_axi_fpu32        \
]

# Track results
set failed_tests [list]
set passed_tests [list]

# Run each simulation
foreach sim_set $sim_filesets {
    puts "\n=========================================="
    puts "Running simulation: $sim_set"
    puts "=========================================="

    # Set as active simulation fileset
    set_property target_simulator XSim [current_project]
    current_fileset -simset [get_filesets $sim_set]

    # Set simulation runtime (long enough for typical tests)
    set_property -name {xsim.simulate.runtime} -value {50us} -objects [get_filesets $sim_set]

    # Launch simulation
    set sim_result [catch {
        launch_simulation

        # Wait for simulation to complete
        # The simulation will run for the specified runtime

        # Close simulation
        close_sim

    } sim_error]

    if {$sim_result != 0} {
        puts "FAILED: $sim_set (simulation error)"
        puts "Error: $sim_error"
        lappend failed_tests $sim_set
    } else {
        # Check simulation log for FAIL/TIMEOUT strings
        set log_file "${proj_dir}/${proj_name}.sim/${sim_set}/behav/xsim/simulate.log"
        set has_fail 0
        if {[file exists $log_file]} {
            set fp [open $log_file r]
            set log_content [read $fp]
            close $fp
            if {[regexp -nocase {FAIL:|TIMEOUT:|FATAL|Assertion failed|\$fatal|ASSERT } $log_content]} {
                set has_fail 1
            }
        }
        if {$has_fail} {
            puts "FAILED: $sim_set (test assertions failed)"
            lappend failed_tests $sim_set
        } else {
            puts "PASSED: $sim_set"
            lappend passed_tests $sim_set
        }
    }
}

# Report summary
puts "\n=========================================="
puts "Test Summary"
puts "=========================================="
puts "Passed: [llength $passed_tests] / [llength $sim_filesets]"
puts "Failed: [llength $failed_tests] / [llength $sim_filesets]"

if {[llength $passed_tests] > 0} {
    puts "\nPassed tests:"
    foreach test $passed_tests {
        puts "  - $test"
    }
}

if {[llength $failed_tests] > 0} {
    puts "\nFailed tests:"
    foreach test $failed_tests {
        puts "  - $test"
    }
    puts "\nERROR: Some tests failed!"
    exit 1
} else {
    puts "\nAll tests passed!"
}

puts "=========================================="
