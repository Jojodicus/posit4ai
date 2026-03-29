// Simulation-only config override: FPU (IEEE 754) 64-bit.
// Used by sim_fpu64 fileset. Do NOT use for synthesis.
package config_pkg;
  parameter string ACCEL_TYPE   = "FPU";
  parameter int    DATA_WIDTH   = 64;
  parameter bit    QUIRE_ENABLE = 1;
  parameter bit    APPROX_MUL  = 0;
  parameter bit    APPROX_DIV  = 0;
  parameter bit    APPROX_SQRT = 0;
  parameter int    INSTR_DEPTH = 256;
  parameter int    DATA_DEPTH  = 4096;
endpackage
