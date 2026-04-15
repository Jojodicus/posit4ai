// Simulation-only config override: FloPoCo PAU 32-bit, no quire (nacc_q accumulator).
// Used by sim_flo_pau32_noquire fileset. Do NOT use for synthesis.
package config_pkg;
  parameter string ACCEL_TYPE   = "FLO_PAU";
  parameter int    DATA_WIDTH   = 32;
  parameter bit    QUIRE_ENABLE = 0;
  parameter bit    APPROX_MUL  = 0;
  parameter bit    APPROX_DIV  = 0;
  parameter bit    APPROX_SQRT = 0;
  parameter int    INSTR_DEPTH = 256;
  parameter int    DATA_DEPTH  = 4096;
endpackage
