// PERCIVAL Accelerator -- data BRAM host-port arbiter.
//
// Arbitrates between multiple host port masters and accel_core's single
// data BRAM host port (port A).
//
// Priority (highest first):
//   1. Port B -- HP0 burst slave (accel_axi_burst), added in Step 3
//   2. Port A -- AXI-Lite slave  (accel_axi)
//
// Step 2: only Port A is wired.  Port B inputs are grounded and Port B
// wins only when b_req is asserted (which it never is at this stage).
// The BRAM write-enable gating (!running) is handled by each master
// individually before asserting we; the arbiter is purely structural.

module accel_dbram_arb
  import config_pkg::*;
(
  // -- Port A: AXI-Lite host (accel_axi) --------------------------
  input  logic [$clog2(DATA_DEPTH)-1:0]  a_addr,
  input  logic [DATA_WIDTH-1:0]          a_wdata,
  input  logic                           a_we,
  output logic [DATA_WIDTH-1:0]          a_rdata,

  // -- Port B: HP0 burst slave (accel_axi_burst) -- added in Step 3 -----
  // b_req must be held for exactly the duration of a burst transaction.
  input  logic                           b_req,    // burst master requests the port
  input  logic [$clog2(DATA_DEPTH)-1:0]  b_addr,
  input  logic [DATA_WIDTH-1:0]          b_wdata,
  input  logic                           b_we,
  output logic [DATA_WIDTH-1:0]          b_rdata,

  // -- accel_core data BRAM host port --------------------------
  output logic [$clog2(DATA_DEPTH)-1:0]  dbram_addr_o,
  output logic [DATA_WIDTH-1:0]          dbram_wdata_o,
  output logic                           dbram_we_o,
  input  logic [DATA_WIDTH-1:0]          dbram_rdata_i
);

  // Port B has priority when it is requesting.
  // Both rdata outputs always reflect the BRAM output; the master that did
  // not "win" the address cycle simply sees the wrong data (it should not
  // be reading while the other master owns the port).
  always_comb begin
    if (b_req) begin
      dbram_addr_o  = b_addr;
      dbram_wdata_o = b_wdata;
      dbram_we_o    = b_we;
    end else begin
      dbram_addr_o  = a_addr;
      dbram_wdata_o = a_wdata;
      dbram_we_o    = a_we;
    end
  end

  assign a_rdata = dbram_rdata_i;
  assign b_rdata = dbram_rdata_i;

  // Write exclusivity is structurally guaranteed: the mux selects exactly one
  // master's we/wdata/addr per cycle.  A concurrent SVA would need a clock
  // port; since the module is purely combinatorial the invariant is self-evident
  // from the always_comb above and needs no separate assertion.

endmodule
