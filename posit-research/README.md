# PAU vs FPU (PERCIVAL)

This allows for standalone synthesis and timing analysis of the Posit Arithmetic Unit (PAU) and the Floating Point Unit (FPU) from the PERCIVAL core, targeting the Xilinx Zedboard (Zynq-7000).

## Quick Start

The project includes convenient shell scripts for streamlined development:

```bash
# 1. Quick synthesis and verification (default: 100 MHz)
./build.sh

# 2. Run all testbenches
./test.sh

# 3. Full FPGA implementation with bitstream generation
./impl.sh

# 4. Open Vivado GUI for inspection
./open.sh

# 5. Clean all build artifacts
./clean.sh
```

### Custom Clock Frequencies

Both build and implementation scripts accept an optional clock frequency argument:

```bash
# Build at 150 MHz
./build.sh 150

# Full implementation at 125 MHz
./impl.sh 125
```

## Workflow Scripts

### build.sh - Quick Synthesis
Fast synthesis-only flow for development iteration. Uses the simpler `pau_fpu_harness` top-level (no AXI overhead).

**Usage:** `./build.sh [FREQ_MHZ]`

**Output:**
- `reports/build_timing.rpt` - Post-synthesis timing estimates
- `reports/build_utilization.rpt` - Resource usage

**When to use:** During development to quickly check if changes synthesize and get rough timing estimates.

### impl.sh - Full Implementation
Complete FPGA implementation flow: synthesis → place & route → bitstream generation. Uses the `pau_fpu_harness_axi` top-level with register-based AXI interface.

**Usage:** `./impl.sh [FREQ_MHZ]`

**Output:**
- `vivado_proj/posit_research.runs/impl_1/pau_fpu_harness_axi.bit` - FPGA bitstream
- `reports/timing_summary.rpt` - Final timing analysis
- `reports/timing_detailed.rpt` - Detailed path analysis
- `reports/utilization.rpt` - Resource usage
- `reports/utilization_hierarchical.rpt` - Hierarchical breakdown
- `reports/power.rpt` - Power analysis
- `reports/clock_networks.rpt` - Clock tree analysis

**When to use:** Before deployment, or when you need accurate timing closure results.

### test.sh - Run All Testbenches
Executes all three simulation filesets automatically.

**Usage:** `./test.sh`

**Simulations run:**
- `sim_harness` - Tests `pau_fpu_harness` (simple wrapper)
- `sim_axi` - Tests `pau_fpu_harness_axi` (AXI interface)
- `sim_pau` - Tests `pau_top` directly

**When to use:** After RTL changes to verify functionality across all test scenarios.

### open.sh - Open Vivado GUI
Opens the Vivado GUI with the project loaded. Creates the project if it doesn't exist.

**Usage:** `./open.sh`

**When to use:**
- Inspect synthesis/implementation results
- Analyze critical paths
- Debug timing violations
- View schematic/hierarchy

### clean.sh - Clean Build Artifacts
Removes all generated files and returns to a clean slate.

**Usage:** `./clean.sh`

**What it removes:**
- `vivado_proj/` - Project directory
- `reports/` - Generated reports
- Log files (`.log`, `.jou`, `.pb`, `.str`)
- IP generation artifacts (`.Xil/`)

## Structure
- `rtl/`: Symlinks to original PERCIVAL sources.
- `harness/`: Minimal SystemVerilog packages and the top-level benchmark wrapper.
- `scripts/`: TCL scripts for Vivado automation and Fmax discovery.
- `constraints/`: Timing constraint files (XDC).
- `reports/`: Generated synthesis and implementation reports (auto-created).

## Configuration
To change the architecture (e.g., 32-bit vs 64-bit, Approximate vs Exact), modify the `VERILOG_DEFINE` section in `scripts/project_setup.tcl`.

Available Macros:
- `POSLEN_64`: Sets Posit width to 64-bit (default is 32-bit).
- `QUIRE_DISABLED`: Disables Quire support.
- `POS_LOG_MULT`: Uses Approximate Posit Multiplier.
- `POS_LOG_DIV`: Uses Approximate Posit Divider.
- `POS_LOG_SQRT`: Uses Approximate Posit Square Root.

## Running the Investigation

### Recommended Workflow (Shell Scripts)

The easiest way to work with the project is using the provided shell scripts:

```bash
# 1. Start fresh
./clean.sh

# 2. Quick verification build
./build.sh 100

# 3. Run testbenches
./test.sh

# 4. Full implementation for deployment
./impl.sh 100

# 5. Inspect results in GUI
./open.sh
```

### Advanced: Manual Vivado Invocation

If you prefer manual control or need to use specific TCL scripts directly:

**Create Project:**
```bash
/tools/Xilinx/2025.2/Vivado/bin/vivado -mode batch -source scripts/project_setup.tcl
```

**Open GUI:**
```bash
/tools/Xilinx/2025.2/Vivado/bin/vivado vivado_proj/posit_research.xpr
```

**Find Maximum Frequency:**
The binary search script will tighten the clock constraint over 4 iterations to find the highest reachable frequency.
```bash
/tools/Xilinx/2025.2/Vivado/bin/vivado -mode batch -source scripts/find_fmax.tcl
```

**Legacy Synthesis Test:**
```bash
/tools/Xilinx/2025.2/Vivado/bin/vivado -mode batch -source scripts/test_synth.tcl
```

**Manual Simulation:**
```bash
/tools/Xilinx/2025.2/Vivado/bin/vivado -mode batch -source scripts/run_sim.tcl
```

## Clock Frequency Configuration

The build and implementation scripts accept a clock frequency argument (in MHz):

```bash
# Default: 100 MHz (matches Zedboard board clock)
./build.sh
./impl.sh

# Custom frequency: 150 MHz
./build.sh 150
./impl.sh 150
```

The scripts automatically:
1. Update the clocking wizard IP configuration
2. Modify the timing constraint file (`constraints/pau_axi_timing.xdc`)
3. Run synthesis/implementation with the new frequency target

**Note:** Higher frequencies may not meet timing. Check `reports/timing_summary.rpt` for WNS (Worst Negative Slack).

## Output Locations

### Synthesis Reports (./build.sh)
- `reports/build_timing.rpt` - Post-synthesis timing estimates
- `reports/build_utilization.rpt` - Resource usage

### Implementation Reports (./impl.sh)
- `reports/timing_summary.rpt` - **Most important**: Final timing results, WNS/WHS
- `reports/timing_detailed.rpt` - Top 10 critical paths with detailed breakdown
- `reports/utilization.rpt` - LUT, FF, DSP, BRAM usage
- `reports/utilization_hierarchical.rpt` - Per-module resource breakdown
- `reports/power.rpt` - Estimated power consumption
- `reports/clock_networks.rpt` - Clock tree analysis

### Bitstream (./impl.sh)
- `vivado_proj/posit_research.runs/impl_1/pau_fpu_harness_axi.bit`

## Metrics to Examine
1. **Timing Summary:** Check the `Worst Negative Slack (WNS)` and the `Data Path Delay` of the longest path in the PAU vs FPU.
   - Open: `reports/timing_summary.rpt`
   - **WNS ≥ 0**: Timing met ✓
   - **WNS < 0**: Timing violation - reduce clock frequency or optimize
2. **Utilization Report:** Compare LUT, DSP, and Flip-Flop counts.
   - Open: `reports/utilization.rpt` or `reports/utilization_hierarchical.rpt`
3. **Critical Path:** Use the GUI to visualize which logic levels (shifters, adders) are dominant in the Posit pipeline.
   - Run: `./open.sh`
   - Navigate to: Implemented Design → Timing → Report Timing Summary
