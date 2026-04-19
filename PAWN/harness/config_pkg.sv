// Edit ONLY this file to change the accelerator's hardware parameters.

package config_pkg;

  // ============================================================
  // Arithmetic Unit Selection
  // "PAU"     = Posit Arithmetic Unit (PERCIVAL cores, 32/64-bit)
  //             8/16-bit automatically uses FloPoCo (PERCIVAL unsupported there)
  // "FLO_PAU" = Posit Arithmetic Unit (FloPoCo cores, 8/16/32-bit only)
  //             Forces FloPoCo for all widths; 64-bit not available.
  // "FPU"     = IEEE 754 Floating Point Unit (fpnew, 32/64-bit)
  // ============================================================
  parameter string ACCEL_TYPE = "PAU";

  // ============================================================
  // Data Width (bits per arithmetic value)
  // PAU supports:     8, 16 (FloPoCo Flo-Posit cores, es=2)
  //                   32, 64 (PERCIVAL cores, es=2)
  // FLO_PAU supports: 8, 16, 32 (FloPoCo Flo-Posit cores, es=2)
  // FPU supports:     32 (single), 64 (double)
  // ============================================================
  parameter int DATA_WIDTH = 32;

  // ============================================================
  // Quire / Accumulator Mode
  // "QUIRE"       - full hardware quire; QACC_* use exact posit accumulation.
  //                 FPU ignores "QUIRE" and behaves as "ACCUMULATOR".
  // "ACCUMULATOR" - register accumulator, no quire hardware.
  //                 FLO_PAU 8/16/32: nacc_q in flo_posit_top (1-cycle MAC).
  //                 PAU-32/64: acc_q in arith_unit (2-pass PMUL+PADD/PSUB).
  //                 FPU: acc_q in arith_unit (FMA unit).
  // "DISABLED"    - all QACC_* ops return NaR/NaN; no accumulator hardware.
  // ============================================================
  parameter string QUIRE_MODE = "QUIRE";

  // ============================================================
  // Multiply Mode
  // "EXACT"  - exact posit multiplication (all ACCEL_TYPEs).
  // "APPROX" - log-domain approximate multiply (PositLAM / ApproxPositMult).
  //            Supported: PAU-32/64 and FLO_PAU 8/16/32.  FPU: ignored.
  // ============================================================
  parameter string MUL_MODE = "EXACT";

  // ============================================================
  // Divide Mode
  // "EXACT"   - exact division (all ACCEL_TYPEs).
  // "APPROX"  - log-domain approximate divide (PAU-32/64 only).
  //             FLO_PAU and FPU: not available; treated as "EXACT".
  // "DISABLED" - OP_DIV returns NaR/NaN immediately; no hardware
  //             synthesized. Use when division is absent from the workload
  //             to remove the critical-path combinatorial divide block.
  // ============================================================
  parameter string DIV_MODE = "EXACT";

  // ============================================================
  // Square-Root Mode
  // "EXACT"   - exact SQRT (PAU-32/64 and FPU).
  //             FLO_PAU always returns NaR (no FloPoCo SQRT core available).
  // "APPROX"  - log-domain approximate sqrt (PAU-32/64 only).
  //             FLO_PAU and FPU: not available; treated as "EXACT".
  // "DISABLED" - OP_SQRT returns NaR/NaN immediately; no hardware
  //             synthesized. FLO_PAU: already has no SQRT hardware; no-op.
  // ============================================================
  parameter string SQRT_MODE = "EXACT";

  // ============================================================
  // Feature support matrix
  //
  //  Feature                  | PAU-8/16 | PAU-32/64 | FLO_PAU 8/16/32 | FPU-32/64
  //  -------------------------+----------+-----------+-----------------+----------
  //  QUIRE_MODE="QUIRE"       |    Y     |     Y     |        Y        | -(=ACCUM)
  //  QUIRE_MODE="ACCUMULATOR" |    Y     |     Y     |        Y        |    Y
  //  QUIRE_MODE="DISABLED"    |    Y     |     Y     |        Y        |    Y
  //  MUL_MODE="APPROX"        |    Y     |     Y     |        Y        |    -
  //  DIV_MODE="APPROX"        |    -     |     Y     |        -        |    -
  //  DIV_MODE="DISABLED"      |    Y     |     Y     |        Y        | Y(bypass)
  //  SQRT_MODE="APPROX"       |    -     |     Y     |        -        |    -
  //  SQRT_MODE="DISABLED"     |    Y     |     Y     |   Y(already NaR)| Y(bypass)
  // ============================================================

  // ============================================================
  // Memory Sizes
  // INSTR_DEPTH: number of 64-bit instruction words (max 2^20)
  // DATA_DEPTH:  number of DATA_WIDTH-bit data words (max 2^20)
  // Instruction format: 4-bit opcode + 3 x 20-bit addresses = 64 bits
  // ============================================================
  parameter int INSTR_DEPTH = 2 ** 15; // 2 MiB
  parameter int DATA_DEPTH  = 2 ** 15; // 2 MiB

  // ============================================================
  // Fixed by VHDL generation (not configurable at build time):
  //   - Posit exponent bits (es): 2
  //   - Quire width: 16 * DATA_WIDTH
  // ============================================================

endpackage
