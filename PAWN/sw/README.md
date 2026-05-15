# PAWN Userspace Programs

Pre-compiled (cross-compile for Zedboard): `make` or `make CROSS=""` for native.

---

## Smoke tests

| Program | What it does |
|---------|-------------|
| `hello_posit.elf` | `c[i] = a[i] + b[i]` for 4 posit32 values, verifies result |
| `hello_posit2.elf` | Same but with `MUL` |
| `hello_posit64.elf` | Same as hello_posit but with posit64 |

## Throughput benchmarks

| Program | What it does |
|---------|-------------|
| `benchmark.elf [N]` | ADD throughput only (legacy quick-test). Default N=1000. Reports MOPS. |
| `bench_per_op.elf [--count N] [--data-depth N] [--instr-depth N]` | Per-op throughput for all 15 non-HALT opcodes (32-bit). Each fills IBRAM with N independent copies, measures MOPS. Quire ops benchmarked as sequences (QCLR + QOP*N + QREAD). |
| `bench_per_op64.elf [--count N] [--data-depth N] [--instr-depth N]` | Same as bench_per_op but for 64-bit posit data. |

## Workload benchmarks

| Program | What it does |
|---------|-------------|
| `bench_gemm.elf <M> <N> <K> [--no-quire] [--data-depth N] [--instr-depth N] [--seed N]` | GEMM `MxK * KxN` (32-bit auto-tiled, quire or MUL+ADD). Reports program/load/compute/readback timing, MOPS, arithmetic intensity, hex results. |
| `bench_gemm64.elf ...` | Same with 64-bit posit data. |
| `bench_conv.elf <H> <W> <FH> <FW> [--no-quire] [--data-depth N] [--instr-depth N] [--seed N]` | 2D conv `HxW * FHxFW` (32-bit, im2col + tiled). Same output format as GEMM. |
| `bench_conv64.elf ...` | Same with 64-bit posit data. |

## Diagnostics

| Program | What it does |
|---------|-------------|
| `long_run_status.elf` | Loads full IBRAM with MOV ops, polls STATUS register during execution, verifies DONE and data integrity. Tests reset+start edge cases. |

## Scripts on the board

| Script | Usage | What it does |
|--------|-------|-------------|
| `load.sh` | `./load.sh [<bitstream.bin>]` | Programs FPGA bitstream via fpga_manager + SLCR. Defaults to `zynq_accel_top.bin` if no arg given. |
| `bench_all.sh` | `./bench_all.sh <bitstream_path> <mode> <data_width>` | Runs all benchmarks for a given config. Positional args: bitstream path (basename used as CSV config tag), mode (`quire` or `no-quire`), data width (`32` or `64`). Loads bitstream via `load.sh`, runs per-op + GEMM (32/64/128/256) + CONV (3x3 and 5x5 at various sizes), collects `#CSV` lines into `results_<config>.csv`. |

Example on the board:
```bash
cd /home/root/pawn
./bench_all.sh ./pau32_quire.bin quire 32
```

Output: individual `.log` files per benchmark + consolidated `results_pau32_quire_quire.csv`.

## Notes

- All benchmarks print a `#CSV` line at the end for machine parsing (roofline data, etc.).
- `--seed N` gives reproducible random data; cross-check hex results against the x86 software reference in `libpawn/examples/`.
- Default `--data-depth` and `--instr-depth` are 32768 (match `config_pkg.sv` defaults).
- `AXI_FULL=1` env var enables AXI4 burst transfers instead of FIFO-style AXI-Lite PIO.
