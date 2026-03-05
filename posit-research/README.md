# PAU vs FPU Research Project (PERCIVAL)

This project allows for standalone synthesis and timing analysis of the Posit Arithmetic Unit (PAU) and the Floating Point Unit (FPU) from the PERCIVAL core, targeting the Xilinx Zedboard (Zynq-7000).

## Structure
- `rtl/`: Symlinks to original PERCIVAL sources.
- `harness/`: Minimal SystemVerilog packages and the top-level benchmark wrapper.
- `scripts/`: TCL scripts for Vivado automation and Fmax discovery.

## Configuration
To change the architecture (e.g., 32-bit vs 64-bit, Approximate vs Exact), modify the `VERILOG_DEFINE` section in `scripts/project_setup.tcl`.

Available Macros:
- `POSLEN_64`: Sets Posit width to 64-bit (default is 32-bit).
- `QUIRE_DISABLED`: Disables Quire support.
- `POS_LOG_MULT`: Uses Approximate Posit Multiplier.
- `POS_LOG_DIV`: Uses Approximate Posit Divider.
- `POS_LOG_SQRT`: Uses Approximate Posit Square Root.

## Running the Investigation

### Create Project

```bash
/tools/Xilinx/2025.2/Vivado/bin/vivado -mode batch -source scripts/project_setup.tcl
```

### Manual Investigation
To open the project in the Vivado GUI for critical path analysis:

```bash
/tools/Xilinx/2025.2/Vivado/bin/vivado vivado_proj/posit_research.xpr
```

### Find Maximum Frequency (Fmax)
The binary search script will tighten the clock constraint over 4 iterations to find the highest reachable frequency.

```bash
/tools/Xilinx/2025.2/Vivado/bin/vivado -mode batch -source scripts/find_fmax.tcl
```

## Metrics to Examine
1. **Timing Summary:** Check the `Worst Negative Slack (WNS)` and the `Data Path Delay` of the longest path in the PAU vs FPU.
2. **Utilization Report:** Compare LUT, DSP, and Flip-Flop counts.
3. **Critical Path:** Use the GUI to visualize which logic levels (shifters, adders) are dominant in the Posit pipeline.
