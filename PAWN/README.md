# PAWN (**P**osit **A**ccelerator for **W**orking with **N**eural Nets)

Standalone FPGA accelerator for comparing Posit Arithmetic (PAU) vs IEEE 754 Floating Point (FPU) performance on the Xilinx Zedboard (Zynq-7000, `xc7z020clg484-1`). The same opcode set drives either unit, so performance, utilization, and power can be compared on equal footing.

## Prerequisites

- Vivado
- Git submodules initialized

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

All user-tunable parameters live in **`harness/config_pkg.sv`**, it is the only file you need to touch.

## Architecture

```
zynq_accel_top            (impl top: PS7 + AXI)
+-- zynq_ps_wrapper       (PS7 block design; 100 MHz FCLK_CLK0)
+-- accel_axi             (AXI-Lite slave at 0x43C00000, register interface)
+-- accel_axi_burst       (AXI4 burst slave, GP1, bulk DBRAM transfers)
+-- accel_dbram_arb       (arbiter between the two AXI masters)
\+-- accel_core            (sequencer + BRAMs + arithmetic)
    +-- Instruction BRAM  (64-bit x INSTR_DEPTH, true dual-port)
    +-- Data BRAM         (DATA_WIDTH x DATA_DEPTH, true dual-port, 2x clk)
    +-- Sequencer         (3-stage pipeline: IF / ID / EX with stall-on-hazard)
    \- arith_unit        (unified opcode -> PAU / FLO_PAU / FPU back-end)
```

**Instruction format (64-bit)**: `[63:60]` opcode `[59:40]` addr_a `[39:20]` addr_b `[19:0]` addr_result. Opcodes are shared across PAU/FPU and defined in `harness/pkg/opcodes_pkg.sv`.

## Testing

```bash
./test.sh           # runs all 21 simulation filesets
./open.sh           # GUI - useful for waveform debugging
```

To add a new configuration: drop a `config_pkg_xxx.sv` into `tb/configs/`, then register a `sim_xxx` fileset in `scripts/project_setup.tcl` (both the `accel_core_simsets` list and the `{simset cfg_file}` mapping) and in `scripts/run_all_tests.tcl`.

## Reports

| Script        | Key Report                     | What to Check                    |
|---------------|--------------------------------|----------------------------------|
| `./build.sh`  | `reports/build_timing.rpt`     | Post-synthesis WNS estimate      |
| `./build.sh`  | `reports/build_utilization.rpt`| LUT / FF / DSP / BRAM counts     |
| `./impl.sh`   | `reports/timing_summary.rpt`   | Final WNS (>= 0 = timing met)     |
| `./impl.sh`   | `reports/utilization*.rpt`     | Per-module resource breakdown    |
| `./impl.sh`   | `reports/power.rpt`            | Estimated power consumption      |

Bitstream: `vivado_proj/posit_research.runs/impl_1/zynq_accel_top.bit`

## Fmax Discovery

TODO
