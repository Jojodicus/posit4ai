# Run a single sim fileset for fast iteration. Usage:
#   vivado -mode batch -source scripts/run_one_test.tcl -tclargs <simset>

if {![file exists vivado_proj/posit_research.xpr]} {
    source scripts/project_setup.tcl
} else {
    open_project vivado_proj/posit_research.xpr
}

set simset [lindex $argv 0]
if {$simset eq ""} { set simset sim_fpu32 }

current_fileset -simset [get_filesets $simset]
launch_simulation -simset [get_filesets $simset]
close_sim
exit 0
