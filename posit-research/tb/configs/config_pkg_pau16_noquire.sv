// Simulation-only config override: PAU 16-bit, no quire (register accumulator).
// Used by sim_pau16_noquire fileset. Do NOT use for synthesis.
package config_pkg;
  parameter string ACCEL_TYPE   = "PAU";
  parameter int    DATA_WIDTH   = 16;
  parameter string QUIRE_MODE  = "ACCUMULATOR";
  parameter string MUL_MODE    = "EXACT";
  parameter string DIV_MODE    = "EXACT";
  parameter string SQRT_MODE   = "EXACT";
  parameter int    INSTR_DEPTH = 256;
  parameter int    DATA_DEPTH  = 4096;
endpackage
