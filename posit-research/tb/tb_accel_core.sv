// Testbench for accel_core — configuration-aware.
//
// This single testbench file is compiled against different config_pkg overrides
// (from tb/configs/) by each simulation fileset.  It adapts its input operands
// and expected results at compile time based on ACCEL_TYPE, DATA_WIDTH, and
// APPROX_MUL.  Running all filesets therefore covers the full comparison matrix:
//
//   sim_pau32        PAU  32-bit  exact
//   sim_pau32_approx PAU  32-bit  approx-mul
//   sim_pau64        PAU  64-bit  exact
//   sim_fpu32        FPU  32-bit
//   sim_fpu64        FPU  64-bit
//
// Program (same for all configs):
//   IBRAM[0]:  ADD   data[0], data[1] → data[2]          ; 1.0 + 1.0 = 2.0
//   IBRAM[1]:  MUL   data[0], data[0] → data[3]          ; 1.0 * 1.0 = 1.0
//   IBRAM[2]:  QACC_CLEAR
//   IBRAM[3]:  QACC_MADD data[0], data[0]                ; acc += 1.0 * 1.0
//   IBRAM[4]:  QACC_MADD data[4], data[4]                ; acc += X * X
//   IBRAM[5]:  QACC_READ → data[5]                       ; data[5] = round(acc)
//   IBRAM[6]:  HALT
//
// X = 3.0 for all exact configs  → QACC result = 1 + 9  = 10.0
// X = 2.0 for PAU32 approx       → QACC result = 1 + 4  =  5.0
//   (powers of 2 are exact even under log-domain approx)
//
// Encoding reference (all values used below):
//   Format   │  1.0               │  2.0               │  3.0/2.0           │  5.0/10.0
//   ─────────┼────────────────────┼────────────────────┼────────────────────┼──────────────────
//   posit32  │  0x40000000        │  0x48000000        │  0x4C000000 / 0x48 │  0x52000000 / 0x5A
//   posit64  │  0x4000000000000000│  0x4800000000000000│  0x4C00000000000000│  0x5A00000000000000
//   fp32     │  0x3F800000        │  0x40000000        │  0x40400000        │  0x41200000
//   fp64     │  0x3FF0000000000000│  0x4000000000000000│  0x4008000000000000│  0x4024000000000000

`timescale 1ns/1ps

module tb_accel_core
  import config_pkg::*;
  import opcodes_pkg::*;
();

  localparam CLK_PERIOD = 10;   // 10 ns = 100 MHz

  // ── Clock and reset ──────────────────────────────────────────────────────────
  logic clk, rst_n;
  initial clk = 0;
  always #(CLK_PERIOD/2) clk = ~clk;

  initial begin
    rst_n = 0;
    repeat(5) @(posedge clk);
    rst_n = 1;
  end

  // ── DUT signals ──────────────────────────────────────────────────────────────
  logic start;
  logic done, running;

  logic [$clog2(INSTR_DEPTH)-1:0] ibram_addr;
  logic [63:0]                    ibram_wdata;
  logic                           ibram_we;
  logic [63:0]                    ibram_rdata;

  logic [$clog2(DATA_DEPTH)-1:0]  dbram_addr;
  logic [DATA_WIDTH-1:0]          dbram_wdata;
  logic                           dbram_we;
  logic [DATA_WIDTH-1:0]          dbram_rdata;

  accel_core dut (
    .clk_i         ( clk         ),
    .rst_ni        ( rst_n       ),
    .start_i       ( start       ),
    .done_o        ( done        ),
    .running_o     ( running     ),
    .ibram_addr_i  ( ibram_addr  ),
    .ibram_wdata_i ( ibram_wdata ),
    .ibram_we_i    ( ibram_we    ),
    .ibram_rdata_o ( ibram_rdata ),
    .dbram_addr_i  ( dbram_addr  ),
    .dbram_wdata_i ( dbram_wdata ),
    .dbram_we_i    ( dbram_we    ),
    .dbram_rdata_o ( dbram_rdata )
  );

  // ── Helpers ──────────────────────────────────────────────────────────────────
  task automatic write_ibram(input int addr, input logic [63:0] data);
    @(posedge clk);
    ibram_addr  <= addr;
    ibram_wdata <= data;
    ibram_we    <= 1;
    @(posedge clk);
    ibram_we <= 0;
  endtask

  task automatic write_dbram(input int addr, input logic [DATA_WIDTH-1:0] data);
    @(posedge clk);
    dbram_addr  <= addr;
    dbram_wdata <= data;
    dbram_we    <= 1;
    @(posedge clk);
    dbram_we <= 0;
  endtask

  task automatic read_dbram(input int addr, output logic [DATA_WIDTH-1:0] data);
    @(posedge clk);
    dbram_addr <= addr;
    dbram_we   <= 0;
    @(posedge clk);  // present address
    @(posedge clk);  // registered output ready
    data = dbram_rdata;
  endtask

  function automatic logic [63:0] make_instr(
    input opcode_t op,
    input logic [11:0] a, b, res
  );
    return {op, a, b, res, 20'b0};
  endfunction

  // ── Config-derived test vectors ───────────────────────────────────────────────
  // Use 64-bit containers for all reference values; slice to DATA_WIDTH at use.
  // All 32-bit values fit in [31:0]; 64-bit values use the full word.
  // Branches are compile-time constant (config_pkg parameters).
  logic [63:0] IN_1P0;       // operand encoding of 1.0
  logic [63:0] IN_X;         // operand at data[4]: 3.0 (exact) or 2.0 (approx)
  logic [63:0] REF_2P0;      // expected result of 1.0 + 1.0
  logic [63:0] REF_1P0;      // expected result of 1.0 * 1.0
  logic [63:0] REF_QACC;     // expected QACC_READ result

  // Emit the active configuration so failures are easy to diagnose.
  initial begin
    $display("[%0t] Config: ACCEL_TYPE=%s DATA_WIDTH=%0d APPROX_MUL=%0b",
             $time, ACCEL_TYPE, DATA_WIDTH, APPROX_MUL);

    if (ACCEL_TYPE == "PAU" && DATA_WIDTH == 32 && APPROX_MUL == 0) begin
      // ── posit<32,2> exact ────────────────────────────────────────────────────
      IN_1P0    = 64'h0000_0000_4000_0000;  // posit32 1.0
      IN_X      = 64'h0000_0000_4C00_0000;  // posit32 3.0
      REF_1P0   = 64'h0000_0000_4000_0000;  // 1.0
      REF_2P0   = 64'h0000_0000_4800_0000;  // 2.0
      REF_QACC  = 64'h0000_0000_5A00_0000;  // 10.0 = 1*1 + 3*3

    end else if (ACCEL_TYPE == "PAU" && DATA_WIDTH == 32 && APPROX_MUL == 1) begin
      // ── posit<32,2> approx-mul ───────────────────────────────────────────────
      // Use powers of 2 so log-domain multiply is exact.
      IN_1P0    = 64'h0000_0000_4000_0000;  // posit32 1.0
      IN_X      = 64'h0000_0000_4800_0000;  // posit32 2.0  (instead of 3.0)
      REF_1P0   = 64'h0000_0000_4000_0000;  // 1.0
      REF_2P0   = 64'h0000_0000_4800_0000;  // 2.0
      REF_QACC  = 64'h0000_0000_5200_0000;  // 5.0 = 1*1 + 2*2

    end else if (ACCEL_TYPE == "PAU" && DATA_WIDTH == 64) begin
      // ── posit<64,2> exact ────────────────────────────────────────────────────
      IN_1P0    = 64'h4000_0000_0000_0000;  // posit64 1.0
      IN_X      = 64'h4C00_0000_0000_0000;  // posit64 3.0
      REF_1P0   = 64'h4000_0000_0000_0000;  // 1.0
      REF_2P0   = 64'h4800_0000_0000_0000;  // 2.0
      REF_QACC  = 64'h5A00_0000_0000_0000;  // 10.0 = 1*1 + 3*3

    end else if (ACCEL_TYPE == "FPU" && DATA_WIDTH == 32) begin
      // ── IEEE 754 single precision ────────────────────────────────────────────
      IN_1P0    = 64'h0000_0000_3F80_0000;  // 1.0f
      IN_X      = 64'h0000_0000_4040_0000;  // 3.0f
      REF_1P0   = 64'h0000_0000_3F80_0000;  // 1.0f
      REF_2P0   = 64'h0000_0000_4000_0000;  // 2.0f
      REF_QACC  = 64'h0000_0000_4120_0000;  // 10.0f

    end else begin
      // ── IEEE 754 double precision ────────────────────────────────────────────
      IN_1P0    = 64'h3FF0_0000_0000_0000;  // 1.0
      IN_X      = 64'h4008_0000_0000_0000;  // 3.0
      REF_1P0   = 64'h3FF0_0000_0000_0000;  // 1.0
      REF_2P0   = 64'h4000_0000_0000_0000;  // 2.0
      REF_QACC  = 64'h4024_0000_0000_0000;  // 10.0
    end
  end

  // ── Test program ─────────────────────────────────────────────────────────────
  logic [DATA_WIDTH-1:0] result;
  int pass_count, fail_count;

  initial begin
    pass_count = 0;
    fail_count = 0;
    start      = 0;
    ibram_addr = 0; ibram_wdata = 0; ibram_we = 0;
    dbram_addr = 0; dbram_wdata = 0; dbram_we = 0;

    // Wait for reset and for config vectors to be set (same time-step)
    @(posedge rst_n);
    repeat(3) @(posedge clk);

    // ── Load instruction BRAM ──────────────────────────────────────────────────
    write_ibram(0, make_instr(OP_ADD,        12'd0, 12'd1, 12'd2));
    write_ibram(1, make_instr(OP_MUL,        12'd0, 12'd0, 12'd3));
    write_ibram(2, make_instr(OP_QACC_CLEAR, 12'd0, 12'd0, 12'd0));
    write_ibram(3, make_instr(OP_QACC_MADD,  12'd0, 12'd0, 12'd0));
    write_ibram(4, make_instr(OP_QACC_MADD,  12'd4, 12'd4, 12'd0));
    write_ibram(5, make_instr(OP_QACC_READ,  12'd0, 12'd0, 12'd5));
    write_ibram(6, make_instr(OP_HALT,       12'd0, 12'd0, 12'd0));

    // ── Load data BRAM ─────────────────────────────────────────────────────────
    write_dbram(0, IN_1P0[DATA_WIDTH-1:0]);   // 1.0
    write_dbram(1, IN_1P0[DATA_WIDTH-1:0]);   // 1.0
    write_dbram(4, IN_X[DATA_WIDTH-1:0]);     // 3.0 (or 2.0 for approx)

    repeat(3) @(posedge clk);

    // ── Run ────────────────────────────────────────────────────────────────────
    $display("[%0t] Starting accelerator...", $time);
    @(posedge clk); start = 1;
    @(posedge clk); start = 0;

    wait(done);
    repeat(5) @(posedge clk);

    // ── Check results ──────────────────────────────────────────────────────────
    read_dbram(2, result);
    if (result == REF_2P0[DATA_WIDTH-1:0]) begin
      $display("PASS: ADD  1.0+1.0 = 0x%0X", result);
      pass_count++;
    end else begin
      $display("FAIL: ADD  1.0+1.0 = 0x%0X  (expected 0x%0X)",
               result, REF_2P0[DATA_WIDTH-1:0]);
      fail_count++;
    end

    read_dbram(3, result);
    if (result == REF_1P0[DATA_WIDTH-1:0]) begin
      $display("PASS: MUL  1.0*1.0 = 0x%0X", result);
      pass_count++;
    end else begin
      $display("FAIL: MUL  1.0*1.0 = 0x%0X  (expected 0x%0X)",
               result, REF_1P0[DATA_WIDTH-1:0]);
      fail_count++;
    end

    read_dbram(5, result);
    if (result == REF_QACC[DATA_WIDTH-1:0]) begin
      $display("PASS: QACC 1*1+X*X = 0x%0X", result);
      pass_count++;
    end else begin
      $display("FAIL: QACC 1*1+X*X = 0x%0X  (expected 0x%0X)",
               result, REF_QACC[DATA_WIDTH-1:0]);
      fail_count++;
    end

    $display("[%0t] Results: %0d passed, %0d failed.", $time, pass_count, fail_count);
    if (fail_count > 0)
      $display("FAIL: %0d test(s) failed for config %s-%0d%s",
               fail_count, ACCEL_TYPE, DATA_WIDTH,
               (APPROX_MUL ? "_approx" : ""));
    else
      $display("PASS: all tests passed for config %s-%0d%s",
               ACCEL_TYPE, DATA_WIDTH,
               (APPROX_MUL ? "_approx" : ""));

    $finish;
  end

  // Watchdog
  initial begin
    #5_000_000;
    $display("TIMEOUT: simulation did not complete");
    $finish;
  end

endmodule
