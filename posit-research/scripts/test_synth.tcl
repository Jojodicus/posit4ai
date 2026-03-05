
source ./scripts/project_setup.tcl

# Run Elaboration Check
puts "RUNNING ELABORATION CHECK..."
# We need to synthesize the IP first so elaboration finds the stub
synth_ip [get_ips clk_wiz_0]
synth_design -rtl -top pau_fpu_harness

# Run Synthesis at 10MHz
puts "RUNNING SYNTHESIS..."
set freq 10
set_property -dict [list CONFIG.CLKOUT1_REQUESTED_OUT_FREQ $freq] [get_ips clk_wiz_0]
generate_target all [get_ips clk_wiz_0]

reset_run synth_1
launch_runs synth_1 -jobs 4
wait_on_run synth_1

if {[get_property PROGRESS [get_runs synth_1]] != "100%"} {
    puts "SYNTHESIS FAILED"
    exit 1
}

open_run synth_1
set wns [get_property SLACK [get_timing_paths -max_paths 1 -setup]]
puts "SYNTHESIS SUCCESSFUL. WNS: $wns"
close_design
