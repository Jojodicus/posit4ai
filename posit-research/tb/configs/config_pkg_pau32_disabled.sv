// Simulation-only config override: PAU 32-bit, quire/div/sqrt all disabled.
// Used by sim_pau32_disabled fileset.
// QACC_* ops return NaR; OP_DIV and OP_SQRT return NaR; no quire/div/sqrt hardware.
// Exercises the QUIRE_MODE="DISABLED", DIV_MODE="DISABLE", SQRT_MODE="DISABLE" paths.
// Do NOT use for synthesis.
package config_pkg;
  parameter string ACCEL_TYPE  = "PAU";
  parameter int    DATA_WIDTH  = 32;
  parameter string QUIRE_MODE  = "DISABLED";
  parameter string MUL_MODE    = "EXACT";
  parameter string DIV_MODE    = "DISABLE";
  parameter string SQRT_MODE   = "DISABLE";
  parameter int    INSTR_DEPTH = 256;
  parameter int    DATA_DEPTH  = 4096;
endpackage
