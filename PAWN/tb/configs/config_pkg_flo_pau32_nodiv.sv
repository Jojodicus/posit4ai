// Simulation-only config override: FloPoCo PAU 32-bit, division disabled.
// Used by sim_flo_pau32_nodiv fileset.  OP_DIV returns NaR; PositDiv32 not synthesized.
// Primary use-case: verify WNS improvement when the critical PositDiv32 path is absent.
// Do NOT use for synthesis.
package config_pkg;
  parameter string ACCEL_TYPE  = "FLO_PAU";
  parameter int    DATA_WIDTH  = 32;
  parameter string QUIRE_MODE  = "QUIRE";
  parameter string MUL_MODE    = "EXACT";
  parameter string DIV_MODE    = "DISABLED";
  parameter string SQRT_MODE   = "EXACT";   // FLO_PAU already returns NaR for SQRT
  parameter int    INSTR_DEPTH = 256;
  parameter int    DATA_DEPTH  = 4096;
endpackage
