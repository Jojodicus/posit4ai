## Timing Constraints for PAU FPU Harness AXI
## Target: Xilinx Zedboard (Zynq-7000 xc7z020clg484-1)

## Primary Clock Constraint
## Default: 100 MHz (10ns period) - matches Zedboard board clock
## This will be updated dynamically by run_impl.tcl based on CLOCK_FREQ_MHZ
create_clock -period 100.0 -name clk_i -waveform {0.000 5.000} [get_ports clk_i]

## Clock Uncertainty
## Account for jitter and other clock network variations
set_clock_uncertainty 0.200 [get_clocks clk_i]

## Input Delay Constraints
## Assume external signals arrive with 2ns setup time relative to clock
set_input_delay -clock [get_clocks clk_i] -max 2.000 [get_ports -filter {NAME !~ clk_i && DIRECTION == IN}]
set_input_delay -clock [get_clocks clk_i] -min 1.000 [get_ports -filter {NAME !~ clk_i && DIRECTION == IN}]

## Output Delay Constraints
## Assume external devices require 2ns setup time, 1ns hold time
set_output_delay -clock [get_clocks clk_i] -max 2.000 [get_ports -filter {DIRECTION == OUT}]
set_output_delay -clock [get_clocks clk_i] -min 1.000 [get_ports -filter {DIRECTION == OUT}]

## False Paths
## Reset signal is asynchronous - no timing constraints
set_false_path -from [get_ports rst_ni]

## I/O Standards for Zedboard
## Default to LVCMOS33 for general I/O on Zedboard
set_property IOSTANDARD LVCMOS33 [get_ports *]

## Drive Strength
set_property DRIVE 8 [get_ports -filter {DIRECTION == OUT}]
set_property SLEW FAST [get_ports -filter {DIRECTION == OUT}]

