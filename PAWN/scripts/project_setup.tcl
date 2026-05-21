
set proj_name "posit_research"
set proj_dir "./vivado_proj"
set target_part "xc7z020clg484-1"

set root_dir [file normalize [file join [file dirname [info script]] ..]]

# Create project
create_project -force $proj_name $proj_dir -part $target_part

# Simulation fileset names.
# Each accel_core fileset compiles tb_accel_core.sv against its own config_pkg override.
# sim_axi uses PAU-32 config and tests the AXI register interface only.
set accel_core_simsets {sim_pau8 sim_pau16 sim_pau16_approx sim_pau32 sim_pau32_approx sim_pau32_approx_div sim_pau32_approx_sqrt sim_pau64 sim_fpu32 sim_fpu64
                        sim_pau8_noquire sim_pau16_noquire sim_pau32_noquire
                        sim_flo_pau32 sim_flo_pau32_approx sim_flo_pau32_noquire
                        sim_flo_pau32_nodiv sim_pau32_disabled}
set axi_simsets        {sim_axi sim_axi_pau64 sim_axi_fpu32}
set all_simsets        [concat $accel_core_simsets $axi_simsets]

foreach simset $all_simsets {
    if {[get_filesets -quiet $simset] == ""} { create_fileset -simset $simset }
}

# Set project properties
set_property target_language Verilog [current_project]
set_property default_lib xil_defaultlib [current_project]

# Define XSIM macro for simulation to disable unsupported SystemVerilog features
foreach simset $all_simsets {
    set_property -name {xsim.compile.xvlog.more_options} -value {-d XSIM} -objects [get_filesets $simset]
}

# -- Add Source Files -----------------------------------------------------
# Packages -- compilation ORDER MATTERS: config_pkg first, then riscv, then ariane

# 1. User configuration (synthesis/implementation only -- simulation uses per-fileset overrides)
add_files -norecurse $root_dir/harness/config_pkg.sv
set_property used_in_simulation false [get_files */config_pkg.sv]

# 2. Accelerator opcode set (no dependencies)
add_files -norecurse $root_dir/harness/pkg/opcodes_pkg.sv

# 3. CVA6/riscv packages (needed by pau_top and fpu_wrap)
add_files -norecurse $root_dir/harness/pkg/cva6_config_pkg.sv
add_files -norecurse $root_dir/harness/pkg/riscv_pkg_mini.sv

# 4. ariane_pkg (imports config_pkg and riscv)
add_files -norecurse $root_dir/harness/pkg/ariane_pkg_mini.sv

# 5. fpnew support packages
add_files -norecurse $root_dir/rtl/common_cells/src/cf_math_pkg.sv
add_files -norecurse $root_dir/rtl/fpu/src/fpnew_pkg.sv

# Set all .sv files to SystemVerilog
set all_sv_files [get_files -filter {FILE_TYPE == "Verilog" || NAME =~ "*.sv"}]
if {[llength $all_sv_files] > 0} {
    set_property file_type SystemVerilog $all_sv_files
}

# -- Common Cells --------------------------------------------------------
add_files -norecurse $root_dir/rtl/common_cells/src/lzc.sv
add_files -norecurse $root_dir/rtl/common_cells/src/rr_arb_tree.sv

# Patched .svh files for Vivado XSim compatibility.
# Upstream PERCIVAL sources use `include "common_cells/registers.svh"` (with the
# directory prefix), so include_dirs must point at the parent of common_cells/
# and the files live inside that subdirectory.
add_files -norecurse $root_dir/harness/patches/common_cells/registers.svh
add_files -norecurse $root_dir/harness/patches/common_cells/assertions.svh

foreach svh_file [get_files -filter {NAME =~ "*.svh"}] {
    set_property file_type {SystemVerilog Header} $svh_file
    set_property is_global_include 1 $svh_file
}

# -- FPU Files ----------------------------------------------------------
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

# -- PAU Files (VHDL) ---------------------------------------------------
add_files -norecurse [glob $root_dir/rtl/pau/*.vhd]

# -- Flo-Posit FloPoCo Files (VHDL) ----------------------------------
# brent_kung adder primitive (shared by all PositMAC wrappers; only one copy needed)
add_files -norecurse $root_dir/rtl/Flo-Posit/PositMAC/brent_kung/no_pipe/brent_kung_PositMAC_8_2_30/brent_kung.vhd
# PositMAC wrappers -- entities renamed to avoid collision with PERCIVAL's PositMAC
add_files -norecurse $root_dir/harness/arith/positmac8.vhd
add_files -norecurse $root_dir/harness/arith/positmac16.vhd
add_files -norecurse $root_dir/harness/arith/positmac32.vhd
# Compile each MAC wrapper into its own library to avoid internal FloPoCo entity
# name collisions (PositDecoder_*_uid4/8, IntMultiplier_F0_uid12, etc. are reused
# across 8-bit, 16-bit and 32-bit with different port widths).  In VHDL, "library work;"
# resolves to the file's own compile library, so each MAC file finds its own
# correctly-ported sub-entities.  brent_kung.vhd stays in 'work'; Vivado's global
# entity binding finds it from flo_mac8, flo_mac16, and flo_mac32 at elaboration time.
set_property library flo_mac8  [get_files positmac8.vhd]
set_property library flo_mac16 [get_files positmac16.vhd]
set_property library flo_mac32 [get_files positmac32.vhd]
# Remaining Flo-Posit cores (unique entity names, direct submodule references)
# 8/16/32-bit Add and Mult share some sub-entity names within each pair -- same pattern
# as 8 vs 16 bit; Vivado accepts identical duplicate declarations in 'work'.
# PERCIVAL uses _F50_ frequency suffix; FloPoCo uses _F0_ -- no cross-library conflict.
add_files -norecurse $root_dir/harness/arith/posit_add8_tc.vhdl
add_files -norecurse $root_dir/harness/arith/posit_add16_tc.vhdl
add_files -norecurse $root_dir/harness/arith/posit_add32_tc.vhdl
add_files -norecurse $root_dir/harness/arith/posit_mult8_tc.vhdl
add_files -norecurse $root_dir/harness/arith/posit_mult16_tc.vhdl
add_files -norecurse $root_dir/harness/arith/posit_mult32_tc.vhdl
set_property library flo_tc_add8  [get_files posit_add8_tc.vhdl]
set_property library flo_tc_add16 [get_files posit_add16_tc.vhdl]
set_property library flo_tc_add32 [get_files posit_add32_tc.vhdl]
set_property library flo_tc_mul8  [get_files posit_mult8_tc.vhdl]
set_property library flo_tc_mul16 [get_files posit_mult16_tc.vhdl]
set_property library flo_tc_mul32 [get_files posit_mult32_tc.vhdl]
add_files -norecurse $root_dir/rtl/Flo-Posit/PositDiv/8_bit/flopoco.vhdl
add_files -norecurse $root_dir/rtl/Flo-Posit/PositDiv/16_bit/flopoco.vhdl
add_files -norecurse $root_dir/rtl/Flo-Posit/PositDiv/32_bit/flopoco.vhdl
add_files -norecurse $root_dir/rtl/Flo-Posit/PositLAM/PositLAM_8_2/flopoco.vhdl
add_files -norecurse $root_dir/rtl/Flo-Posit/PositLAM/PositLAM_16_2/flopoco.vhdl
add_files -norecurse $root_dir/rtl/Flo-Posit/PositLAM/PositLAM_32_2/flopoco.vhdl

# -- Accelerator RTL ------------------------------------------------
# Local copies of PERCIVAL cores (editable)
add_files -norecurse $root_dir/harness/arith/pau_top.sv
add_files -norecurse $root_dir/harness/arith/fpu_wrap.sv

# FloPoCo wrapper (quire2posit_sm must precede flo_posit_top)
add_files -norecurse $root_dir/harness/arith/quire2posit_sm.sv
add_files -norecurse $root_dir/harness/arith/flo_posit_top.sv

# New accelerator modules (in dependency order)
add_files -norecurse $root_dir/harness/arith/arith_unit.sv
add_files -norecurse $root_dir/harness/core/accel_core.sv
add_files -norecurse $root_dir/harness/axi/accel_axi.sv
add_files -norecurse $root_dir/harness/axi/accel_dbram_arb.sv
add_files -norecurse $root_dir/harness/axi/accel_axi_burst.sv
add_files -norecurse $root_dir/harness/axi/accel_ibram_burst.sv
add_files -norecurse $root_dir/harness/top/accel_harness.sv
add_files -norecurse $root_dir/harness/top/zynq_accel_top.sv

# -- Include Paths -------------------------------------------------
set inc_dirs [list \
    [file normalize $root_dir/harness/patches] \
    [file normalize $root_dir/rtl/common_cells/include] \
    [file normalize $root_dir/rtl/fpu/src/fpu_div_sqrt_mvp/hdl] \
]
set_property include_dirs $inc_dirs [current_fileset]
foreach simset $all_simsets {
    set_property include_dirs $inc_dirs [get_filesets $simset]
}

set_property top accel_axi [current_fileset]

# -- Testbenches ------------------------------------------------
# Map each accel_core sim fileset to its config override + testbench.
# config_pkg_*.sv defines package config_pkg for that fileset (overrides harness/config_pkg.sv).
foreach {simset cfg_file} {
    sim_pau8             tb/configs/config_pkg_pau8.sv
    sim_pau16            tb/configs/config_pkg_pau16.sv
    sim_pau16_approx     tb/configs/config_pkg_pau16_approx.sv
    sim_pau32            tb/configs/config_pkg_pau32.sv
    sim_pau32_approx     tb/configs/config_pkg_pau32_approx.sv
    sim_pau32_approx_div  tb/configs/config_pkg_pau32_approx_div.sv
    sim_pau32_approx_sqrt tb/configs/config_pkg_pau32_approx_sqrt.sv
    sim_pau64            tb/configs/config_pkg_pau64.sv
    sim_fpu32            tb/configs/config_pkg_fpu32.sv
    sim_fpu64            tb/configs/config_pkg_fpu64.sv
    sim_pau8_noquire     tb/configs/config_pkg_pau8_noquire.sv
    sim_pau16_noquire    tb/configs/config_pkg_pau16_noquire.sv
    sim_pau32_noquire    tb/configs/config_pkg_pau32_noquire.sv
    sim_flo_pau32         tb/configs/config_pkg_flo_pau32.sv
    sim_flo_pau32_approx  tb/configs/config_pkg_flo_pau32_approx.sv
    sim_flo_pau32_noquire tb/configs/config_pkg_flo_pau32_noquire.sv
    sim_flo_pau32_nodiv   tb/configs/config_pkg_flo_pau32_nodiv.sv
    sim_pau32_disabled    tb/configs/config_pkg_pau32_disabled.sv
} {
    add_files -fileset $simset -norecurse [file normalize $root_dir/$cfg_file]
    add_files -fileset $simset -norecurse $root_dir/tb/tb_accel_core.sv
    set_property top tb_accel_core [get_filesets $simset]
}

# AXI integration filesets -- each tests the full AXI path with a different config.
# sim_axi      (PAU-32): verifies 32-bit DBRAM write/read path and STATUS polling.
# sim_axi_pau64 (PAU-64): verifies DBRAM_DATA_HI 64-bit write/read path.
foreach {simset cfg_file} {
    sim_axi       tb/configs/config_pkg_pau32.sv
    sim_axi_pau64 tb/configs/config_pkg_pau64.sv
    sim_axi_fpu32 tb/configs/config_pkg_fpu32.sv
} {
    add_files -fileset $simset -norecurse [file normalize $root_dir/$cfg_file]
    add_files -fileset $simset -norecurse $root_dir/tb/tb_accel_axi.sv
    set_property top tb_accel_axi [get_filesets $simset]
}

# -- Ensure packages are used in simulation --------------------------
# config_pkg.sv is synthesis-only; the rest are shared.
foreach pkg {opcodes_pkg.sv cva6_config_pkg.sv riscv_pkg_mini.sv ariane_pkg_mini.sv cf_math_pkg.sv fpnew_pkg.sv} {
    catch { set_property used_in_simulation true [get_files */$pkg] }
    catch { set_property used_in_synthesis  true [get_files */$pkg] }
}

# -- Clocking Wizard IPs --------------------------------------------
# clk_wiz_0: used by accel_harness (build flow). 100 MHz board clock ->
#   CLKOUT1=target (clk_core), CLKOUT2=2x (clk_bram).
create_ip -name clk_wiz -vendor xilinx.com -library ip -version 6.0 -module_name clk_wiz_0
set_property -dict [list \
    CONFIG.PRIM_IN_FREQ {100.000} \
    CONFIG.CLKOUT1_REQUESTED_OUT_FREQ {100.000} \
    CONFIG.CLKOUT2_USED {true} \
    CONFIG.CLKOUT2_REQUESTED_OUT_FREQ {200.000} \
    CONFIG.CLKOUT2_REQUESTED_PHASE {180.000} \
    CONFIG.USE_SAFE_CLOCK_STARTUP {true} \
] [get_ips clk_wiz_0]
generate_target all [get_ips clk_wiz_0]

# -- Constraints ----------------------------------------------------
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

# -- Set compile order (packages must come first) ---------------------
update_compile_order -fileset sources_1
foreach simset $all_simsets {
    update_compile_order -fileset $simset
}

# Explicitly place packages at front of compile order for sources_1 (reverse order)
set src_pkg_files [list \
    [get_files -of_objects [get_filesets sources_1] */config_pkg.sv]      \
    [get_files -of_objects [get_filesets sources_1] */opcodes_pkg.sv]     \
    [get_files -of_objects [get_filesets sources_1] */cva6_config_pkg.sv] \
    [get_files -of_objects [get_filesets sources_1] */riscv_pkg_mini.sv]  \
    [get_files -of_objects [get_filesets sources_1] */ariane_pkg_mini.sv] \
    [get_files -of_objects [get_filesets sources_1] */cf_math_pkg.sv]     \
    [get_files -of_objects [get_filesets sources_1] */fpnew_pkg.sv]       \
]
# Place packages front-to-back by iterating the list in reverse
# (reorder_files -front each one, last in list ends up first)
for {set i [expr {[llength $src_pkg_files] - 1}]} {$i >= 0} {incr i -1} {
    set f [lindex $src_pkg_files $i]
    if {$f ne ""} { reorder_files -fileset sources_1 -front $f }
}

# For each sim fileset, ensure its config_pkg override is compiled first.
foreach simset $all_simsets {
    set cfg_file [get_files -of_objects [get_filesets $simset] */config_pkg_*.sv]
    if {$cfg_file ne ""} {
        reorder_files -fileset $simset -front $cfg_file
    }
}

puts "Compile order: config_pkg -> opcodes_pkg -> cva6 -> riscv -> ariane -> cf_math -> fpnew"

# -- Create Zynq PS Block Design ------------------------------------
puts ""
puts "Creating Zynq PS block design..."
source -notrace [file join $root_dir scripts create_bd.tcl]

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
