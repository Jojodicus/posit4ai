// Simulation-only config override: PAU 32-bit, exact arithmetic.
// Used by sim_pau32 fileset. Do NOT use for synthesis.
package config_pkg;
  parameter string ACCEL_TYPE   = "PAU";
  parameter int    DATA_WIDTH   = 32;
  parameter string QUIRE_MODE  = "QUIRE";
  parameter string MUL_MODE    = "EXACT";
  parameter string DIV_MODE    = "EXACT";
  parameter string SQRT_MODE   = "EXACT";
  parameter int    INSTR_DEPTH = 256;
  parameter int    DATA_DEPTH  = 4096;
endpackage
