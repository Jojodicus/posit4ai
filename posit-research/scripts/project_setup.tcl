
set proj_name "posit_research"
set proj_dir "./vivado_proj"
set target_part "xc7z020clg484-1"

set root_dir [file normalize [file join [file dirname [info script]] ..]]
set percival_dir [file normalize [file join $root_dir .. PERCIVAL]]

# Create project
create_project -force $proj_name $proj_dir -part $target_part

# Set project properties
set_property target_language Verilog [current_project]
set_property default_lib xil_defaultlib [current_project]

# Add Source Files
# Packages first
add_files -norecurse $root_dir/harness/cva6_config_pkg.sv
add_files -norecurse $root_dir/harness/riscv_pkg_mini.sv
add_files -norecurse $root_dir/harness/ariane_pkg_mini.sv
add_files -norecurse $root_dir/rtl/common_cells/src/cf_math_pkg.sv
add_files -norecurse $root_dir/rtl/fpu/src/fpnew_pkg.sv

# Set packages as Global Include
set_property is_global_include 1 [get_files $root_dir/harness/cva6_config_pkg.sv]
set_property is_global_include 1 [get_files $root_dir/harness/riscv_pkg_mini.sv]
set_property is_global_include 1 [get_files $root_dir/harness/ariane_pkg_mini.sv]
set_property is_global_include 1 [get_files $root_dir/rtl/common_cells/src/cf_math_pkg.sv]
set_property is_global_include 1 [get_files $root_dir/rtl/fpu/src/fpnew_pkg.sv]

# Set all .sv files to SystemVerilog early
set_property file_type SystemVerilog [get_files *.sv]

# Common Cells and Macros
add_files -norecurse $root_dir/rtl/common_cells/src/lzc.sv
add_files -norecurse $root_dir/rtl/common_cells/src/rr_arb_tree.sv
add_files -norecurse $root_dir/rtl/common_cells/include/common_cells/registers.svh
add_files -norecurse $root_dir/rtl/common_cells/include/common_cells/assertions.svh

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

# Set Include Paths
set_property include_dirs [list \
    [file normalize $root_dir/rtl/common_cells/include] \
    [file normalize $root_dir/rtl/fpu/src/fpu_div_sqrt_mvp/hdl] \
] [current_fileset]


set_property top pau_fpu_harness [current_fileset]

# Create Clocking Wizard
create_ip -name clk_wiz -vendor xilinx.com -library ip -version 6.0 -module_name clk_wiz_0
set_property -dict [list \
    CONFIG.PRIM_IN_FREQ {100.000} \
    CONFIG.CLKOUT1_REQUESTED_OUT_FREQ {100.000} \
] [get_ips clk_wiz_0]
generate_target all [get_ips clk_wiz_0]

update_compile_order -fileset sources_1
