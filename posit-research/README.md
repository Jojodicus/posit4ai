# PERCIVAL Posit vs Float Accelerator

Standalone FPGA accelerator for comparing Posit Arithmetic (PAU) vs IEEE 754 Floating Point (FPU) performance on the Xilinx Zedboard (Zynq-7000, `xc7z020clg484-1`). The same opcode set drives either unit, so timing, utilization, and power can be compared on equal footing.

## Prerequisites

- **Vivado 2025.2** at `/tools/Xilinx/2025.2/Vivado/`
- **PERCIVAL** repo cloned at `../PERCIVAL/` (sibling directory — `rtl/` is symlinks into it)

## Quick Start

```bash
vim harness/config_pkg.sv   # pick the arithmetic unit + width
./clean.sh                  # wipe previous build artifacts
./test.sh                   # run all functional simulations
./build.sh [FREQ_MHZ]       # synthesis-only (accel_harness; default 100 MHz)
./impl.sh  [FREQ_MHZ]       # full implementation + bitstream (zynq_accel_top; default 100 MHz)
./open.sh                   # open the project in the Vivado GUI
```

After changing `config_pkg.sv`, always `./clean.sh` before rebuilding.

## Configuration

All user-tunable parameters live in **`harness/config_pkg.sv`** — it is the only file you need to touch.

| Parameter     | Values                                     | Notes                                                      |
|---------------|--------------------------------------------|------------------------------------------------------------|
| `ACCEL_TYPE`  | `"PAU"` / `"FLO_PAU"` / `"FPU"`            | Posit (PERCIVAL), Posit (FloPoCo-only), or IEEE 754 FPU     |
| `DATA_WIDTH`  | `8` / `16` / `32` / `64`                   | `FLO_PAU`: 8/16/32 only. `FPU`: 32/64 only.                |
| `QUIRE_MODE`  | `"QUIRE"` / `"ACCUMULATOR"` / `"DISABLED"` | Exact quire, register accumulator, or all QACC_* → NaR/NaN |
| `MUL_MODE`    | `"EXACT"` / `"APPROX"`                     | Log-domain approx (PAU, FLO_PAU only)                      |
| `DIV_MODE`    | `"EXACT"` / `"APPROX"` / `"DISABLE"`       | APPROX only on PAU-32/64. DISABLE removes the divider.     |
| `SQRT_MODE`   | `"EXACT"` / `"APPROX"` / `"DISABLE"`       | APPROX only on PAU-32/64. FLO_PAU always returns NaR.      |
| `INSTR_DEPTH` | integer, max `2**20`                       | 64-bit instruction words (default `2**15` = 32K)           |
| `DATA_DEPTH`  | integer, max `2**20`                       | `DATA_WIDTH`-bit data words (default `2**15` = 32K)        |

`ACCEL_TYPE = "PAU"` with `DATA_WIDTH` 8 or 16 transparently dispatches to FloPoCo cores (PERCIVAL only supplies 32/64-bit). For all supported combinations and which features are honoured per type, see the "Feature support matrix" comment block in `config_pkg.sv`.

Posit `es=2` and the quire width (`16 × DATA_WIDTH`) are baked into the pre-generated VHDL cores. Changing either requires regenerating the PAU/FloPoCo VHDL.

## Architecture

```
zynq_accel_top            (impl top: PS7 + AXI)
├── zynq_ps_wrapper       (PS7 block design; 100 MHz FCLK_CLK0)
├── accel_axi             (AXI-Lite slave at 0x43C00000, register interface)
├── accel_axi_burst       (AXI4 burst slave, GP1, bulk DBRAM transfers)
├── accel_dbram_arb       (arbiter between the two AXI masters)
└── accel_core            (sequencer + BRAMs + arithmetic)
    ├── Instruction BRAM  (64-bit × INSTR_DEPTH, true dual-port)
    ├── Data BRAM         (DATA_WIDTH × DATA_DEPTH, true dual-port, 2× clk)
    ├── Sequencer         (3-stage pipeline: IF / ID / EX with stall-on-hazard)
    └── arith_unit        (unified opcode → PAU / FLO_PAU / FPU back-end)
```

`accel_harness` is a synthesis-only wrapper (no PS7, clocked via `clk_wiz_0`) used by `./build.sh` and `find_fmax.tcl` for fast timing/utilization checks.

**Instruction format (64-bit)**: `[63:60]` opcode · `[59:40]` addr_a · `[39:20]` addr_b · `[19:0]` addr_result. Opcodes are shared across PAU/FPU and defined in `harness/opcodes_pkg.sv` (ADD, SUB, MUL, DIV, SQRT, QACC_*, HALT, …).

## Project Layout

```
harness/        SystemVerilog accelerator RTL + config
  config_pkg.sv     ← edit this
  opcodes_pkg.sv    unified opcode set
  accel_core.sv     sequencer + BRAMs + arith_unit
  accel_axi.sv      AXI-Lite register slave
  accel_axi_burst.sv AXI4 burst slave for bulk DBRAM I/O
  accel_dbram_arb.sv DBRAM port arbiter (AXI-Lite vs burst)
  accel_harness.sv  synthesis-only top (clk_wiz + accel_core)
  zynq_accel_top.sv implementation top (PS7 + AXI + core)
  arith_unit.sv     opcode → PAU/FLO_PAU/FPU dispatch
  pau_top.sv        PAU wrapper (32/64-bit PERCIVAL path)
  flo_posit_top.sv  FloPoCo posit wrapper (8/16/32-bit path)
  fpu_wrap.sv       fpnew FPU wrapper
  positmac{8,16,32}.vhd FloPoCo MAC wrappers
rtl/            Symlinks to PERCIVAL upstream (pau/, fpu/, common_cells/, Flo-Posit/)
tb/             Testbenches + per-config overrides
  tb_accel_core.sv   core-level (BRAM + sequencer + arith_unit)
  tb_accel_axi.sv    AXI register-interface level
  configs/*.sv       config_pkg overrides, one per sim fileset
scripts/        Vivado TCL automation
constraints/    Timing constraints (XDC)
reports/        Generated after build/impl
```

`rtl/` contains **symlinks** into PERCIVAL; do not edit in-place. `harness/pau_top.sv` and `harness/fpu_wrap.sv` are local editable copies.

## Testing

```bash
./test.sh           # runs all 21 simulation filesets
./open.sh           # GUI — useful for waveform debugging
```

`run_all_tests.tcl` launches 21 filesets covering the comparison matrix. Each compiles `tb_accel_core` (or `tb_accel_axi`) against a `tb/configs/config_pkg_*.sv` override so one invocation exercises every supported configuration.

- **Core-level (18)**: `sim_pau{8,16,32,64}`, `sim_pau{16,32}_approx`, `sim_pau32_approx_{div,sqrt}`, `sim_pau32_disabled`, `sim_fpu{32,64}`, `sim_pau{8,16,32}_noquire`, `sim_flo_pau32{,_approx,_noquire,_nodiv}`
- **AXI-level (3)**: `sim_axi` (PAU-32), `sim_axi_pau64`, `sim_axi_fpu32`

A fileset fails if its sim log contains `FAIL:`, `TIMEOUT:`, `FATAL`, or an assertion error (see `scripts/run_all_tests.tcl`). Per-fileset logs live at `vivado_proj/posit_research.sim/<fileset>/behav/xsim/simulate.log`.

To add a new configuration: drop a `config_pkg_xxx.sv` into `tb/configs/`, then register a `sim_xxx` fileset in `scripts/project_setup.tcl` (both the `accel_core_simsets` list and the `{simset cfg_file}` mapping) and in `scripts/run_all_tests.tcl`.

## Reports

| Script        | Key Report                     | What to Check                    |
|---------------|--------------------------------|----------------------------------|
| `./build.sh`  | `reports/build_timing.rpt`     | Post-synthesis WNS estimate      |
| `./build.sh`  | `reports/build_utilization.rpt`| LUT / FF / DSP / BRAM counts     |
| `./impl.sh`   | `reports/timing_summary.rpt`   | Final WNS (≥ 0 = timing met)     |
| `./impl.sh`   | `reports/utilization*.rpt`     | Per-module resource breakdown    |
| `./impl.sh`   | `reports/power.rpt`            | Estimated power consumption      |

Bitstream: `vivado_proj/posit_research.runs/impl_1/zynq_accel_top.bit`

## Fmax Discovery

```bash
/tools/Xilinx/2025.2/Vivado/bin/vivado -mode batch -source scripts/find_fmax.tcl
```

Binary search (4 synthesis iterations, `accel_harness` only) over the clocking-wizard frequency to estimate the maximum that meets timing. Synthesis-only, no P&R.
