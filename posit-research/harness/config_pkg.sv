// PERCIVAL Accelerator — single configuration file.
// Edit ONLY this file to change the accelerator's hardware parameters.
// After editing, run ./clean.sh then ./build.sh or ./impl.sh.

package config_pkg;

  // ============================================================
  // Arithmetic Unit Selection
  // "PAU" = Posit Arithmetic Unit (PERCIVAL)
  // "FPU" = IEEE 754 Floating Point Unit (fpnew)
  // ============================================================
  parameter string ACCEL_TYPE = "PAU";

  // ============================================================
  // Data Width (bits per arithmetic value)
  // PAU supports: 8, 16 (FloPoCo Flo-Posit cores, es=2)
  //               32, 64 (PERCIVAL cores, es=2)
  // FPU supports: 32 (single), 64 (double)
  //
  // Notes for DATA_WIDTH 8 or 16 with PAU:
  //   PSQRT returns NaR (not supported by FloPoCo cores).
  //   APPROX_DIV / APPROX_SQRT have no effect.
  //   APPROX_MUL = 1 uses PositLAM (log-domain, ~11% bounded relative error).
  // ============================================================
  parameter int DATA_WIDTH = 32;

  // ============================================================
  // PAU: Quire Accumulator Enable
  // 1 = enable exact accumulation (quire) for QACC_* ops
  // 0 = disable quire (QACC_* ops unsupported)
  // Only used when ACCEL_TYPE == "PAU"
  // ============================================================
  parameter bit QUIRE_ENABLE = 1;

  // ============================================================
  // PAU: Approximate Operations (log-domain, faster, less accurate)
  // Only used when ACCEL_TYPE == "PAU"
  // ============================================================
  parameter bit APPROX_MUL  = 0;
  parameter bit APPROX_DIV  = 0;
  parameter bit APPROX_SQRT = 0;

  // ============================================================
  // Memory Sizes
  // INSTR_DEPTH: number of 64-bit instruction words
  // DATA_DEPTH:  number of DATA_WIDTH-bit data words
  // ============================================================
  parameter int INSTR_DEPTH = 256;
  parameter int DATA_DEPTH  = 4096;

  // ============================================================
  // Fixed by VHDL generation (not configurable at build time):
  //   - Posit exponent bits (es): 2 for 32-bit, 2 for 64-bit
  //   - Quire width: 16 * DATA_WIDTH (512 bits for 32-bit, 1024 for 64-bit)
  // To change these, regenerate the VHDL cores via FloPoCo.
  // ============================================================

endpackage
