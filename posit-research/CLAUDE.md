# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

PERCIVAL research project comparing Posit Arithmetic Unit (PAU) vs Floating Point Unit (FPU) performance through standalone FPGA synthesis and timing analysis. Targets Xilinx Zedboard (Zynq-7000, part: xc7z020clg484-1) using Vivado 2025.2.

## Development Commands

### Quick Development Workflow
```bash
./clean.sh              # Clean all build artifacts
./build.sh [FREQ_MHZ]   # Fast synthesis-only (default: 100 MHz)
./test.sh               # Run all three simulation filesets
./impl.sh [FREQ_MHZ]    # Full implementation with bitstream generation
./open.sh               # Open Vivado GUI for inspection
```

### Vivado Environment
All shell scripts automatically source Vivado environment from `scripts/vivado_env.sh`. The Vivado installation path is `/tools/Xilinx/2025.2/Vivado/`.

### Build Outputs
- **Synthesis reports** (`./build.sh`): `reports/build_timing.rpt`, `reports/build_utilization.rpt`
- **Implementation reports** (`./impl.sh`): `reports/timing_summary.rpt`, `reports/timing_detailed.rpt`, `reports/utilization*.rpt`, `reports/power.rpt`, `reports/clock_networks.rpt`
- **Bitstream**: `vivado_proj/posit_research.runs/impl_1/pau_fpu_harness_axi.bit`

### Testing
Three simulation filesets run via `./test.sh`:
- `sim_harness` - Tests `tb_pau_fpu_harness.sv` (simple wrapper)
- `sim_axi` - Tests `tb_pau_fpu_harness_axi.sv` (AXI interface)
- `sim_pau` - Tests `tb_pau_top.sv` (PAU core directly)

### Manual Vivado Invocation
If shell scripts are insufficient:
```bash
# Create/setup project
/tools/Xilinx/2025.2/Vivado/bin/vivado -mode batch -source scripts/project_setup.tcl

# Open GUI
/tools/Xilinx/2025.2/Vivado/bin/vivado vivado_proj/posit_research.xpr

# Find maximum frequency (binary search over 4 iterations)
/tools/Xilinx/2025.2/Vivado/bin/vivado -mode batch -source scripts/find_fmax.tcl
```

## Architecture

### Project Structure
- `rtl/` - Symlinks to PERCIVAL sources: `common_cells/`, `fpu/` (SystemVerilog), `pau/` (VHDL)
- `harness/` - Minimal SystemVerilog packages and top-level wrappers
  - `cva6_config_pkg.sv`, `riscv_pkg_mini.sv`, `ariane_pkg_mini.sv` - Configuration packages
  - `pau_fpu_harness.sv` - Simple top-level for quick synthesis (no AXI)
  - `pau_fpu_harness_axi.sv` - AXI-Lite register interface for FPGA deployment
- `tb/` - Testbenches for all three simulation targets
- `scripts/` - TCL scripts for Vivado automation
- `constraints/` - Timing constraints (XDC files)

### Two Top-Level Modules

**pau_fpu_harness** (simple):
- Used by `./build.sh` for fast iteration during development
- Direct signal interface (no AXI overhead)
- Input registers, clocking wizard, instantiates `pau_top` and `fpu_wrap`

**pau_fpu_harness_axi** (register-based):
- Used by `./impl.sh` for full implementation and bitstream generation
- AXI-Lite slave interface with register map at addresses 0x00-0x1C
- Register map: operands (OP_A, OP_B), operation selectors (OP_SEL, FU_SEL), results (RESULT, VALID_O, READY_O)

### Core Components
Both harnesses instantiate:
- `clk_wiz_0` - Xilinx Clocking Wizard IP (100 MHz input → configurable output)
- `pau_top` - Posit Arithmetic Unit (from PERCIVAL/core/pau_top.sv)
- `fpu_wrap` - Floating Point Unit wrapper (from PERCIVAL/core/fpu_wrap.sv)

### Package Dependencies
Packages must be included in order (handled by `project_setup.tcl`):
1. `cva6_config_pkg.sv` - CVA6 core configuration
2. `riscv_pkg_mini.sv` - RISC-V types and constants
3. `ariane_pkg_mini.sv` - Ariane/CVA6 types (defines `fu_op`, `fu_t`, `fu_data_t`)
4. `cf_math_pkg.sv` - Common cells math utilities
5. `fpnew_pkg.sv` - FPU types and configurations

## Configuration

### Posit Width and Operation Modes
Edit `VERILOG_DEFINE` section in `scripts/project_setup.tcl`:
- `POSLEN_64` - Use 64-bit posits (default: 32-bit)
- `QUIRE_DISABLED` - Disable quire accumulator support
- `POS_LOG_MULT` - Use approximate posit multiplier
- `POS_LOG_DIV` - Use approximate posit divider
- `POS_LOG_SQRT` - Use approximate posit square root

**Note**: After changing these macros, run `./clean.sh` before rebuilding.

### Clock Frequency
Pass frequency (MHz) as argument to build/implementation scripts:
```bash
./build.sh 150   # Build at 150 MHz
./impl.sh 125    # Implement at 125 MHz
```

Scripts automatically:
1. Update `clk_wiz_0` IP configuration
2. Modify `constraints/pau_axi_timing.xdc` with new period
3. Run synthesis/implementation with updated constraints

## Timing Analysis

Check `reports/timing_summary.rpt` after implementation:
- **WNS ≥ 0**: Timing met ✓
- **WNS < 0**: Timing violation - reduce clock frequency or optimize RTL

Critical path analysis typically shows dominant delays in posit shifters and adders. Use Vivado GUI (`./open.sh` → Implemented Design → Timing → Report Timing Summary) to visualize critical paths.

## Common Development Patterns

### Typical Development Cycle
1. Modify RTL in PERCIVAL repository (changes appear via symlinks in `rtl/`)
2. `./clean.sh` (if changing macros or significant structural changes)
3. `./test.sh` (verify functionality)
4. `./build.sh [FREQ]` (quick synthesis check)
5. `./impl.sh [FREQ]` (full implementation before deployment)
6. `./open.sh` (inspect timing/utilization in GUI)

### Adding New RTL Files
Edit `scripts/project_setup.tcl`:
- Add source files with `add_files -norecurse <path>`
- Set `.sv` files as SystemVerilog: `set_property file_type SystemVerilog [get_files <file>]`
- Mark packages as global includes: `set_property is_global_include 1 [get_files <pkg>]`
- Update compile order: `update_compile_order -fileset sources_1`

### Language Mixing
- PAU core: VHDL (in `rtl/pau/*.vhd`)
- FPU, common cells, harnesses: SystemVerilog
- Vivado handles mixed-language simulation and synthesis automatically

## Notes
- Project name: `posit_research`
- Project directory: `vivado_proj/`
- Zedboard provides 100 MHz board clock as input to clocking wizard
- The PERCIVAL repository is expected at `../PERCIVAL` relative to this directory
