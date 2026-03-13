
set proj_name "posit_research"
set proj_dir "./vivado_proj"
set target_part "xc7z020clg484-1"

set root_dir [file normalize [file join [file dirname [info script]] ..]]
set percival_dir [file normalize [file join $root_dir .. PERCIVAL]]

# Create project
create_project -force $proj_name $proj_dir -part $target_part

# Create Simulation Filesets
if {[get_filesets -quiet sim_harness] == ""} { create_fileset -simset sim_harness }
if {[get_filesets -quiet sim_axi] == ""} { create_fileset -simset sim_axi }
if {[get_filesets -quiet sim_pau] == ""} { create_fileset -simset sim_pau }

# Set project properties
set_property target_language Verilog [current_project]
set_property default_lib xil_defaultlib [current_project]

# Define XSIM macro for simulation to disable unsupported SystemVerilog features
set_property -name {xsim.compile.xvlog.more_options} -value {-d XSIM} -objects [current_fileset -simset]
foreach simset {sim_harness sim_axi sim_pau} {
    set_property -name {xsim.compile.xvlog.more_options} -value {-d XSIM} -objects [get_filesets $simset]
}

# Add Source Files
# Packages first
add_files -norecurse $root_dir/harness/cva6_config_pkg.sv
add_files -norecurse $root_dir/harness/riscv_pkg_mini.sv
add_files -norecurse $root_dir/harness/ariane_pkg_mini.sv
add_files -norecurse $root_dir/rtl/common_cells/src/cf_math_pkg.sv
add_files -norecurse $root_dir/rtl/fpu/src/fpnew_pkg.sv

# DO NOT set packages as Global Include - this prevents them from being compiled in XSim!
# SystemVerilog packages should be regular source files with proper compile order
# set_property is_global_include 1 [get_files $root_dir/harness/cva6_config_pkg.sv]
# set_property is_global_include 1 [get_files $root_dir/harness/riscv_pkg_mini.sv]
# set_property is_global_include 1 [get_files $root_dir/harness/ariane_pkg_mini.sv]
# set_property is_global_include 1 [get_files $root_dir/rtl/common_cells/src/cf_math_pkg.sv]
# set_property is_global_include 1 [get_files $root_dir/rtl/fpu/src/fpnew_pkg.sv]

# Set all .sv files to SystemVerilog early
# Use -filter to match all .sv files regardless of path
set all_sv_files [get_files -filter {FILE_TYPE == "Verilog" || NAME =~ "*.sv"}]
if {[llength $all_sv_files] > 0} {
    set_property file_type SystemVerilog $all_sv_files
}

# Common Cells and Macros
add_files -norecurse $root_dir/rtl/common_cells/src/lzc.sv
add_files -norecurse $root_dir/rtl/common_cells/src/rr_arb_tree.sv
# Use patched .svh files for Vivado XSim compatibility (removes default macro parameters)
add_files -norecurse $root_dir/harness/common_cells_patches/registers.svh
add_files -norecurse $root_dir/harness/common_cells_patches/assertions.svh

# Explicitly mark .svh files as SystemVerilog Headers (not Verilog)
set_property file_type {SystemVerilog Header} [get_files registers.svh]
set_property file_type {SystemVerilog Header} [get_files assertions.svh]
set_property is_global_include 1 [get_files registers.svh]
set_property is_global_include 1 [get_files assertions.svh]

# FPU Files
add_files -norecurse $root_dir/rtl/fpu/src/fpnew_fma.sv
add_files -norecurse $root_dir/rtl/fpu/src/fpnew_opgroup_fmt_slice.sv
add_files -norecurse $root_dir/rtl/fpu/src/fpnew_divsqrt_multi.sv
add_files -norecurse $root_dir/rtl/fpu/src/fpnew_fma_multi.sv
add_files -norecurse $root_dir/rtl/fpu/src/fpnew_opgroup_multifmt_slice.sv
add_files -norecurse $root_dir/rtl/fpu/src/fpnew_classifier.sv
add_files -norecurse $root_dir/rtl/fpu/src/fpnew_noncomp.sv
add_files -norecurse $root_dir/rtl/fpu/src/fpnew_cast_multi.sv
add_files -norecurse $root_dir/rtl/fpu/src/fpnew_opgroup_block.sv
add_files -norecurse $root_dir/rtl/fpu/src/fpnew_rounding.sv
add_files -norecurse $root_dir/rtl/fpu/src/fpnew_top.sv
add_files -norecurse [glob $root_dir/rtl/fpu/src/fpu_div_sqrt_mvp/hdl/*.sv]

# PAU Files (VHDL)
add_files -norecurse [glob $root_dir/rtl/pau/*.vhd]

# Wrapper and Harness
add_files -norecurse $percival_dir/core/pau_top.sv
add_files -norecurse $percival_dir/core/fpu_wrap.sv
add_files -norecurse $root_dir/harness/pau_fpu_harness.sv
add_files -norecurse $root_dir/harness/pau_fpu_harness_axi.sv

# Set Include Paths for sources_1
set_property include_dirs [list \
    [file normalize $root_dir/rtl/common_cells/include] \
    [file normalize $root_dir/rtl/fpu/src/fpu_div_sqrt_mvp/hdl] \
] [current_fileset]

# Set Include Paths for all simulation filesets
foreach simset {sim_harness sim_axi sim_pau} {
    set_property include_dirs [list \
        [file normalize $root_dir/rtl/common_cells/include] \
        [file normalize $root_dir/rtl/fpu/src/fpu_div_sqrt_mvp/hdl] \
    ] [get_filesets $simset]
}


set_property top pau_fpu_harness_axi [current_fileset]

# Add Testbenches
add_files -fileset sim_harness -norecurse $root_dir/tb/tb_pau_fpu_harness.sv
set_property top tb_pau_fpu_harness [get_filesets sim_harness]

add_files -fileset sim_axi -norecurse $root_dir/tb/tb_pau_fpu_harness_axi.sv
set_property top tb_pau_fpu_harness_axi [get_filesets sim_axi]

add_files -fileset sim_pau -norecurse $root_dir/tb/tb_pau_top.sv
set_property top tb_pau_top [get_filesets sim_pau]

# CRITICAL: Ensure package files are enabled for simulation
set_property used_in_simulation true [get_files */cva6_config_pkg.sv]
set_property used_in_simulation true [get_files */riscv_pkg_mini.sv]
set_property used_in_simulation true [get_files */ariane_pkg_mini.sv]
set_property used_in_simulation true [get_files */cf_math_pkg.sv]
set_property used_in_simulation true [get_files */fpnew_pkg.sv]

# Create Clocking Wizard
create_ip -name clk_wiz -vendor xilinx.com -library ip -version 6.0 -module_name clk_wiz_0
set_property -dict [list \
    CONFIG.PRIM_IN_FREQ {100.000} \
    CONFIG.CLKOUT1_REQUESTED_OUT_FREQ {100.000} \
] [get_ips clk_wiz_0]
generate_target all [get_ips clk_wiz_0]

# Create constraints fileset if it doesn't exist
if {[get_filesets -quiet constrs_1] == ""} {
    create_fileset -constrset constrs_1
}

# Add constraint file if it exists
set constraint_file [file normalize $root_dir/constraints/pau_axi_timing.xdc]
if {[file exists $constraint_file]} {
    add_files -fileset constrs_1 -norecurse $constraint_file
}

# Create reports directory
file mkdir [file normalize $root_dir/reports]

# Ensure ALL .sv files are marked as SystemVerilog (catch any added after earlier setting)
set all_sv_files [get_files -filter {NAME =~ "*.sv"}]
if {[llength $all_sv_files] > 0} {
    set_property file_type SystemVerilog $all_sv_files
    puts "Set SystemVerilog file type for [llength $all_sv_files] files"
}

# Explicitly set compile order dependencies for packages
# This ensures riscv_pkg_mini compiles before ariane_pkg_mini
set_property used_in_synthesis true [get_files */cva6_config_pkg.sv]
set_property used_in_simulation true [get_files */cva6_config_pkg.sv]
set_property used_in_synthesis true [get_files */riscv_pkg_mini.sv]
set_property used_in_simulation true [get_files */riscv_pkg_mini.sv]
set_property used_in_synthesis true [get_files */ariane_pkg_mini.sv]
set_property used_in_simulation true [get_files */ariane_pkg_mini.sv]

# Update compile order FIRST (automatic dependency detection)
update_compile_order -fileset sources_1
update_compile_order -fileset sim_harness
update_compile_order -fileset sim_axi
update_compile_order -fileset sim_pau

# THEN explicitly reorder packages to ensure correct compilation order
# The order MUST be: cva6_config_pkg -> riscv_pkg_mini -> ariane_pkg_mini -> cf_math_pkg -> fpnew_pkg
# Build the order by moving files to front in REVERSE order (last file first)
set pkg_files [list \
    [get_files */cva6_config_pkg.sv] \
    [get_files */riscv_pkg_mini.sv] \
    [get_files */ariane_pkg_mini.sv] \
    [get_files */cf_math_pkg.sv] \
    [get_files */fpnew_pkg.sv] \
]

# Reorder in sources_1 - move to front in reverse order
reorder_files -fileset sources_1 -front [lindex $pkg_files 4]
reorder_files -fileset sources_1 -front [lindex $pkg_files 3]
reorder_files -fileset sources_1 -front [lindex $pkg_files 2]
reorder_files -fileset sources_1 -front [lindex $pkg_files 1]
reorder_files -fileset sources_1 -front [lindex $pkg_files 0]

# Simulation filesets inherit compile order from sources_1 for files marked used_in_simulation
# No need to reorder in simulation filesets - they follow sources_1 order

puts "Compile order manually set: cva6 -> riscv -> ariane -> cf_math -> fpnew"
