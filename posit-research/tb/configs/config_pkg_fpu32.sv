// Simulation-only config override: FPU (IEEE 754) 32-bit.
// Used by sim_fpu32 fileset. Do NOT use for synthesis.
package config_pkg;
  parameter string ACCEL_TYPE   = "FPU";
  parameter int    DATA_WIDTH   = 32;
  parameter string QUIRE_MODE  = "ACCUMULATOR";
  parameter string MUL_MODE    = "EXACT";
  parameter string DIV_MODE    = "EXACT";
  parameter string SQRT_MODE   = "EXACT";
  parameter int    INSTR_DEPTH = 256;
  parameter int    DATA_DEPTH  = 4096;
endpackage
