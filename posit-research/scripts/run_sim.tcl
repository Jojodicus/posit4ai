# Simulation script for Posit Research project

set proj_name "posit_research"
set proj_dir "./vivado_proj"

# Close any existing open project first to avoid conflicts
catch {close_project -quiet}

# Open project if not already open
if {[get_projects -quiet $proj_name] == ""} {
    open_project $proj_dir/$proj_name.xpr
}

# Create simulation filesets if they don't exist
if {[get_filesets -quiet sim_harness] == ""} {
    create_fileset -simset sim_harness
}
if {[get_filesets -quiet sim_axi] == ""} {
    create_fileset -simset sim_axi
}
if {[get_filesets -quiet sim_pau] == ""} {
    create_fileset -simset sim_pau
}

# Add TB files to respective sets
add_files -fileset sim_harness [file normalize "../tb/tb_pau_fpu_harness.sv"]
add_files -fileset sim_axi [file normalize "../tb/tb_pau_fpu_harness_axi.sv"]
add_files -fileset sim_pau [file normalize "../tb/tb_pau_top.sv"]

# Set top modules
set_property top tb_pau_fpu_harness [get_filesets sim_harness]
set_property top tb_pau_fpu_harness_axi [get_filesets sim_axi]
set_property top tb_pau_top [get_filesets sim_pau]

# Helper proc to run simulation
proc run_test {simset} {
    current_fileset -simset [get_filesets $simset]
    launch_simulation -simset [get_filesets $simset]
    run all
}

puts "To run harness test:  run_test sim_harness"
puts "To run AXI test:      run_test sim_axi"
puts "To run PAU unit test: run_test sim_pau"
