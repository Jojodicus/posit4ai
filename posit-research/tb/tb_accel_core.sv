// Testbench for accel_core — configuration-aware, comprehensive.
//
// Compiled against different tb/configs/config_pkg_*.sv overrides by each sim fileset:
//   sim_pau32        PAU  32-bit  exact
//   sim_pau32_approx PAU  32-bit  approx-mul  (APPROX_MUL=1, DIV/SQRT still exact)
//   sim_pau64        PAU  64-bit  exact
//   sim_fpu32        FPU  32-bit
//   sim_fpu64        FPU  64-bit
//
// ── Coverage ─────────────────────────────────────────────────────────────────────
// All 16 opcodes exercised:
//   ADD SUB MUL DIV SQRT NEG ABS MOV RELU
//   QACC_CLEAR QACC_ADD QACC_MADD QACC_MSUB QACC_NEG QACC_READ HALT
//
// Forwarding / stall edge cases:
//   - Result of each arithmetic op used as operand of the very next instruction
//     (tests BRAM write-then-read across adjacent instructions)
//   - Result of DIV  (~10cy stall, PAU) used immediately by next ADD
//   - Result of SQRT (~13cy stall, PAU) used immediately by next ADD
//   - NEG result forwarded to both ABS and RELU
//
// ── Input data (same arithmetic for all configs, different encodings) ─────────────
//   d[0] = 1.0    d[1] = 2.0    d[2] = 4.0
//   All MUL operands are powers of 2 → exact even under APPROX_MUL.
//
// ── Program (IBRAM[0..21]) ────────────────────────────────────────────────────────
//   [0]  ADD  d[0], d[1]  → d[10]   1+2=3
//   [1]  ADD  d[10],d[0]  → d[11]   3+1=4   (fwd d[10])
//   [2]  SUB  d[11],d[1]  → d[12]   4-2=2   (fwd d[11])
//   [3]  MUL  d[0], d[1]  → d[13]   1*2=2
//   [4]  MUL  d[1], d[13] → d[14]   2*2=4   (fwd d[13])
//   [5]  DIV  d[2], d[1]  → d[15]   4/2=2   (long latency)
//   [6]  ADD  d[15],d[0]  → d[16]   2+1=3   (fwd d[15] after DIV stall)
//   [7]  SQRT d[2]        → d[17]   √4=2    (long latency)
//   [8]  ADD  d[17],d[1]  → d[18]   2+2=4   (fwd d[17] after SQRT stall)
//   [9]  NEG  d[1]        → d[19]   -2.0
//   [10] ABS  d[19]       → d[20]   |-2|=2  (fwd d[19])
//   [11] MOV  d[0]        → d[21]   1.0
//   [12] RELU d[19]       → d[22]   max(0,-2)=0  (fwd d[19])
//   [13] RELU d[21]       → d[23]   max(0,1)=1   (fwd d[21])
//   [14] QACC_CLEAR
//   [15] QACC_ADD   d[0]            acc = 1.0
//   [16] QACC_MADD  d[1],d[1]       acc = 1+4 = 5.0
//   [17] QACC_MSUB  d[0],d[1]       acc = 5-2 = 3.0
//   [18] QACC_NEG                   acc = -3.0
//   [19] QACC_MADD  d[1],d[1]       acc = -3+4 = 1.0
//   [20] QACC_READ  → d[24]         d[24] = 1.0
//   [21] HALT
//
// ── Reference encodings ───────────────────────────────────────────────────────────
//   Value │ posit<32,2>  │ posit<64,2>          │ fp32        │ fp64
//   ──────┼─────────────┼──────────────────────┼─────────────┼─────────────────────
//   0.0   │ 0x00000000  │ 0x0000000000000000   │ 0x00000000  │ 0x0000000000000000
//   1.0   │ 0x40000000  │ 0x4000000000000000   │ 0x3F800000  │ 0x3FF0000000000000
//   2.0   │ 0x48000000  │ 0x4800000000000000   │ 0x40000000  │ 0x4000000000000000
//   3.0   │ 0x4C000000  │ 0x4C00000000000000   │ 0x40400000  │ 0x4008000000000000
//   4.0   │ 0x50000000  │ 0x5000000000000000   │ 0x40800000  │ 0x4010000000000000
//  -2.0   │ 0xB8000000  │ 0xB800000000000000   │ 0xC0000000  │ 0xC000000000000000

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

  // ── DUT ──────────────────────────────────────────────────────────────────────
  logic start, done, running;

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

  // ── BRAM helpers ─────────────────────────────────────────────────────────────
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
    input opcode_t     op,
    input logic [11:0] a, b, res
  );
    return {op, a, b, res, 20'b0};
  endfunction

  // ── Config-derived reference values ──────────────────────────────────────────
  // Stored in 64-bit containers; sliced to [DATA_WIDTH-1:0] at use.
  // All `if` branches are compile-time constant — dead branches are never executed.
  logic [63:0] V_0, V_1, V_2, V_3, V_4, V_NEG2;

  initial begin
    if (ACCEL_TYPE == "PAU" && DATA_WIDTH == 32) begin
      // posit<32,2> — same values for exact and approx (mul ops use powers of 2)
      V_0    = 64'h0000_0000_0000_0000;
      V_1    = 64'h0000_0000_4000_0000;
      V_2    = 64'h0000_0000_4800_0000;
      V_3    = 64'h0000_0000_4C00_0000;
      V_4    = 64'h0000_0000_5000_0000;
      V_NEG2 = 64'h0000_0000_B800_0000;
    end else if (ACCEL_TYPE == "PAU" && DATA_WIDTH == 64) begin
      // posit<64,2>
      V_0    = 64'h0000_0000_0000_0000;
      V_1    = 64'h4000_0000_0000_0000;
      V_2    = 64'h4800_0000_0000_0000;
      V_3    = 64'h4C00_0000_0000_0000;
      V_4    = 64'h5000_0000_0000_0000;
      V_NEG2 = 64'hB800_0000_0000_0000;
    end else if (ACCEL_TYPE == "FPU" && DATA_WIDTH == 32) begin
      // IEEE 754 single precision
      V_0    = 64'h0000_0000_0000_0000;
      V_1    = 64'h0000_0000_3F80_0000;
      V_2    = 64'h0000_0000_4000_0000;
      V_3    = 64'h0000_0000_4040_0000;
      V_4    = 64'h0000_0000_4080_0000;
      V_NEG2 = 64'h0000_0000_C000_0000;
    end else begin
      // IEEE 754 double precision
      V_0    = 64'h0000_0000_0000_0000;
      V_1    = 64'h3FF0_0000_0000_0000;
      V_2    = 64'h4000_0000_0000_0000;
      V_3    = 64'h4008_0000_0000_0000;
      V_4    = 64'h4010_0000_0000_0000;
      V_NEG2 = 64'hC000_0000_0000_0000;
    end
  end

  // ── Result tracking ───────────────────────────────────────────────────────────
  int pass_count, fail_count;

  task automatic check(
    input string       label,
    input logic [63:0] expected,
    input int          dbram_slot
  );
    logic [DATA_WIDTH-1:0] got;
    read_dbram(dbram_slot, got);
    if (got == expected[DATA_WIDTH-1:0]) begin
      $display("  PASS  %-30s  got 0x%0X", label, got);
      pass_count++;
    end else begin
      $display("  FAIL  %-30s  got 0x%0X  expected 0x%0X",
               label, got, expected[DATA_WIDTH-1:0]);
      fail_count++;
    end
  endtask

  // ── Test ─────────────────────────────────────────────────────────────────────
  initial begin
    pass_count = 0;
    fail_count = 0;
    start      = 0;
    ibram_addr = 0; ibram_wdata = 0; ibram_we = 0;
    dbram_addr = 0; dbram_wdata = 0; dbram_we = 0;

    // Wait for reset deassertion and for V_* to be assigned (same time-0 initial block)
    @(posedge rst_n);
    repeat(3) @(posedge clk);

    $display("===================================================================");
    $display("Config: %s-%0d%s", ACCEL_TYPE, DATA_WIDTH, APPROX_MUL ? " approx-mul" : "");
    $display("===================================================================");

    // ── Load instruction BRAM ─────────────────────────────────────────────────
    // Section 1: ADD/SUB chain — each result immediately read by next instruction
    write_ibram( 0, make_instr(OP_ADD,  12'd0,  12'd1,  12'd10)); // 1+2=3
    write_ibram( 1, make_instr(OP_ADD,  12'd10, 12'd0,  12'd11)); // 3+1=4  fwd d[10]
    write_ibram( 2, make_instr(OP_SUB,  12'd11, 12'd1,  12'd12)); // 4-2=2  fwd d[11]
    // Section 2: MUL chain — operands are powers of 2 (exact for APPROX_MUL)
    write_ibram( 3, make_instr(OP_MUL,  12'd0,  12'd1,  12'd13)); // 1*2=2
    write_ibram( 4, make_instr(OP_MUL,  12'd1,  12'd13, 12'd14)); // 2*2=4  fwd d[13]
    // Section 3: DIV — long latency (~10cy PAU), result used by next instruction
    write_ibram( 5, make_instr(OP_DIV,  12'd2,  12'd1,  12'd15)); // 4/2=2
    write_ibram( 6, make_instr(OP_ADD,  12'd15, 12'd0,  12'd16)); // 2+1=3  fwd d[15]
    // Section 4: SQRT — long latency (~13cy PAU), result used by next instruction
    write_ibram( 7, make_instr(OP_SQRT, 12'd2,  12'd0,  12'd17)); // √4=2
    write_ibram( 8, make_instr(OP_ADD,  12'd17, 12'd1,  12'd18)); // 2+2=4  fwd d[17]
    // Section 5: Unary ops — NEG result forwarded to ABS and RELU
    write_ibram( 9, make_instr(OP_NEG,  12'd1,  12'd0,  12'd19)); // -2.0
    write_ibram(10, make_instr(OP_ABS,  12'd19, 12'd0,  12'd20)); // |-2|=2  fwd d[19]
    write_ibram(11, make_instr(OP_MOV,  12'd0,  12'd0,  12'd21)); // 1.0
    write_ibram(12, make_instr(OP_RELU, 12'd19, 12'd0,  12'd22)); // max(0,-2)=0  fwd d[19]
    write_ibram(13, make_instr(OP_RELU, 12'd21, 12'd0,  12'd23)); // max(0,1)=1   fwd d[21]
    // Section 6: Quire/accumulator
    write_ibram(14, make_instr(OP_QACC_CLEAR, 12'd0, 12'd0, 12'd0));
    write_ibram(15, make_instr(OP_QACC_ADD,   12'd0, 12'd0, 12'd0)); // acc=1
    write_ibram(16, make_instr(OP_QACC_MADD,  12'd1, 12'd1, 12'd0)); // acc=1+4=5
    write_ibram(17, make_instr(OP_QACC_MSUB,  12'd0, 12'd1, 12'd0)); // acc=5-2=3
    write_ibram(18, make_instr(OP_QACC_NEG,   12'd0, 12'd0, 12'd0)); // acc=-3
    write_ibram(19, make_instr(OP_QACC_MADD,  12'd1, 12'd1, 12'd0)); // acc=-3+4=1
    write_ibram(20, make_instr(OP_QACC_READ,  12'd0, 12'd0, 12'd24));// d[24]=1
    write_ibram(21, make_instr(OP_HALT,        12'd0, 12'd0, 12'd0));

    // ── Load data BRAM ────────────────────────────────────────────────────────
    write_dbram(0, V_1[DATA_WIDTH-1:0]);   // 1.0
    write_dbram(1, V_2[DATA_WIDTH-1:0]);   // 2.0
    write_dbram(2, V_4[DATA_WIDTH-1:0]);   // 4.0

    repeat(3) @(posedge clk);

    // ── Run ───────────────────────────────────────────────────────────────────
    $display("[%0t] Starting accelerator...", $time);
    @(posedge clk); start = 1;
    @(posedge clk); start = 0;

    wait(done);
    repeat(5) @(posedge clk);
    $display("[%0t] Done.", $time);

    // ── Check results ─────────────────────────────────────────────────────────
    $display("-- Section 1: ADD/SUB chain with forwarding --");
    check("ADD  1+2=3             [10]", V_3,    10);
    check("ADD  3+1=4 (fwd[10])  [11]", V_4,    11);
    check("SUB  4-2=2 (fwd[11])  [12]", V_2,    12);

    $display("-- Section 2: MUL chain with forwarding --");
    check("MUL  1*2=2             [13]", V_2,    13);
    check("MUL  2*2=4 (fwd[13])  [14]", V_4,    14);

    $display("-- Section 3: DIV + forwarding after long stall --");
    check("DIV  4/2=2             [15]", V_2,    15);
    check("ADD  2+1=3 (fwd[15])  [16]", V_3,    16);

    $display("-- Section 4: SQRT + forwarding after long stall --");
    check("SQRT sqrt(4)=2         [17]", V_2,    17);
    check("ADD  2+2=4 (fwd[17])  [18]", V_4,    18);

    $display("-- Section 5: Unary ops with forwarding --");
    check("NEG  -2.0              [19]", V_NEG2, 19);
    check("ABS  |-2|=2 (fwd[19]) [20]", V_2,    20);
    check("MOV  1.0               [21]", V_1,    21);
    check("RELU max(0,-2)=0       [22]", V_0,    22);
    check("RELU max(0,1)=1        [23]", V_1,    23);

    $display("-- Section 6: Quire/accumulator --");
    check("QACC 1+4-2→neg→+4=1   [24]", V_1,    24);

    // ── Summary ───────────────────────────────────────────────────────────────
    $display("===================================================================");
    $display("Results: %0d passed, %0d failed  (%s-%0d%s)",
             pass_count, fail_count,
             ACCEL_TYPE, DATA_WIDTH, APPROX_MUL ? "-approx" : "");
    if (fail_count > 0)
      $display("FAIL: %0d test(s) failed", fail_count);
    else
      $display("PASS: all tests passed");
    $display("===================================================================");

    $finish;
  end

  // Watchdog — generous to cover PAU SQRT (~13cy) * many instructions
  initial begin
    #10_000_000;
    $display("TIMEOUT: simulation did not complete");
    $finish;
  end

endmodule
