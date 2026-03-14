# Create Block Design: Zynq PS7 + AXI Protocol Converter
# Exports AXI-Lite master, clock, and reset for connection to pau_fpu_harness_axi
# in the top-level wrapper (zynq_pau_top.sv).
#
# Must be sourced AFTER project_setup.tcl has added all RTL sources and IPs.

set root_dir [file normalize [file join [file dirname [info script]] ..]]

puts "=========================================="
puts "Creating Zynq PS Block Design"
puts "=========================================="

# Remove existing block design if present
set existing_bd [get_files -quiet "zynq_ps.bd"]
if {$existing_bd != ""} {
    puts "Removing existing block design..."
    remove_files $existing_bd
    file delete -force [file join $root_dir vivado_proj posit_research.srcs sources_1 bd zynq_ps]
    file delete -force [file join $root_dir vivado_proj posit_research.gen sources_1 bd zynq_ps]
}

# --- Try to set Zedboard board part ---
set board_set 0
foreach board_pattern {"avnet.com:zedboard*" "digilentinc.com:zedboard*" "*zedboard*"} {
    set board_parts [get_board_parts -quiet $board_pattern]
    if {[llength $board_parts] > 0} {
        set board_part [lindex $board_parts 0]
        set_property board_part $board_part [current_project]
        puts "Board part set to: $board_part"
        set board_set 1
        break
    }
}

if {!$board_set} {
    puts "INFO: Zedboard board part not found in local installation."
    puts "      Using manual PS7 configuration for Zedboard."
}

# --- Create Block Design ---
create_bd_design "zynq_ps"

# --- Add Processing System 7 ---
create_bd_cell -type ip -vlnv xilinx.com:ip:processing_system7:5.5 ps7

if {$board_set} {
    # Use board automation for DDR/MIO configuration
    apply_bd_automation -rule xilinx.com:bd_rule:processing_system7 \
        -config {make_external "FIXED_IO, DDR" Master "Disable" Slave "Disable"} \
        [get_bd_cells ps7]
} else {
    # Manual DDR/FIXED_IO external ports
    make_bd_intf_pins_external [get_bd_intf_pins ps7/DDR]
    make_bd_intf_pins_external [get_bd_intf_pins ps7/FIXED_IO]
}

# Configure PS7 for Zedboard
set_property -dict [list \
    CONFIG.PCW_USE_M_AXI_GP0 {1} \
    CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ {100} \
    CONFIG.PCW_CRYSTAL_PERIPHERAL_FREQMHZ {33.333333} \
    CONFIG.PCW_PRESET_BANK0_VOLTAGE {LVCMOS 3.3V} \
    CONFIG.PCW_PRESET_BANK1_VOLTAGE {LVCMOS 1.8V} \
    CONFIG.PCW_UIPARAM_DDR_PARTNO {MT41K128M16JT-125} \
    CONFIG.PCW_UIPARAM_DDR_MEMORY_TYPE {DDR 3} \
    CONFIG.PCW_UIPARAM_DDR_DEVICE_CAPACITY {2048 MBits} \
    CONFIG.PCW_UIPARAM_DDR_BUS_WIDTH {32 Bit} \
    CONFIG.PCW_UIPARAM_DDR_DRAM_WIDTH {16 Bits} \
    CONFIG.PCW_QSPI_PERIPHERAL_ENABLE {1} \
    CONFIG.PCW_QSPI_GRP_SINGLE_SS_ENABLE {1} \
    CONFIG.PCW_ENET0_PERIPHERAL_ENABLE {1} \
    CONFIG.PCW_ENET0_ENET0_IO {MIO 16 .. 27} \
    CONFIG.PCW_ENET0_GRP_MDIO_ENABLE {1} \
    CONFIG.PCW_ENET0_GRP_MDIO_IO {MIO 52 .. 53} \
    CONFIG.PCW_SD0_PERIPHERAL_ENABLE {1} \
    CONFIG.PCW_SD0_SD0_IO {MIO 40 .. 45} \
    CONFIG.PCW_UART1_PERIPHERAL_ENABLE {1} \
    CONFIG.PCW_UART1_UART1_IO {MIO 48 .. 49} \
    CONFIG.PCW_USB0_PERIPHERAL_ENABLE {1} \
    CONFIG.PCW_USB0_USB0_IO {MIO 28 .. 39} \
    CONFIG.PCW_GPIO_MIO_GPIO_ENABLE {1} \
    CONFIG.PCW_GPIO_MIO_GPIO_IO {MIO} \
] [get_bd_cells ps7]

# --- Add Processor System Reset ---
create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 rst_ps7

# --- Add AXI Protocol Converter (AXI3 -> AXI4-Lite) ---
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_protocol_converter:2.1 axi_pc
set_property -dict [list \
    CONFIG.SI_PROTOCOL {AXI3} \
    CONFIG.MI_PROTOCOL {AXI4LITE} \
] [get_bd_cells axi_pc]

# --- Connect Clock Network ---
connect_bd_net [get_bd_pins ps7/FCLK_CLK0] \
    [get_bd_pins ps7/M_AXI_GP0_ACLK] \
    [get_bd_pins rst_ps7/slowest_sync_clk] \
    [get_bd_pins axi_pc/aclk]

# --- Connect Reset Network ---
connect_bd_net [get_bd_pins ps7/FCLK_RESET0_N] \
    [get_bd_pins rst_ps7/ext_reset_in]

connect_bd_net [get_bd_pins rst_ps7/interconnect_aresetn] \
    [get_bd_pins axi_pc/aresetn]

# --- Connect AXI Data Path ---
connect_bd_intf_net [get_bd_intf_pins ps7/M_AXI_GP0] \
    [get_bd_intf_pins axi_pc/S_AXI]

# --- Export External Ports ---
# Clock output (FCLK_CLK0)
create_bd_port -dir O -type clk FCLK_CLK0
connect_bd_net [get_bd_pins ps7/FCLK_CLK0] [get_bd_ports FCLK_CLK0]

# Synchronized reset output (active low)
create_bd_port -dir O -type rst peripheral_aresetn
connect_bd_net [get_bd_pins rst_ps7/peripheral_aresetn] [get_bd_ports peripheral_aresetn]

# AXI-Lite master interface (to be connected to pau_fpu_harness_axi in top wrapper)
make_bd_intf_pins_external [get_bd_intf_pins axi_pc/M_AXI]
# Rename from auto-generated M_AXI_0 to M_AXI_LITE
set_property name M_AXI_LITE [get_bd_intf_ports M_AXI_0]

# --- Address Space ---
# PS7 M_AXI_GP0 maps to 0x4000_0000 - 0x7FFF_FFFF by default.
# With the AXI-Lite port exported externally, no in-BD address segment is needed.
# The software driver accesses registers at base address 0x43C0_0000.

# Exclude unconnected address segments to avoid validation warnings
catch {
    set addr_segs [get_bd_addr_segs -quiet]
    foreach seg $addr_segs {
        catch { exclude_bd_addr_seg $seg }
    }
}

# --- Validate Block Design ---
validate_bd_design
save_bd_design

# --- Generate Output Products ---
generate_target all [get_files zynq_ps.bd]

# --- Create HDL Wrapper ---
make_wrapper -files [get_files zynq_ps.bd] -top

# Find and add the wrapper file
set wrapper_files [glob -nocomplain \
    $root_dir/vivado_proj/posit_research.gen/sources_1/bd/zynq_ps/hdl/zynq_ps_wrapper.* \
    $root_dir/vivado_proj/posit_research.srcs/sources_1/bd/zynq_ps/hdl/zynq_ps_wrapper.* \
]
if {[llength $wrapper_files] > 0} {
    add_files -norecurse [lindex $wrapper_files 0]
    puts "Added BD wrapper: [lindex $wrapper_files 0]"
} else {
    puts "ERROR: Could not find generated BD wrapper file!"
    exit 1
}

puts ""
puts "=========================================="
puts "Block Design Created Successfully"
puts "=========================================="
puts "  PS7 FCLK_CLK0:     100 MHz"
puts "  AXI Slave base:    0x43C00000"
puts "  BD Wrapper:        zynq_ps_wrapper"
puts "  Exported ports:    FCLK_CLK0, peripheral_aresetn, M_AXI_LITE_*"
puts "  Top-level wrapper: zynq_pau_top (connects BD + pau_fpu_harness_axi)"
puts "=========================================="
