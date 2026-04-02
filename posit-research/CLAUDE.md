# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

PERCIVAL research project comparing Posit Arithmetic Unit (PAU) vs Floating Point Unit (FPU) performance through standalone FPGA synthesis and timing analysis. Targets Xilinx Zedboard (Zynq-7000, part: xc7z020clg484-1) using Vivado 2025.2.

## Development Commands

### Quick Development Workflow
```bash
./clean.sh              # Clean all build artifacts
./build.sh [FREQ_MHZ]   # Fast synthesis-only (default: 100 MHz)
./test.sh               # Run simulation filesets (sim_core, sim_axi)
./impl.sh [FREQ_MHZ]    # Full implementation with bitstream generation
./open.sh               # Open Vivado GUI for inspection
```

### Vivado Environment
All shell scripts automatically source Vivado environment from `scripts/vivado_env.sh`. The Vivado installation path is `/tools/Xilinx/2025.2/Vivado/`.

### Build Outputs
- **Synthesis reports** (`./build.sh`): `reports/build_timing.rpt`, `reports/build_utilization.rpt`
- **Implementation reports** (`./impl.sh`): `reports/timing_summary.rpt`, `reports/timing_detailed.rpt`, `reports/utilization*.rpt`, `reports/power.rpt`, `reports/clock_networks.rpt`
- **Bitstream**: `vivado_proj/posit_research.runs/impl_1/zynq_accel_top.bit`

### Testing
Two simulation filesets run via `./test.sh`:
- `sim_core` - Tests `tb_accel_core.sv` (BRAM + sequencer + arith_unit)
- `sim_axi`  - Tests `tb_accel_axi.sv` (AXI register interface)

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
- `rtl/` - **Symlinks** to PERCIVAL upstream sources: `common_cells/`, `fpu/`, `pau/` (VHDL)
- `harness/` - Accelerator RTL
  - `config_pkg.sv` - **User-facing configuration** (edit this to change arithmetic unit, width, etc.)
  - `opcodes_pkg.sv` - Unified opcode set (same for PAU and FPU)
  - `arith_unit.sv` - Instantiates either `pau_top` or `fpu_wrap` based on `config_pkg::ACCEL_TYPE`
  - `accel_core.sv` - Instruction BRAM + data BRAM + sequencer + `arith_unit`
  - `accel_axi.sv` - AXI-Lite slave wrapping `accel_core`
  - `accel_harness.sv` - Synthesis-only top (no PS7) for `./build.sh`
  - `zynq_accel_top.sv` - Full implementation top (PS7 + `accel_axi`) for `./impl.sh`
  - `pau_top.sv`, `fpu_wrap.sv` - Local editable copies from PERCIVAL
  - `cva6_config_pkg.sv`, `riscv_pkg_mini.sv`, `ariane_pkg_mini.sv` - Internal packages (do not edit)
- `tb/` - Testbenches (`tb_accel_core.sv`, `tb_accel_axi.sv`)
- `scripts/` - TCL scripts for Vivado automation
- `constraints/` - Timing constraints (XDC files)

### Top-Level Architecture

**zynq_accel_top** (implementation top):
- Used by `./impl.sh` for full implementation and bitstream generation
- Instantiates `zynq_ps_wrapper` (PS7 block design) and `accel_axi`
- AXI slave at `0x43C00000`, runs at 100 MHz from PS7 FCLK_CLK0

**accel_harness** (quick build top):
- Used by `./build.sh` and `find_fmax.tcl` for synthesis-only timing/utilization checks
- Contains `clk_wiz_0` (100 MHz → target freq) and `accel_core`

### Accelerator Core
- **Instruction BRAM**: 64-bit × 256 words (dual-port: host write, sequencer fetch)
- **Data BRAM**: DATA_WIDTH × 4096 words (true dual-port: host r/w, sequencer r/w)
- **Sequencer**: 5-stage pipeline (FETCH→DECODE→EXEC→WAIT_ARITH→WRITEBACK)
- **arith_unit**: maps accelerator opcodes to PAU (`QMADD`, `PADD`, …) or FPU (`FMADD`, `FADD`, …)

### Instruction Format (64-bit)
```
[63:60] opcode (4-bit)  [59:40] addr_a (20-bit)  [39:20] addr_b (20-bit)  [19:0] addr_result (20-bit)
```
16 opcodes, up to 1M data addresses (DATA_DEPTH configurable, max 2^20).

### Package Dependencies (compile order)
1. `config_pkg.sv` - user configuration
2. `opcodes_pkg.sv` - accelerator opcodes
3. `cva6_config_pkg.sv`, `riscv_pkg_mini.sv` - needed by pau_top/fpu_wrap
4. `ariane_pkg_mini.sv` - PAU/FPU internal types (imports config_pkg)
5. `cf_math_pkg.sv`, `fpnew_pkg.sv` - FPU support

## Configuration

### Arithmetic Unit and Width
Edit **only** `harness/config_pkg.sv`:
```sv
parameter string ACCEL_TYPE  = "PAU";   // "PAU" or "FPU"
parameter int    DATA_WIDTH  = 32;      // 32 or 64
parameter bit    QUIRE_ENABLE = 1;      // exact quire accumulator (PAU only)
parameter bit    APPROX_MUL  = 0;      // log-domain approximate ops (PAU only)
parameter bit    APPROX_DIV  = 0;
parameter bit    APPROX_SQRT = 0;
```

Note: posit es=2 and quire width (16 x DATA_WIDTH) are fixed in the pre-generated VHDL. Changing these requires regenerating PAU cores via FloPoCo.

After changing `config_pkg.sv`, run `./clean.sh` then rebuild.

### Clock Frequency
```bash
./build.sh 150   # Synthesise accel_harness at 150 MHz (updates clk_wiz_0)
./impl.sh        # Implement zynq_accel_top at 100 MHz (PS7 FCLK_CLK0)
```

## Timing Analysis

Check `reports/timing_summary.rpt` after implementation:
- **WNS ≥ 0**: Timing met ✓
- **WNS < 0**: Timing violation — reduce clock frequency or optimise RTL

For Fmax measurement: `./build.sh [FREQ]` or `find_fmax.tcl` (synthesis only, fast).

## Common Development Patterns

### Typical Development Cycle
1. Edit `harness/config_pkg.sv` to select PAU/FPU, width, options
2. `./clean.sh`
3. `./test.sh` (functional simulation)
4. `./build.sh [FREQ]` (quick synthesis + timing)
5. `./impl.sh` (full implementation + bitstream)
6. `./open.sh` (inspect timing/utilization in GUI)

### Adding New RTL Files
Edit `scripts/project_setup.tcl`:
- Add source files with `add_files -norecurse <path>`
- Set `.sv` files as SystemVerilog: `set_property file_type SystemVerilog [get_files <file>]`
- Update compile order: `update_compile_order -fileset sources_1`

### Language Mixing
- PAU core: VHDL (in `rtl/pau/*.vhd`)
- FPU, common cells, harnesses: SystemVerilog
- Vivado handles mixed-language simulation and synthesis automatically

## Notes
- Project name: `posit_research`
- Project directory: `vivado_proj/`
- AXI slave mapped at `0x43C00000` on PS7 M_AXI_GP0 (100 MHz FCLK_CLK0)
- `rtl/` contains **symlinks** to PERCIVAL upstream (`../PERCIVAL/`); do not edit in-place
- `harness/pau_top.sv` and `harness/fpu_wrap.sv` are local editable copies from PERCIVAL
- Block design (`zynq_ps`) created by `scripts/create_bd.tcl`, sourced from `project_setup.tcl`
- Comparison matrix: PAU-32 vs FPU-32, PAU-32(approx) vs PAU-32(exact), PAU-64 vs PAU-32
