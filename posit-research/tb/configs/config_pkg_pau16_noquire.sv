// Simulation-only config override: PAU 16-bit, no quire (register accumulator).
// Used by sim_pau16_noquire fileset. Do NOT use for synthesis.
package config_pkg;
  parameter string ACCEL_TYPE   = "PAU";
  parameter int    DATA_WIDTH   = 16;
  parameter bit    QUIRE_ENABLE = 0;
  parameter bit    APPROX_MUL  = 0;
  parameter bit    APPROX_DIV  = 0;
  parameter bit    APPROX_SQRT = 0;
  parameter int    INSTR_DEPTH = 256;
  parameter int    DATA_DEPTH  = 4096;
endpackage
