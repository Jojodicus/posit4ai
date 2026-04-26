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
+-- zynq_ps_wrapper       (PS7 block design; PL_CLK input from clk_wiz_0)
+-- accel_axi             (AXI-Lite slave at 0x43C00000, register interface)
+-- accel_axi_burst       (AXI4 burst slave, GP1, bulk DBRAM transfers)
+-- accel_dbram_arb       (arbiter between the two AXI masters)
\+-- accel_core            (sequencer + BRAMs + arithmetic)
    +-- Instruction BRAM  (64-bit x INSTR_DEPTH, true dual-port)
    +-- Data BRAM         (DATA_WIDTH x DATA_DEPTH, true dual-port, 2x clk)
    +-- Sequencer         (3-stage pipeline: IF / ID / EX with stall-on-hazard)
    \- arith_unit        (unified opcode -> PAU / FLO_PAU / FPU back-end)
```

Clocking: 100 MHz crystal (Zedboard Y9) -> `clk_wiz_0` -> `clk_core` (CLOCK_FREQ_MHZ) + `clk_bram` (2x). `clk_core` drives both the PS7 AXI master ports and the accelerator slave, so there is no clock domain crossing on the AXI bus.

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

---

## Running on the Zedboard (PetaLinux)

### Build the bitstream

```bash
vim harness/config_pkg.sv   # choose ACCEL_TYPE, DATA_WIDTH, etc.
./clean.sh
./impl.sh 30                # 30 MHz target; edit frequency as needed
# -> vivado_proj/posit_research.runs/impl_1/zynq_accel_top.bit
```

### Cross-compile the userspace programs

Install the ARM toolchain on your host:

```bash
# Debian/Ubuntu
sudo apt install gcc-arm-linux-gnueabihf
# Arch/Manjaro
sudo pacman -S arm-linux-gnueabihf-gcc
```

Build:

```bash
cd sw
make CROSS=arm-linux-gnueabihf-
# -> examples/hello_posit  examples/benchmark
```

### Copy files to the board

Set your board's IP (check the PetaLinux boot log or your DHCP leases):

```bash
./scripts/board_push.sh 192.168.1.100 root
```

This copies the bitstream and both example binaries to `~/pawn/` on the board.

### Program the bitstream

SSH to the board (`./scripts/board_run.sh 192.168.1.100 root`) and run:

```bash
# Zynq xdevcfg interface (available on stock PetaLinux, no extra kernel module)
dd if=/home/root/pawn/zynq_accel_top.bit of=/dev/xdevcfg
```

The DONE LED on the Zedboard lights up when configuration succeeds.

### Run the examples

```bash
/home/root/pawn/examples/hello_posit
/home/root/pawn/examples/benchmark 4096
```

Both programs open `/dev/mem` directly (root required by default).
`hello_posit` computes 4 posit additions and prints the raw hex results.
`benchmark` times N independent ADD operations and reports cycles/op.

### Profiling

**Elapsed time** is returned by `pawn_run_blocking` in nanoseconds
(`CLOCK_MONOTONIC`). Convert to cycles: `cycles = ns / (1000.0 / FREQ_MHZ)`.

**`perf`** (if built into your PetaLinux kernel):

```bash
perf stat ./examples/benchmark 4096
```

For finer-grained host-side profiling wrap individual `pawn_dbram_write32` /
`pawn_load_program` calls with `clock_gettime(CLOCK_MONOTONIC, ...)` pairs.
