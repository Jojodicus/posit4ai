# find_fmax.tcl - Fmax binary search via full implementation runs
#
# Algorithm:
#   1. Try 100 MHz.
#   2. From the post-impl WNS compute a candidate frequency:
#        F_new = floor(1000 / (T - WNS))   where T = 1000/F_current
#      Positive WNS -> new period is tighter -> higher frequency.
#      Negative WNS -> new period is looser  -> lower frequency.
#   3. If the run passed, keep climbing (up to MAX_CLIMB consecutive
#      successes without a failure).  When a failure occurs, clamp the
#      candidate inside the [best_good+1, best_bad-1] window and continue.
#   4. Stop when best_bad - best_good <= 1 (converged) or MAX_ITER
#      total runs are exhausted.
#   5. If no passing frequency was ever found, report failure.
#
# Results are written to reports/fmax_search.log.

set proj_name "posit_research"
set proj_dir  "./vivado_proj"
set root_dir  [file normalize [file join [file dirname [info script]] ..]]

set MAX_ITER  20
set MAX_CLIMB  4

# --------------------------------------------------------------------------
proc calc_next_freq {freq_mhz wns_ns} {
    # New achievable period = current period minus WNS.
    set T_ns     [expr {1000.0 / $freq_mhz}]
    set new_T_ns [expr {$T_ns - $wns_ns}]
    if {$new_T_ns <= 0} { return -1 }
    # Floor to integer MHz so we never claim a fractional target.
    return [expr {int(floor(1000.0 / $new_T_ns))}]
}

# Run synthesis + implementation at freq_mhz.
# Returns WNS (ns) on success, or exits the script on a tool error.
proc run_impl_at {freq_mhz root_dir} {
    set bram_freq [expr {$freq_mhz * 2}]

    puts "\n------------------------------------------"
    puts "Impl run at ${freq_mhz} MHz"
    puts "------------------------------------------"

    set_property -dict [list \
        CONFIG.PRIM_IN_FREQ              {100.000} \
        CONFIG.CLKOUT1_REQUESTED_OUT_FREQ "$freq_mhz" \
        CONFIG.CLKOUT2_USED              {true} \
        CONFIG.CLKOUT2_REQUESTED_OUT_FREQ "$bram_freq" \
    ] [get_ips clk_wiz_0]
    generate_target all [get_ips clk_wiz_0]

    update_compile_order -fileset sources_1

    # Force clk_wiz_0 to re-synthesize; without this Vivado reuses the stale
    # 100 MHz DCP and STA always reports the same WNS regardless of frequency.
    reset_run clk_wiz_0_synth_1
    launch_runs clk_wiz_0_synth_1 -jobs 8
    wait_on_run clk_wiz_0_synth_1

    reset_run synth_1
    launch_runs synth_1 -jobs 8
    wait_on_run synth_1

    if {[get_property PROGRESS [get_runs synth_1]] != "100%"} {
        puts "ERROR: Synthesis failed at ${freq_mhz} MHz."
        puts "Check the synthesis log and investigate manually."
        exit 1
    }

    reset_run impl_1
    launch_runs impl_1 -jobs 8
    wait_on_run impl_1

    if {[get_property PROGRESS [get_runs impl_1]] != "100%"} {
        puts "ERROR: Implementation failed at ${freq_mhz} MHz."
        puts "Check the implementation log and investigate manually."
        exit 1
    }

    open_run impl_1
    set wns [get_property SLACK [get_timing_paths]]
    set whs [get_property SLACK [get_timing_paths -hold]]

    if {$wns >= 0} {
        puts "  PASS  WNS=${wns} ns  WHS=${whs} ns"
    } else {
        puts "  FAIL  WNS=${wns} ns  WHS=${whs} ns"
    }
    return $wns
}

# --------------------------------------------------------------------------
# Open or create project
catch {close_project -quiet}

if {[file exists ${proj_dir}/${proj_name}.xpr]} {
    open_project ${proj_dir}/${proj_name}.xpr
} else {
    puts "Project not found -- creating..."
    source -notrace [file join $root_dir scripts project_setup.tcl]
}

set_property top zynq_accel_top [current_fileset]

# Rebuild BD if needed (same guard as run_impl.tcl)
if {[get_files -quiet "zynq_ps.bd"] eq ""} {
    source -notrace [file join $root_dir scripts create_bd.tcl]
    set_property top zynq_accel_top [current_fileset]
}

file mkdir [file normalize $root_dir/reports]
set log_fh [open [file normalize $root_dir/reports/fmax_search.log] w]

proc log {msg} {
    global log_fh
    puts $msg
    puts $log_fh $msg
}

puts $log_fh "find_fmax run -- [clock format [clock seconds]]"
puts $log_fh ""

puts "\n=========================================="
puts "Fmax Search (impl-based)"
puts "=========================================="

# --------------------------------------------------------------------------
set best_good -1  ;# highest passing MHz, -1 = none yet
set best_bad  -1  ;# lowest failing MHz,  -1 = none yet
set current   100
set climb_count 0 ;# consecutive passes without an intervening failure

for {set iter 0} {$iter < $MAX_ITER} {incr iter} {

    # --- clamp inside known bounds ---
    if {$best_good >= 0 && $current <= $best_good} {
        set current [expr {$best_good + 1}]
    }
    if {$best_bad >= 0 && $current >= $best_bad} {
        set current [expr {$best_bad - 1}]
    }

    # --- convergence: gap is 1 MHz, nothing left to try ---
    if {$best_good >= 0 && $best_bad >= 0 && $best_bad - $best_good <= 1} {
        log "Converged: best_good=${best_good} MHz  best_bad=${best_bad} MHz"
        break
    }

    # --- run ---
    set wns [run_impl_at $current $root_dir]
    log [format "  iter=%2d  freq=%d MHz  WNS=%.3f ns" $iter $current $wns]

    if {$wns >= 0} {
        # Pass
        set best_good $current
        incr climb_count
        if {$climb_count >= $MAX_CLIMB} {
            log "Stopped climbing after $MAX_CLIMB consecutive passes."
            break
        }
        set next [calc_next_freq $current $wns]
        if {$next <= $current} { set next [expr {$current + 1}] }
        set current $next
    } else {
        # Fail
        set best_bad $current
        set climb_count 0
        set next [calc_next_freq $current $wns]
        if {$next >= $current || $next <= 0} { set next [expr {$current - 1}] }
        if {$next <= 0} {
            log "Candidate frequency dropped to zero -- cannot go lower."
            break
        }
        set current $next
    }
}

close $log_fh

# --------------------------------------------------------------------------
puts "\n=========================================="
puts "Fmax Search Results"
puts "=========================================="

if {$best_good < 0} {
    puts "No passing frequency found."
    puts "Even 100 MHz failed. Investigate the design manually."
    puts "  Detailed log: reports/fmax_search.log"
    exit 1
} else {
    puts "Fmax (impl) = ${best_good} MHz"
    if {$best_bad >= 0} {
        puts "First failing freq = ${best_bad} MHz"
    }
    puts "Detailed log: reports/fmax_search.log"
}
puts "=========================================="
