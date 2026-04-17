# Create Block Design: Zynq PS7 + AXI Protocol Converter
# Exports AXI-Lite master, clock, and reset for connection to accel_axi
# in the top-level wrapper (zynq_accel_top.sv).
#
# Must be sourced AFTER project_setup.tcl has added all RTL sources and IPs.

set root_dir [file normalize [file join [file dirname [info script]] ..]]

if {[info exists env(CLOCK_FREQ_MHZ)]} {
    set clock_freq_mhz $env(CLOCK_FREQ_MHZ)
} else {
    set clock_freq_mhz 100
}

puts "=========================================="
puts "Creating Zynq PS Block Design (FCLK0 = ${clock_freq_mhz} MHz)"
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
    CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ "$clock_freq_mhz" \
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

# AXI-Lite master interface (to be connected to accel_axi in top wrapper)
make_bd_intf_pins_external [get_bd_intf_pins axi_pc/M_AXI]
# Rename from auto-generated M_AXI_0 to M_AXI_LITE
set_property name M_AXI_LITE [get_bd_intf_ports M_AXI_0]

# --- Enable M_AXI_GP1 for burst DBRAM access (PS master -> PL slave) ---
# GP1 is the second PS7 AXI3 master port (PS CPU -> PL fabric direction).
# NOTE: S_AXI_HP0 is PL->PS direction (PL DMA -> DDR), NOT suitable for PS->PL BRAM.
# GP1 (32-bit AXI3) converted to AXI4 gives burst-capable PS->PL path for bulk DBRAM loads.
set_property CONFIG.PCW_USE_M_AXI_GP1 {1} [get_bd_cells ps7]

# AXI Protocol Converter: AXI3 (GP1) -> AXI4 (burst-capable, 8-bit AWLEN)
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_protocol_converter:2.1 axi_pc_gp1
set_property -dict [list \
    CONFIG.SI_PROTOCOL {AXI3} \
    CONFIG.MI_PROTOCOL {AXI4} \
] [get_bd_cells axi_pc_gp1]

# GP1 and its protocol converter share FCLK_CLK0
connect_bd_net [get_bd_pins ps7/FCLK_CLK0] [get_bd_pins ps7/M_AXI_GP1_ACLK]
connect_bd_net [get_bd_pins ps7/FCLK_CLK0] [get_bd_pins axi_pc_gp1/aclk]
connect_bd_net [get_bd_pins rst_ps7/peripheral_aresetn] [get_bd_pins axi_pc_gp1/aresetn]

# GP1 -> axi_pc_gp1 -> exported M_AXI_BURST (burst-capable AXI4, 32-bit data, base 0x8000_0000)
connect_bd_intf_net [get_bd_intf_pins ps7/M_AXI_GP1] [get_bd_intf_pins axi_pc_gp1/S_AXI]
make_bd_intf_pins_external [get_bd_intf_pins axi_pc_gp1/M_AXI]
set_property name M_AXI_BURST [get_bd_intf_ports {M_AXI_0}]

# --- Address Space ---
# Assign the two exported AXI slave segments to their hardware addresses so
# BD validation does not error out.  These must match the software driver base
# addresses used by the PS7 masters.
#   GP0 -> M_AXI_LITE  at 0x43C0_0000 (control + IBRAM, 64 KiB)
#     GP0 aperture: 0x4000_0000 - 0x7FFF_FFFF
#   GP1 -> M_AXI_BURST at 0x8000_0000 (DBRAM bulk load, 64 KiB)
#     GP1 aperture: 0x8000_0000 - 0xBFFF_FFFF
assign_bd_address \
    -target_address_space /ps7/Data \
    [get_bd_addr_segs {M_AXI_LITE/Reg}] \
    -range 64K -offset 0x43C00000
assign_bd_address \
    -target_address_space /ps7/Data \
    [get_bd_addr_segs {M_AXI_BURST/Reg}] \
    -range 64K -offset 0x80000000

# Associate the exported AXI interface ports with the exported clock so that
# BD validation can verify clock/data coherency.
set_property CONFIG.ASSOCIATED_BUSIF {M_AXI_LITE:M_AXI_BURST} [get_bd_ports FCLK_CLK0]

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
puts "  PS7 FCLK_CLK0:     ${clock_freq_mhz} MHz"
puts "  GP0 slave base:    0x43C00000  (control + IBRAM, AXI4-Lite)"
puts "  GP1 burst base:    0x80000000  (DBRAM bulk load, AXI4 burst)"
puts "  BD Wrapper:        zynq_ps_wrapper"
puts "  Exported ports:    FCLK_CLK0, peripheral_aresetn, M_AXI_LITE_*, M_AXI_BURST_*"
puts "  Top-level wrapper: zynq_accel_top (connects BD + accel_axi + accel_axi_burst)"
puts "=========================================="
