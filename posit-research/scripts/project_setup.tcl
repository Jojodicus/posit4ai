
set proj_name "posit_research"
set proj_dir "./vivado_proj"
set target_part "xc7z020clg484-1"

set root_dir [file normalize [file join [file dirname [info script]] ..]]

# Create project
create_project -force $proj_name $proj_dir -part $target_part

# Create Simulation Filesets
if {[get_filesets -quiet sim_core] == ""} { create_fileset -simset sim_core }
if {[get_filesets -quiet sim_axi]  == ""} { create_fileset -simset sim_axi  }

# Set project properties
set_property target_language Verilog [current_project]
set_property default_lib xil_defaultlib [current_project]

# Define XSIM macro for simulation to disable unsupported SystemVerilog features
foreach simset {sim_core sim_axi} {
    set_property -name {xsim.compile.xvlog.more_options} -value {-d XSIM} -objects [get_filesets $simset]
}

# ── Add Source Files ───────────────────────────────────────────────────────────
# Packages — compilation ORDER MATTERS: config_pkg first, then riscv, then ariane

# 1. User configuration (no dependencies)
add_files -norecurse $root_dir/harness/config_pkg.sv

# 2. Accelerator opcode set (no dependencies)
add_files -norecurse $root_dir/harness/opcodes_pkg.sv

# 3. CVA6/riscv packages (needed by pau_top and fpu_wrap)
add_files -norecurse $root_dir/harness/cva6_config_pkg.sv
add_files -norecurse $root_dir/harness/riscv_pkg_mini.sv

# 4. ariane_pkg (imports config_pkg and riscv)
add_files -norecurse $root_dir/harness/ariane_pkg_mini.sv

# 5. fpnew support packages
add_files -norecurse $root_dir/rtl/common_cells/src/cf_math_pkg.sv
add_files -norecurse $root_dir/rtl/fpu/src/fpnew_pkg.sv

# Set all .sv files to SystemVerilog
set all_sv_files [get_files -filter {FILE_TYPE == "Verilog" || NAME =~ "*.sv"}]
if {[llength $all_sv_files] > 0} {
    set_property file_type SystemVerilog $all_sv_files
}

# ── Common Cells ───────────────────────────────────────────────────────────────
add_files -norecurse $root_dir/rtl/common_cells/src/lzc.sv
add_files -norecurse $root_dir/rtl/common_cells/src/rr_arb_tree.sv

# Patched .svh files for Vivado XSim compatibility
add_files -norecurse $root_dir/harness/common_cells_patches/registers.svh
add_files -norecurse $root_dir/harness/common_cells_patches/assertions.svh
add_files -norecurse $root_dir/harness/common_cells_patches/common_cells/registers.svh
add_files -norecurse $root_dir/harness/common_cells_patches/common_cells/assertions.svh

foreach svh_file [get_files -filter {NAME =~ "*.svh"}] {
    set_property file_type {SystemVerilog Header} $svh_file
    set_property is_global_include 1 $svh_file
}

# ── FPU Files ──────────────────────────────────────────────────────────────────
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

# ── PAU Files (VHDL) ───────────────────────────────────────────────────────────
add_files -norecurse [glob $root_dir/rtl/pau/*.vhd]

# ── Accelerator RTL ────────────────────────────────────────────────────────────
# Local copies of PERCIVAL cores (editable)
add_files -norecurse $root_dir/harness/pau_top.sv
add_files -norecurse $root_dir/harness/fpu_wrap.sv

# New accelerator modules (in dependency order)
add_files -norecurse $root_dir/harness/arith_unit.sv
add_files -norecurse $root_dir/harness/accel_core.sv
add_files -norecurse $root_dir/harness/accel_axi.sv
add_files -norecurse $root_dir/harness/accel_harness.sv
add_files -norecurse $root_dir/harness/zynq_accel_top.sv

# ── Include Paths ──────────────────────────────────────────────────────────────
set inc_dirs [list \
    [file normalize $root_dir/harness/common_cells_patches] \
    [file normalize $root_dir/rtl/common_cells/include] \
    [file normalize $root_dir/rtl/fpu/src/fpu_div_sqrt_mvp/hdl] \
]
set_property include_dirs $inc_dirs [current_fileset]
foreach simset {sim_core sim_axi} {
    set_property include_dirs $inc_dirs [get_filesets $simset]
}

set_property top accel_axi [current_fileset]

# ── Testbenches ────────────────────────────────────────────────────────────────
add_files -fileset sim_core -norecurse $root_dir/tb/tb_accel_core.sv
set_property top tb_accel_core [get_filesets sim_core]

add_files -fileset sim_axi -norecurse $root_dir/tb/tb_accel_axi.sv
set_property top tb_accel_axi [get_filesets sim_axi]

# ── Ensure packages are used in simulation ─────────────────────────────────────
foreach pkg {config_pkg.sv opcodes_pkg.sv cva6_config_pkg.sv riscv_pkg_mini.sv ariane_pkg_mini.sv cf_math_pkg.sv fpnew_pkg.sv} {
    catch { set_property used_in_simulation true [get_files */$pkg] }
    catch { set_property used_in_synthesis  true [get_files */$pkg] }
}

# ── Clocking Wizard IP ─────────────────────────────────────────────────────────
create_ip -name clk_wiz -vendor xilinx.com -library ip -version 6.0 -module_name clk_wiz_0
set_property -dict [list \
    CONFIG.PRIM_IN_FREQ {100.000} \
    CONFIG.CLKOUT1_REQUESTED_OUT_FREQ {100.000} \
    CONFIG.SAFE_CLK_STARTUP {true} \
    CONFIG.USE_RESET {false} \
] [get_ips clk_wiz_0]
generate_target all [get_ips clk_wiz_0]

# ── Constraints ────────────────────────────────────────────────────────────────
if {[get_filesets -quiet constrs_1] == ""} { create_fileset -constrset constrs_1 }
set timing_constraint [file normalize $root_dir/constraints/pau_axi_timing.xdc]
if {[file exists $timing_constraint]} {
    add_files -fileset constrs_1 -norecurse $timing_constraint
}
set zedboard_constraint [file normalize $root_dir/constraints/zedboard_master_XDC_RevC_D_v3.xdc]
if {[file exists $zedboard_constraint]} {
    add_files -fileset constrs_1 -norecurse $zedboard_constraint
}

file mkdir [file normalize $root_dir/reports]

# Ensure all .sv files are SystemVerilog
set all_sv_files [get_files -filter {NAME =~ "*.sv"}]
if {[llength $all_sv_files] > 0} {
    set_property file_type SystemVerilog $all_sv_files
}

# ── Set compile order (packages must come first) ───────────────────────────────
update_compile_order -fileset sources_1
update_compile_order -fileset sim_core
update_compile_order -fileset sim_axi

# Explicitly place packages at front of compile order (reverse order)
set pkg_files [list \
    [get_files */config_pkg.sv]       \
    [get_files */opcodes_pkg.sv]      \
    [get_files */cva6_config_pkg.sv]  \
    [get_files */riscv_pkg_mini.sv]   \
    [get_files */ariane_pkg_mini.sv]  \
    [get_files */cf_math_pkg.sv]      \
    [get_files */fpnew_pkg.sv]        \
]
reorder_files -fileset sources_1 -front [lindex $pkg_files 6]
reorder_files -fileset sources_1 -front [lindex $pkg_files 5]
reorder_files -fileset sources_1 -front [lindex $pkg_files 4]
reorder_files -fileset sources_1 -front [lindex $pkg_files 3]
reorder_files -fileset sources_1 -front [lindex $pkg_files 2]
reorder_files -fileset sources_1 -front [lindex $pkg_files 1]
reorder_files -fileset sources_1 -front [lindex $pkg_files 0]

puts "Compile order: config_pkg → opcodes_pkg → cva6 → riscv → ariane → cf_math → fpnew"

# ── Create Zynq PS Block Design ────────────────────────────────────────────────
puts ""
puts "Creating Zynq PS block design..."
source [file join $root_dir scripts create_bd.tcl]

set_property top zynq_accel_top [current_fileset]
update_compile_order -fileset sources_1

puts ""
puts "Project setup complete."
puts "  Top module (impl):  zynq_accel_top"
puts "  Top module (build): accel_harness (set by run_build.tcl)"
puts ""
puts "AXI Slave Register Map (base: 0x43C00000):"
puts "  0x00  CTRL    \[0\]=START, \[1\]=RESET"
puts "  0x04  STATUS  \[0\]=DONE,  \[1\]=RUNNING"
puts "  0x08  IBRAM_ADDR"
puts "  0x0C  IBRAM_DATA_LO"
puts "  0x10  IBRAM_DATA_HI  (write triggers BRAM write)"
puts "  0x14  DBRAM_ADDR"
puts "  0x18  DBRAM_DATA"
puts "  0x1C  DBRAM_DATA_HI  (DATA_WIDTH=64 only)"
