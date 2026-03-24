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
  // PAU supports: 32, 64
  // FPU supports: 32 (single), 64 (double)
  // ============================================================
  parameter int DATA_WIDTH = 32;

  // ============================================================
  // PAU: Posit Exponent Bits (es)
  // Typical values: 0, 1, 2 (standard for 32-bit), 3 (for 64-bit)
  // Only used when ACCEL_TYPE == "PAU"
  // ============================================================
  parameter int POSIT_ES = 2;

  // ============================================================
  // PAU: Quire Accumulator Enable
  // 1 = enable exact accumulation (quire) for QACC_* ops
  // 0 = quire is a single posit register (loses exactness)
  // Only used when ACCEL_TYPE == "PAU"
  // ============================================================
  parameter bit QUIRE_ENABLE = 1;

  // ============================================================
  // PAU: Quire Width Override
  // 0 = auto: 16 * DATA_WIDTH (standard posit quire)
  // N = use N-bit quire
  // Only used when ACCEL_TYPE == "PAU" and QUIRE_ENABLE == 1
  // ============================================================
  parameter int QUIRE_WIDTH = 0;  // 0 = auto

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

  // Derived: actual quire width used by ariane_pkg
  localparam int QUIRE_BITS = (QUIRE_WIDTH == 0) ? 16 * DATA_WIDTH : QUIRE_WIDTH;

endpackage
