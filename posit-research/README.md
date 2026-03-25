# PERCIVAL Posit vs Float Accelerator

Standalone FPGA accelerator for comparing Posit Arithmetic (PAU) vs IEEE 754 Floating Point (FPU) performance. Runs the same program on either arithmetic unit and measures timing, utilization, and power on the Xilinx Zedboard (Zynq-7000, `xc7z020clg484-1`).

## Prerequisites

- **Vivado 2025.2** installed at `/tools/Xilinx/2025.2/Vivado/`
- **PERCIVAL** repo at `../PERCIVAL/` (sibling directory) — `rtl/` symlinks point there

## Quick Start

```bash
vim harness/config_pkg.sv   # select PAU or FPU, 32 or 64 bit
./clean.sh                  # remove previous build artifacts
./test.sh                   # run functional simulations
./build.sh [FREQ_MHZ]       # synthesis-only (default: 100 MHz)
./impl.sh  [FREQ_MHZ]       # full implementation + bitstream
```

## Configuration

Edit **`harness/config_pkg.sv`** — the only file you need to touch:

| Parameter      | Values            | Description                                   |
|----------------|-------------------|-----------------------------------------------|
| `ACCEL_TYPE`   | `"PAU"` / `"FPU"` | Posit or IEEE 754 arithmetic unit             |
| `DATA_WIDTH`   | `32` / `64`       | Operand width                                 |
| `QUIRE_ENABLE` | `1` / `0`         | PAU exact quire accumulator (PAU only)        |
| `APPROX_MUL`   | `0` / `1`         | Log-domain approximate multiply (PAU only)    |
| `APPROX_DIV`   | `0` / `1`         | Log-domain approximate divide (PAU only)      |
| `APPROX_SQRT`  | `0` / `1`         | Log-domain approximate sqrt (PAU only)        |
| `INSTR_DEPTH`  | integer           | Instruction BRAM depth (default: 256)         |
| `DATA_DEPTH`   | integer           | Data BRAM depth (default: 4096)               |

Posit exponent bits (es=2) and quire width (16 x DATA_WIDTH) are fixed by the pre-generated VHDL cores. Changing these requires regenerating the PAU VHDL via FloPoCo.

After editing, always `./clean.sh` before rebuilding.

## Architecture

```
zynq_accel_top              (impl top: PS7 + AXI slave)
  zynq_ps_wrapper           (Zynq PS7 block design, 100 MHz FCLK_CLK0)
  accel_axi                 (AXI-Lite slave at 0x43C00000)
    accel_core              (sequencer + BRAMs + arithmetic)
      Instruction BRAM      (64-bit x 256, dual-port)
      Data BRAM             (DATA_WIDTH x 4096, true dual-port)
      Sequencer             (FETCH -> DECODE -> EXEC -> WAIT_ARITH -> WRITEBACK)
      arith_unit            (unified opcode interface)
        pau_top  OR  fpu_wrap   (selected by ACCEL_TYPE)
```

`accel_harness` is a synthesis-only wrapper (no PS7) used by `./build.sh` for quick timing checks.

Both units share the same instruction set (`opcodes_pkg.sv`): ADD, SUB, MUL, DIV, SQRT, and quire/accumulator ops (QACC_CLEAR, QACC_MADD, QACC_READ, etc.).

## Project Structure

```
harness/        SystemVerilog accelerator RTL + config
  config_pkg.sv         User configuration (edit this)
  opcodes_pkg.sv        Unified opcode definitions
  accel_core.sv         Sequencer + BRAM + arith_unit
  accel_axi.sv          AXI-Lite register interface
  accel_harness.sv      Synthesis-only top (clk_wiz + accel_core)
  zynq_accel_top.sv     Implementation top (PS7 + accel_axi)
  arith_unit.sv         PAU/FPU opcode translation
  pau_top.sv            PAU wrapper (local copy from PERCIVAL)
  fpu_wrap.sv           FPU wrapper (local copy from PERCIVAL)
rtl/            Symlinks to PERCIVAL upstream sources
  pau/                  VHDL posit arithmetic cores
  fpu/                  fpnew IEEE 754 FPU
  common_cells/         Shared utilities (lzc, rr_arb_tree)
tb/             Testbenches
scripts/        Vivado TCL automation
constraints/    Timing constraints (XDC)
reports/        Generated reports (after build/impl)
```

## Testing

```bash
./test.sh           # runs both testbenches
./open.sh           # open Vivado GUI to debug waveforms
```

Two simulation filesets:
- **sim_core** (`tb_accel_core`) — tests the accelerator core directly
- **sim_axi** (`tb_accel_axi`) — tests the full AXI register interface

## Reports

| Script      | Key Report                     | What to Check                    |
|-------------|--------------------------------|----------------------------------|
| `./build.sh`| `reports/build_timing.rpt`     | Post-synthesis WNS estimate      |
| `./build.sh`| `reports/build_utilization.rpt`| LUT/FF/DSP/BRAM counts          |
| `./impl.sh` | `reports/timing_summary.rpt`   | Final WNS (must be >= 0)         |
| `./impl.sh` | `reports/utilization*.rpt`     | Per-module resource breakdown    |
| `./impl.sh` | `reports/power.rpt`            | Estimated power consumption      |

Bitstream: `vivado_proj/posit_research.runs/impl_1/zynq_accel_top.bit`

## Fmax Discovery

```bash
/tools/Xilinx/2025.2/Vivado/bin/vivado -mode batch -source scripts/find_fmax.tcl
```

Binary search over 4 synthesis iterations to find the maximum frequency that meets timing.
