# Automated Testbench Execution
# Runs all three simulation filesets and reports results

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

# List of simulation filesets to run
set sim_filesets [list sim_core sim_axi]

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
    set_property -name {xsim.simulate.runtime} -value {10us} -objects [get_filesets $sim_set]

    # Launch simulation
    set sim_result [catch {
        launch_simulation

        # Wait for simulation to complete
        # The simulation will run for the specified runtime

        # Close simulation
        close_sim

    } sim_error]

    if {$sim_result != 0} {
        puts "FAILED: $sim_set"
        puts "Error: $sim_error"
        lappend failed_tests $sim_set
    } else {
        puts "PASSED: $sim_set"
        lappend passed_tests $sim_set
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
