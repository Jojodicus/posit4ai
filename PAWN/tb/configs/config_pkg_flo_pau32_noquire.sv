// Simulation-only config override: FloPoCo PAU 32-bit, no quire (nacc_q accumulator).
// Used by sim_flo_pau32_noquire fileset. Do NOT use for synthesis.
package config_pkg;
  parameter string ACCEL_TYPE   = "FLO_PAU";
  parameter int    DATA_WIDTH   = 32;
  parameter string QUIRE_MODE  = "ACCUMULATOR";
  parameter string MUL_MODE    = "EXACT";
  parameter string DIV_MODE    = "EXACT";
  parameter string SQRT_MODE   = "EXACT";
  parameter int    INSTR_DEPTH = 256;
  parameter int    DATA_DEPTH  = 4096;
endpackage
