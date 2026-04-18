# CLAUDE.md

Guidance for Claude Code when working in this repository.

## Project Overview

Standalone FPGA accelerator comparing PERCIVAL's Posit Arithmetic Unit (PAU) against an IEEE 754 FPU on the same opcode set. Target: Zedboard (Zynq-7000, `xc7z020clg484-1`), Vivado 2025.2 at `/tools/Xilinx/2025.2/Vivado/`.

See `README.md` for the end-user walkthrough; this file focuses on nuances that aren't obvious from the code.

## Development Loop

```bash
./clean.sh              # wipe vivado_proj/ and reports/
./test.sh               # run all 21 sim filesets via run_all_tests.tcl
./build.sh [FREQ_MHZ]   # synthesis-only on accel_harness (default 100 MHz)
./impl.sh  [FREQ_MHZ]   # full P&R + bitstream on zynq_accel_top (default 100 MHz)
./open.sh               # open the project in the Vivado GUI
```

All shell scripts source `scripts/vivado_env.sh` automatically.

Manual invocations when the wrappers aren't enough:
```bash
/tools/Xilinx/2025.2/Vivado/bin/vivado -mode batch -source scripts/project_setup.tcl
/tools/Xilinx/2025.2/Vivado/bin/vivado vivado_proj/posit_research.xpr
/tools/Xilinx/2025.2/Vivado/bin/vivado -mode batch -source scripts/find_fmax.tcl
```

### Testing

`scripts/run_all_tests.tcl` launches 21 filesets; each compiles `tb_accel_core.sv` (18 filesets) or `tb_accel_axi.sv` (3 filesets) against a `tb/configs/config_pkg_*.sv` override. Fail markers scanned in each sim log: `FAIL:`, `TIMEOUT:`, `FATAL`, `Assertion failed`, `$fatal`, `ASSERT`. Logs: `vivado_proj/posit_research.sim/<fileset>/behav/xsim/simulate.log`.

The filesets are registered twice - once in `scripts/project_setup.tcl` (the `accel_core_simsets` / `axi_simsets` lists and the `{simset cfg_file}` mapping) and once in `scripts/run_all_tests.tcl`. Both must be updated when adding a config.

### Build vs Impl

- `./build.sh` -> `scripts/run_build.tcl`, top is `accel_harness` (no PS7, `clk_wiz_0` set from `CLOCK_FREQ_MHZ`). Fast - synthesis only. Use for quick utilization / timing feedback.
- `./impl.sh` -> `scripts/run_impl.tcl`, top is `zynq_accel_top` (PS7 block design, AXI-Lite + AXI4 burst). Full P&R and bitstream. `CLOCK_FREQ_MHZ` plumbs through to PS7 `FCLK_CLK0`.

## Architecture

### Layout
- `harness/config_pkg.sv` is the **only** user-facing configuration file (see below).
- `harness/` RTL is grouped into subfolders: `pkg/` (packages), `arith/` (PAU/FPU/FloPoCo back-ends + MAC wrappers), `core/` (`accel_core`), `axi/` (register + burst slaves + arbiter), `top/` (`accel_harness`, `zynq_accel_top`), `patches/common_cells/` (XSim-compatible `.svh` overrides for the upstream `include "common_cells/..."` paths).
- `harness/arith/positmac{8,16,32}.vhd` are FloPoCo MAC wrappers compiled into per-width libraries (`flo_mac8/16/32`) to sidestep duplicate entity names across widths.
- `rtl/` - **symlinks** into `../PERCIVAL/` (`pau/`, `fpu/`, `common_cells/`, `Flo-Posit/`). Do not edit in-place; local editable copies of `pau_top.sv` / `fpu_wrap.sv` are in `harness/arith/`.
- `tb/` - testbenches plus per-fileset config overrides in `tb/configs/`.
- `scripts/` - Vivado TCL automation. `constraints/` - timing XDC.

### Top Modules

- **`zynq_accel_top`** (impl top, `./impl.sh`) - PS7 via `zynq_ps_wrapper` + `accel_axi` (AXI-Lite register slave, `0x43C00000`) + `accel_axi_burst` (AXI4 burst slave on PS7 GP1) + `accel_dbram_arb` + `accel_core`. Currently clocks `accel_core.clk_bram_i` from `FCLK_CLK0` (1x, not 2x) - the 2x DBRAM-multipump path is wired but unused at impl; see the TODO inline.
- **`accel_harness`** (build top, `./build.sh`, `find_fmax.tcl`) - `clk_wiz_0` (100 MHz -> `CLOCK_FREQ_MHZ` primary, 2x secondary for `clk_bram`) + `accel_core`. No PS7, no AXI, no burst path.

### Core Internals

- Instruction BRAM: 64-bit x INSTR_DEPTH (default 2**15 = 32K words), true dual-port.
- Data BRAM: DATA_WIDTH x DATA_DEPTH (default 2**15 = 32K words), true dual-port, clocked at clk_bram_i (intended 2x clk_i; alpha-blending / XAPP706 pattern).
- Sequencer: 3-stage pipeline (IF / ID / EX) running in parallel inside RUNNING_S. FSM states: IDLE_S -> RUNNING_S -> HALT_S. Stalls on RAW hazards and arith-busy.
- `arith_unit` dispatches to `pau_top`, `flo_posit_top`, or `fpu_wrap` based on `ACCEL_TYPE` and `DATA_WIDTH`.

### Instruction Format (64-bit)

```
[63:60] opcode  [59:40] addr_a  [39:20] addr_b  [19:0] addr_result
```

16 opcodes in `opcodes_pkg.sv`; up to 2**20 data addresses (DATA_DEPTH is the actual cap and is configurable up to `2**20`).

### Package Compile Order
`config_pkg` -> `opcodes_pkg` -> `cva6_config_pkg` -> `riscv_pkg_mini` -> `ariane_pkg_mini` -> `cf_math_pkg` -> `fpnew_pkg`. Handled by `project_setup.tcl` via `reorder_files -front`; per-sim filesets additionally front their own `config_pkg_*.sv` override.

## Configuration

Edit **only** `harness/config_pkg.sv`. Full option table with per-`ACCEL_TYPE` support matrix lives in the file itself - prefer reading it over paraphrasing.

Key routing rules that are easy to miss:
- `ACCEL_TYPE = "PAU"` with `DATA_WIDTH` 8 or 16 automatically uses FloPoCo cores (PERCIVAL does not supply those widths). Use "FLO_PAU" to force FloPoCo for 32-bit too.
- `ACCEL_TYPE = "FPU"` ignores QUIRE_MODE = "QUIRE" - treated as "ACCUMULATOR".
- `ACCEL_TYPE = "FLO_PAU"` has no SQRT core; `SQRT_MODE = "EXACT"` returns NaR.
- `MUL_MODE = "APPROX"` requires PAU or FLO_PAU; FPU ignores it.
- `DIV_MODE = "APPROX"` / `SQRT_MODE = "APPROX"` are PAU-32/64 only.

After editing, `./clean.sh` then rebuild.

Posit `es = 2` and quire width `16 x DATA_WIDTH` are fixed in the pre-generated VHDL - regenerating via FloPoCo is the only way to change them.

## Timing

`reports/timing_summary.rpt` after `./impl.sh`:
- **WNS >= 0**: timing met.
- **WNS < 0**: lower the target frequency or tighten RTL.

For a quick Fmax estimate, run `./build.sh [FREQ]` or `scripts/find_fmax.tcl` - both synthesis-only on `accel_harness`.

## Adding RTL

Edit `scripts/project_setup.tcl`:
- `add_files -norecurse <path>`
- Set `.sv` files explicitly: `set_property file_type SystemVerilog [get_files <file>]`
- `update_compile_order -fileset sources_1`
- For a new simulation variant, register the fileset in both the `accel_core_simsets` / `axi_simsets` list and the `{simset cfg_file}` mapping (plus the same list in `run_all_tests.tcl`).

## Notes

- Project name / directory: `posit_research` / `vivado_proj/`.
- AXI-Lite slave at `0x43C00000`; AXI4 burst slave on PS7 GP1.
- PAU core is VHDL (in `rtl/pau/`, `rtl/Flo-Posit/`); FPU, common cells, harness are SystemVerilog. Vivado handles the mixed-language elaboration.
- Block design `zynq_ps` is (re)created by `scripts/create_bd.tcl`, sourced from `project_setup.tcl`.
- Comparison matrix: PAU-32 vs FPU-32, PAU-32 exact vs approx, PAU-64 vs PAU-32, FLO_PAU 8/16/32 vs PAU where applicable.
