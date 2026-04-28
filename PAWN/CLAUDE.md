# CLAUDE.md

Guidance for Claude Code working in this repository.

## House Rules

- ASCII only. No unicode arrows, em-dashes, non-breaking spaces, or box-drawing
  characters in source, docs, or comments. Use `->`, `-`, regular spaces, `+-\|`.
- Do not paraphrase `harness/config_pkg.sv` into this file; that file is the
  single source of truth for the option matrix.

## Project Overview

Standalone FPGA accelerator comparing PERCIVAL's Posit Arithmetic Unit (PAU)
against an IEEE 754 FPU on the same opcode set. Target: Zedboard
(Zynq-7000, `xc7z020clg484-1`). Toolchain: Vivado 2025.2 at
`/tools/Xilinx/2025.2/Vivado/`.

`README.md` has the end-user walkthrough. This file only records what the
code does not make obvious.

## Build / Test Loop

```bash
./clean.sh              # wipe vivado_proj/ and reports/
./test.sh               # run all sim filesets via run_all_tests.tcl
./build.sh [FREQ_MHZ]   # synthesis-only on accel_harness (default 100)
./impl.sh  [FREQ_MHZ]   # full P&R + bitstream on zynq_accel_top (default 100)
./open.sh               # open the project in Vivado GUI
```

All scripts source `scripts/vivado_env.sh` automatically.

- `./build.sh FREQ` -> top `accel_harness` (no PS7; `clk_wiz_0` drives
  `clk_core` at FREQ and `clk_bram` at 2x). Fast feedback on utilization and
  timing.
- `./impl.sh  FREQ` -> top `zynq_accel_top` (PS7, AXI-Lite + AXI4 burst).
  `CLOCK_FREQ_MHZ` plumbs through to PS7 FCLK_CLK0. Full P&R and bitstream.
- `scripts/find_fmax.tcl` -> binary-search Fmax with synth-only builds.

Manual: `vivado -mode batch -source scripts/<...>.tcl`, or
`vivado vivado_proj/posit_research.xpr`.

### Tests

`scripts/run_all_tests.tcl` launches all filesets. Each compiles
`tb_accel_core.sv` or `tb_accel_axi.sv` against a `tb/configs/config_pkg_*.sv`
override. A fileset fails if its log matches `FAIL:`, `TIMEOUT:`, `FATAL`,
`Assertion failed`, `$fatal`, or `ASSERT`. Logs:
`vivado_proj/posit_research.sim/<fileset>/behav/xsim/simulate.log`.

Filesets are registered in **both**
`scripts/project_setup.tcl` (the `accel_core_simsets` / `axi_simsets` lists
AND the `{simset cfg_file}` mapping) and `scripts/run_all_tests.tcl`. Update
all three when adding a config.

## Architecture

### Layout

- `harness/config_pkg.sv` -- the only user-facing configuration file.
- `harness/pkg/`    -- packages (opcode, riscv/ariane shims).
- `harness/arith/`  -- PAU / FPU / FloPoCo back-ends + MAC wrappers.
  `positmac{8,16,32}.vhd` compile into per-width libraries
  (`flo_mac8/16/32`) to avoid duplicate-entity-name clashes.
- `harness/core/`   -- `accel_core` (sequencer + BRAMs).
- `harness/axi/`    -- `accel_axi` (AXI-Lite regs), `accel_axi_burst`
  (AXI4 burst), `accel_dbram_arb` (port arbiter).
- `harness/top/`    -- `accel_harness` (build top), `zynq_accel_top`
  (impl top).
- `harness/patches/common_cells/` -- XSim-compatible `.svh` overrides for
  the upstream `include "common_cells/..."` paths.
- `rtl/` -- symlinks into `../PERCIVAL/` (pau, fpu, common_cells, Flo-Posit).
  Do not edit. Local editable copies of `pau_top.sv` / `fpu_wrap.sv` live in
  `harness/arith/`.
- `tb/`, `scripts/`, `constraints/` -- testbenches, Vivado TCL, XDC.

### Top modules

- `zynq_accel_top` (impl) -- PS7 via `zynq_ps_wrapper` + `accel_axi`
  (AXI-Lite at `0x43C00000`) + `accel_axi_burst` (AXI4 on GP1) +
  `accel_dbram_arb` + `accel_core`.
  Currently `accel_core.clk_bram_i` is tied to `FCLK_CLK0` (1x, not 2x) --
  the 2x path is wired through `accel_core` but the second PS7 FCLK is not
  yet enabled. See the TODO in `zynq_accel_top.sv`.
- `accel_harness` (build, find_fmax) -- `clk_wiz_0` (100 MHz ->
  `CLOCK_FREQ_MHZ` + 2x) feeding `accel_core`. No PS7, no AXI.

### Core internals

- Instruction BRAM: 64-bit x `INSTR_DEPTH` (default 32K), true dual-port.
- Data BRAM: `DATA_WIDTH` x `DATA_DEPTH` (default 32K), true dual-port,
  clocked at `clk_bram_i` (intended 2x clk_i; alpha-blending / XAPP706
  pattern).
- 3-stage pipeline IF / ID / EX running in parallel inside `RUNNING_S`.
  `IDLE_S -> RUNNING_S -> HALT_S`. Stalls only while the EX op has not
  produced a result. RAW hazards resolved by a forwarding mux (not by
  stalling).
- `arith_unit` dispatches to `pau_top`, `flo_posit_top`, or `fpu_wrap`
  based on `ACCEL_TYPE` and `DATA_WIDTH`.

### Instruction format (64-bit)

```
[63:60] opcode     [59:40] addr_a     [39:20] addr_b     [19:0] addr_result
```

16 opcodes in `opcodes_pkg.sv`. All 4 bits used (no spare). Address fields
are 20 bits each, capping `DATA_DEPTH` at `2**20`.

### Package compile order

`config_pkg -> opcodes_pkg -> cva6_config_pkg -> riscv_pkg_mini ->
ariane_pkg_mini -> cf_math_pkg -> fpnew_pkg`. Handled by
`project_setup.tcl` via `reorder_files -front`; per-sim filesets
additionally front their own `config_pkg_*.sv` override.

## Pipeline Delay and Throughput

End-to-end latency of one instruction (IF -> ID -> EX -> writeback) is
`2 + L` cycles where `L` is the arith latency. Steady-state throughput
depends on the op class:

| Op class                                   | L (arith cy) | Steady-state |
|--------------------------------------------|--------------|--------------|
| Comb (MOV, NEG, ABS, RELU, disabled ops)   | 0            | 1 cy/op      |
| PAU pipelined (PADD/PSUB/PMUL, QMADD ...)  | >= 1         | L + 1 cy/op  |
| PAU DIV / SQRT                             | 11 / 14      | ~12 / ~15    |
| FPU (fpnew FMA, DIV, SQRT)                 | variable     | L + 1 cy/op  |

The `+1` gap between consecutive non-comb ops is structural and not
reducible: when `arith_valid_o` fires at cycle N, `id_ex_q` still holds the
current instruction. It only advances to the next instruction at the N
clock edge. Setting `accept_new=1` at N would cause accel_core to
re-issue the just-completed op (id_ex_q not yet updated). Eliminating the
gap would require look-ahead into `ibram_fetch_rdata` to pre-issue before
the stall clears -- a major pipeline restructure.

Comb ops reach 1 cy/op because they bypass the PAU/FPU pipeline entirely --
`arith_valid_o` fires the same cycle as `arith_valid_i`, so `stall` never
asserts.

`pau_top` and `flo_posit_top` now support STALL-exit restart: when
`arith_valid_o` fires and a new `pau_valid_i` arrives simultaneously, the
PAU captures the new op in the same cycle (count restarted at 1, not 0).
This is used by `arith_unit` for the 2-pass MAC second pass, collapsing
the old S_MAC_STEP cycle into the PMUL completion cycle.

### Arith-unit PAU latencies (cycles, `pau_valid_i` to `pau_valid_o`)

POSLEN=32 and POSLEN=64 current RTL:

| Op          | Latency |
|-------------|---------|
| PADD / PSUB | 2       |
| PMUL        | 2       |
| QMADD/QMSUB | 3 (POSLEN=32), 4 (POSLEN=64) |
| QROUND      | 3       |
| PDIV        | 11 (exact), 2 (approx) |
| PSQRT       | 14 (exact), 2 (approx) |

(`pau_top` `latency_mux` + one extra cycle because the output FFs register
`pau_valid_d -> pau_valid_o` one cycle after the STALL-exit.)

FloPoCo (`flo_posit_top`, all widths): every op 2 cycles.

### 2-pass MAC (PAU-32/64 ACCUMULATOR mode)

QMADD/QMSUB issues PMUL then PADD/PSUB via `arith_unit`. With the
STALL-exit restart: when PMUL fires, the PADD is issued in the same cycle
using `arith_result` (PMUL output FF) directly as operand. The old
`S_MAC_STEP` idle cycle is eliminated.

Total cycles per QMADD/QMSUB: `L_pmul + L_padd + 1` (pipeline advance) =
2 + 2 + 1 = 5 cy/op (was 6 before S_MAC_STEP removal).

## Configuration

Edit **only** `harness/config_pkg.sv`. The full option matrix and
per-`ACCEL_TYPE` support table live in that file. Do not mirror them
into docs.

Key routing rules that are not obvious from the parameter names:

- `ACCEL_TYPE="PAU"` with `DATA_WIDTH` 8 or 16 -> FloPoCo cores
  automatically (PERCIVAL does not supply those widths).
- `ACCEL_TYPE="FLO_PAU"` forces FloPoCo for 8/16/32. No 64-bit FloPoCo
  cores exist. PSQRT always returns NaR. Approx DIV/SQRT not available.
- `ACCEL_TYPE="FPU"` ignores `QUIRE_MODE="QUIRE"` (treated as
  `ACCUMULATOR`).
- `MUL_MODE="APPROX"` requires PAU or FLO_PAU; FPU silently ignores it.
- Posit `es=2` and quire width (`16 * DATA_WIDTH`) are baked into the
  pre-generated VHDL. Changing them requires regenerating via FloPoCo.

After editing `config_pkg.sv`, run `./clean.sh` before the next build
(Vivado caches stale package state otherwise).

### Clock configuration

- `./build.sh FREQ` and `./impl.sh FREQ` both set `CLOCK_FREQ_MHZ`.
  `run_build.tcl` pushes it into `clk_wiz_0`; `run_impl.tcl` +
  `create_bd.tcl` push it into PS7 FCLK_CLK0.
- 30 MHz currently meets timing at impl (WNS positive). 28 MHz meets
  timing for `accel_harness` synth-only.

## Timing

`reports/timing_summary.rpt` after `./impl.sh`:

- `WNS >= 0`: timing met.
- `WNS <  0`: lower the target frequency or tighten RTL.

Synthesis-only Fmax estimate: `./build.sh [FREQ]` or
`scripts/find_fmax.tcl`, both on `accel_harness`.

## Adding RTL

Edit `scripts/project_setup.tcl`:

- `add_files -norecurse <path>`
- Set SV files explicitly: `set_property file_type SystemVerilog
  [get_files <file>]`.
- `update_compile_order -fileset sources_1`.
- For a new simulation variant, register the fileset in the
  `accel_core_simsets` / `axi_simsets` list, in the `{simset cfg_file}`
  mapping, and in `run_all_tests.tcl`.

## Notes

- Project name / directory: `posit_research` / `vivado_proj/`.
- PAU cores are VHDL (in `rtl/pau/`, `rtl/Flo-Posit/`). FPU, common cells
  and harness are SystemVerilog. Vivado handles mixed-language elaboration.
- Block design `zynq_ps` is (re)created by `scripts/create_bd.tcl`, sourced
  from `project_setup.tcl`.
