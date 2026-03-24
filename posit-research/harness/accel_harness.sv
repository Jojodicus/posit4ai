// PERCIVAL Accelerator — synthesis-only top module (no PS7, no AXI).
// Used by ./build.sh for fast timing/utilization checks and Fmax binary search.
// All inputs are registered to prevent Vivado from optimising away the logic.

module accel_harness
  import config_pkg::*;
  import opcodes_pkg::*;
(
  input  logic        clk_in,     // 100 MHz board clock (from Zedboard)
  input  logic        rst_ni_in,  // active-low reset (from board button)
  // Synthesis stimulus inputs — allow Vivado to see non-constant logic
  // (tie all to 0 in constraints; no LOC assignment needed for synth-only flow)
  input  logic [$clog2(INSTR_DEPTH)-1:0] ibram_addr_in,
  input  logic [63:0]                    ibram_wdata_in,
  input  logic                           ibram_we_in,
  input  logic [$clog2(DATA_DEPTH)-1:0]  dbram_addr_in,
  input  logic [DATA_WIDTH-1:0]          dbram_wdata_in,
  input  logic                           dbram_we_in,
  input  logic                           start_in,
  // Synthesis observation outputs — prevent result logic from being trimmed
  output logic                           done_out,
  output logic [DATA_WIDTH-1:0]          dbram_rdata_out
);

  // ── Clocking wizard: board clock → synthesis target frequency ────────────────
  logic clk_core, clk_locked;

  clk_wiz_0 u_clk_wiz (
    .clk_in1  ( clk_in     ),
    .reset    ( 1'b0       ),  // active-high; tie low to keep PLL running
    .clk_out1 ( clk_core   ),
    .locked   ( clk_locked )
  );

  logic rst_n;
  assign rst_n = rst_ni_in & clk_locked;

  // ── Input registers — register from top-level ports so Vivado sees live inputs
  logic [$clog2(INSTR_DEPTH)-1:0] ibram_addr_r;
  logic [63:0]                    ibram_wdata_r;
  logic                           ibram_we_r;
  logic [$clog2(DATA_DEPTH)-1:0]  dbram_addr_r;
  logic [DATA_WIDTH-1:0]          dbram_wdata_r;
  logic                           dbram_we_r;
  logic                           start_r;

  always_ff @(posedge clk_core) begin
    ibram_addr_r  <= ibram_addr_in;
    ibram_wdata_r <= ibram_wdata_in;
    ibram_we_r    <= ibram_we_in;
    dbram_addr_r  <= dbram_addr_in;
    dbram_wdata_r <= dbram_wdata_in;
    dbram_we_r    <= dbram_we_in;
    start_r       <= start_in;
  end

  // ── accel_core ────────────────────────────────────────────────────────────────
  logic done_sig, running_sig;
  logic [63:0]         ibram_rdata_sig;
  logic [DATA_WIDTH-1:0] dbram_rdata_sig;

  assign done_out        = done_sig;
  assign dbram_rdata_out = dbram_rdata_sig;

  accel_core u_core (
    .clk_i         ( clk_core      ),
    .rst_ni        ( rst_n         ),
    .start_i       ( start_r       ),
    .done_o        ( done_sig      ),
    .running_o     ( running_sig   ),
    .ibram_addr_i  ( ibram_addr_r  ),
    .ibram_wdata_i ( ibram_wdata_r ),
    .ibram_we_i    ( ibram_we_r    ),
    .ibram_rdata_o ( ibram_rdata_sig ),
    .dbram_addr_i  ( dbram_addr_r  ),
    .dbram_wdata_i ( dbram_wdata_r ),
    .dbram_we_i    ( dbram_we_r    ),
    .dbram_rdata_o ( dbram_rdata_sig )
  );

endmodule
