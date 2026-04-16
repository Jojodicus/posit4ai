// Testbench for accel_core -- configuration-aware, comprehensive.
//
// Compiled against different tb/configs/config_pkg_*.sv overrides by each sim fileset:
//   sim_pau32               PAU  32-bit  exact
//   sim_pau32_approx        PAU  32-bit  MUL_MODE="APPROX"
//   sim_pau32_approx_div    PAU  32-bit  DIV_MODE="APPROX"
//   sim_pau32_approx_sqrt   PAU  32-bit  SQRT_MODE="APPROX"
//   sim_pau32_disabled      PAU  32-bit  QUIRE_MODE="DISABLED" + DIV/SQRT disabled
//   sim_pau64               PAU  64-bit  exact
//   sim_fpu32               FPU  32-bit
//   sim_fpu64               FPU  64-bit
//   sim_pau8                PAU   8-bit  exact quire
//   sim_pau16               PAU  16-bit  exact quire
//   sim_pau16_approx        PAU  16-bit  MUL_MODE="APPROX", exact quire
//   sim_pau8_noquire        PAU   8-bit  QUIRE_MODE="ACCUMULATOR" (nacc_q in flo_posit_top)
//   sim_pau16_noquire       PAU  16-bit  QUIRE_MODE="ACCUMULATOR" (nacc_q in flo_posit_top)
//   sim_pau32_noquire       PAU  32-bit  QUIRE_MODE="ACCUMULATOR" (acc_q in arith_unit, 2-pass MAC)
//   sim_flo_pau32           FLO_PAU 32-bit  exact quire  (FloPoCo cores; PSQRT->NaR)
//   sim_flo_pau32_approx    FLO_PAU 32-bit  MUL_MODE="APPROX" (PositLAM_32_2)
//   sim_flo_pau32_noquire   FLO_PAU 32-bit  QUIRE_MODE="ACCUMULATOR" (nacc_q in flo_posit_top)
//   sim_flo_pau32_nodiv     FLO_PAU 32-bit  DIV_MODE="DISABLE" (PositDiv32 not synthesized)
//
// -- Coverage ---------------------------------------------------------
// All 16 opcodes exercised:
//   ADD SUB MUL DIV SQRT NEG ABS MOV RELU
//   QACC_CLEAR QACC_ADD QACC_MADD QACC_MSUB QACC_NEG QACC_READ HALT
//
// Edge cases:
//   - Result forwarding across adjacent instructions (all arith ops)
//   - DIV/SQRT long-stall forwarding
//   - NaR (posit) / NaN (FPU) propagation through all arithmetic ops
//   - Zero operand: 0+0, 0*x, x/0, sqrt(0)
//   - Same-address read/write (WAW: ADD d[0],d[1] -> d[0])
//   - Back-to-back comb ops (NEG->ABS->RELU chain, tests zero-latency path)
//   - Quire/accumulator: full sequence including QACC_NEG
//   - Halt then restart with a new program
//   - Max BRAM address access (DATA_DEPTH-1)
//   - Back-to-back long-latency ops (consecutive DIV/SQRT pipeline stress)
//   - Quire accumulation stress (10-op sequence + NEG on zero)
//   - Instruction BRAM saturation (all INSTR_DEPTH slots filled)
//   - Approximate DIV/SQRT liveness (non-NaR output for DIV_MODE/SQRT_MODE="APPROX")
//   - QACC_NEG double-fire: single neg->-x, double neg->+x (regression for pau_top QNEG gate)
//
// -- Reference encodings -------------------------------------------------
//   Value | posit<32,2> | posit<64,2>          | fp32        | fp64
//   ------+-------------+----------------------+-------------+--------------------
//   0.0   | 0x00000000  | 0x0000000000000000   | 0x00000000  | 0x0000000000000000
//   1.0   | 0x40000000  | 0x4000000000000000   | 0x3F800000  | 0x3FF0000000000000
//   2.0   | 0x48000000  | 0x4800000000000000   | 0x40000000  | 0x4000000000000000
//   3.0   | 0x4C000000  | 0x4C00000000000000   | 0x40400000  | 0x4008000000000000
//   4.0   | 0x50000000  | 0x5000000000000000   | 0x40800000  | 0x4010000000000000
//   5.0   | 0x52000000  | 0x5200000000000000   | 0x40A00000  | 0x4014000000000000
//  -2.0   | 0xB8000000  | 0xB800000000000000   | 0xC0000000  | 0xC000000000000000
//  -3.0   | 0xB4000000  | 0xB400000000000000   | 0xC0400000  | 0xC008000000000000
//   NaR   | 0x80000000  | 0x8000000000000000   |    N/A      |    N/A

`timescale 1ns/1ps

module tb_accel_core
  import config_pkg::*;
  import opcodes_pkg::*;
();

  localparam real CLK_PERIOD = 10.0;   // 10 ns = 100 MHz

  // -- Clock and reset -------------------------------------------------
  logic clk, clk_bram, rst_n;
  initial clk = 0;
  always #(CLK_PERIOD/2) clk = ~clk;
  // clk_bram = 2x clk; same initial phase so clk_bram posedge coincides with
  // clk posedge -- that edge is phase_q=0 (read sub-cycle) inside accel_core.
  initial clk_bram = 0;
  always #(CLK_PERIOD/4) clk_bram = ~clk_bram;

  initial begin
    rst_n = 0;
    repeat(5) @(posedge clk);
    rst_n = 1;
  end

  // -- DUT -------------------------------------------------------------
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
    .clk_bram_i    ( clk_bram    ),
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

  // -- BRAM helpers -------------------------------------------------
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
    input logic [19:0] a, b, res
  );
    return {op, a, b, res};
  endfunction

  // -- Run program and wait for done -----------------------------------
  task automatic run_program();
    @(posedge clk); start = 1;
    @(posedge clk); start = 0;
    @(posedge done);  // wait for 0->1 edge (not level) to avoid stale done from HALT_S
    repeat(5) @(posedge clk);
  endtask

  // -- Config-derived reference values ------------------------------
  logic [63:0] V_0, V_1, V_2, V_3, V_4, V_5, V_NEG2, V_NEG3;
  logic [63:0] V_SQRT_2, V_SQRT_FWD;
  // NaR for posit, quiet NaN for FPU
  logic [63:0] V_NAR;
  // Expected result for NaR+1 / NaN+1 (NaR propagates for posit; NaN for FPU)
  logic [63:0] V_NAR_PROP;

  initial begin
    if (ACCEL_TYPE == "PAU" && DATA_WIDTH == 8) begin
      V_0      = 64'h0000_0000_0000_0000;
      V_1      = 64'h0000_0000_0000_0040;
      V_2      = 64'h0000_0000_0000_0048;
      V_3      = 64'h0000_0000_0000_004C;
      V_4      = 64'h0000_0000_0000_0050;
      V_5      = 64'h0000_0000_0000_0052;
      V_NEG2   = 64'h0000_0000_0000_00B8;
      V_NEG3   = 64'h0000_0000_0000_00B4;
      V_NAR    = 64'h0000_0000_0000_0080;
      V_NAR_PROP = V_NAR;  // NaR propagates
      V_SQRT_2 = V_NAR; V_SQRT_FWD = V_NAR;
    end else if (ACCEL_TYPE == "PAU" && DATA_WIDTH == 16) begin
      V_0      = 64'h0000_0000_0000_0000;
      V_1      = 64'h0000_0000_0000_4000;
      V_2      = 64'h0000_0000_0000_4800;
      V_3      = 64'h0000_0000_0000_4C00;
      V_4      = 64'h0000_0000_0000_5000;
      V_5      = 64'h0000_0000_0000_5200;
      V_NEG2   = 64'h0000_0000_0000_B800;
      V_NEG3   = 64'h0000_0000_0000_B400;
      V_NAR    = 64'h0000_0000_0000_8000;
      V_NAR_PROP = V_NAR;
      V_SQRT_2 = V_NAR; V_SQRT_FWD = V_NAR;
    end else if ((ACCEL_TYPE == "PAU" || ACCEL_TYPE == "FLO_PAU") && DATA_WIDTH == 32) begin
      V_0      = 64'h0000_0000_0000_0000;
      V_1      = 64'h0000_0000_4000_0000;
      V_2      = 64'h0000_0000_4800_0000;
      V_3      = 64'h0000_0000_4C00_0000;
      V_4      = 64'h0000_0000_5000_0000;
      V_5      = 64'h0000_0000_5200_0000;
      V_NEG2   = 64'h0000_0000_B800_0000;
      V_NEG3   = 64'h0000_0000_B400_0000;
      V_NAR    = 64'h0000_0000_8000_0000;
      V_NAR_PROP = V_NAR;
      // FLO_PAU uses FloPoCo cores: PSQRT returns NaR (unsupported), same as PAU-8/16.
      // PERCIVAL PAU-32 supports SQRT correctly.
      if (ACCEL_TYPE == "FLO_PAU") begin
        V_SQRT_2 = V_NAR; V_SQRT_FWD = V_NAR;
      end else begin
        V_SQRT_2 = V_2; V_SQRT_FWD = V_4;
      end
    end else if (ACCEL_TYPE == "PAU" && DATA_WIDTH == 64) begin
      V_0      = 64'h0000_0000_0000_0000;
      V_1      = 64'h4000_0000_0000_0000;
      V_2      = 64'h4800_0000_0000_0000;
      V_3      = 64'h4C00_0000_0000_0000;
      V_4      = 64'h5000_0000_0000_0000;
      V_5      = 64'h5200_0000_0000_0000;
      V_NEG2   = 64'hB800_0000_0000_0000;
      V_NEG3   = 64'hB400_0000_0000_0000;
      V_NAR    = 64'h8000_0000_0000_0000;
      V_NAR_PROP = V_NAR;
      V_SQRT_2 = V_2; V_SQRT_FWD = V_4;
    end else if (ACCEL_TYPE == "FPU" && DATA_WIDTH == 32) begin
      V_0      = 64'h0000_0000_0000_0000;
      V_1      = 64'h0000_0000_3F80_0000;
      V_2      = 64'h0000_0000_4000_0000;
      V_3      = 64'h0000_0000_4040_0000;
      V_4      = 64'h0000_0000_4080_0000;
      V_5      = 64'h0000_0000_40A0_0000;
      V_NEG2   = 64'h0000_0000_C000_0000;
      V_NEG3   = 64'h0000_0000_C040_0000;
      // quiet NaN (sign=0, exp=FF, frac MSB=1)
      V_NAR      = 64'h0000_0000_7FC0_0000;
      V_NAR_PROP = V_NAR;  // NaN propagates
      V_SQRT_2 = V_2; V_SQRT_FWD = V_4;
    end else begin
      // IEEE 754 double precision
      V_0      = 64'h0000_0000_0000_0000;
      V_1      = 64'h3FF0_0000_0000_0000;
      V_2      = 64'h4000_0000_0000_0000;
      V_3      = 64'h4008_0000_0000_0000;
      V_4      = 64'h4010_0000_0000_0000;
      V_5      = 64'h4014_0000_0000_0000;
      V_NEG2   = 64'hC000_0000_0000_0000;
      V_NEG3   = 64'hC008_0000_0000_0000;
      // quiet NaN (sign=0, exp=7FF, frac MSB=1)
      V_NAR      = 64'h7FF8_0000_0000_0000;
      V_NAR_PROP = V_NAR;
      V_SQRT_2 = V_2; V_SQRT_FWD = V_4;
    end
  end

  // -- Result tracking ---------------------------------------------
  int pass_count, fail_count;

  task automatic check(
    input string       label,
    input logic [63:0] expected,
    input int          dbram_slot
  );
    logic [DATA_WIDTH-1:0] got;
    read_dbram(dbram_slot, got);
    if (got == expected[DATA_WIDTH-1:0]) begin
      $display("  PASS  %-35s  got 0x%0X", label, got);
      pass_count++;
    end else begin
      $display("  FAIL  %-35s  got 0x%0X  expected 0x%0X",
               label, got, expected[DATA_WIDTH-1:0]);
      fail_count++;
    end
  endtask

  // For NaN checks: any NaN (exp=all-1, frac!=0) counts as pass
  task automatic check_nan(
    input string label,
    input int    dbram_slot
  );
    logic [DATA_WIDTH-1:0] got;
    logic is_nan;
    read_dbram(dbram_slot, got);
    if (DATA_WIDTH == 32)
      is_nan = (got[30:23] == 8'hFF) && (got[22:0] != '0);
    else
      is_nan = (got[62:52] == 11'h7FF) && (got[51:0] != '0);
    if (is_nan) begin
      $display("  PASS  %-35s  got NaN 0x%0X", label, got);
      pass_count++;
    end else begin
      $display("  FAIL  %-35s  got 0x%0X  expected NaN", label, got);
      fail_count++;
    end
  endtask

  // For approximate ops: check result is non-zero and non-NaR (liveness check).
  // Approximate arithmetic (log-domain) doesn't produce exact results, so we
  // only verify the output is a valid, non-special value.
  task automatic check_not_nar(
    input string label,
    input int    dbram_slot
  );
    logic [DATA_WIDTH-1:0] got;
    logic is_special;
    read_dbram(dbram_slot, got);
    if (ACCEL_TYPE == "PAU" || ACCEL_TYPE == "FLO_PAU")
      is_special = (got == '0) || (got == {1'b1, {(DATA_WIDTH-1){1'b0}}});  // 0 or NaR
    else if (DATA_WIDTH == 32)
      is_special = (got[30:23] == 8'hFF);  // Inf or NaN
    else
      is_special = (got[62:52] == 11'h7FF);
    if (!is_special && got != '0) begin
      $display("  PASS  %-35s  got 0x%0X (approx, non-NaR)", label, got);
      pass_count++;
    end else begin
      $display("  FAIL  %-35s  got 0x%0X  expected non-zero, non-NaR", label, got);
      fail_count++;
    end
  endtask

  // -- Mode-aware check helpers -------------------------------------
  // These tasks encode the DIV/SQRT/QUIRE mode branching once, so call-sites can
  // describe the *intended* operation (e.g. "DIV 4/2=2") and the task appends a
  // short suffix explaining how the check was actually performed.

  // DIV result: disabled -> NaR, approx -> liveness, else exact.
  task automatic check_div(
    input string       label,
    input logic [63:0] v_exact,
    input int          slot
  );
    if (DIV_MODE == "DISABLE")
      check({label, " [disabled->NaR]"}, V_NAR, slot);
    else if (DIV_MODE == "APPROX")
      check_not_nar({label, " [approx]"}, slot);
    else
      check(label, v_exact, slot);
  endtask

  // Result of an instruction that consumed a DIV output as operand.
  task automatic check_after_div(
    input string       label,
    input logic [63:0] v_exact,
    input int          slot
  );
    if (DIV_MODE == "DISABLE")
      check({label, " [div NaR->NaR prop]"}, V_NAR_PROP, slot);
    else if (DIV_MODE == "APPROX")
      check_not_nar({label, " [div approx fwd]"}, slot);
    else
      check(label, v_exact, slot);
  endtask

  // SQRT result: no-hw configs (PAU-8/16, FLO_PAU) always NaR; then mode checks.
  task automatic check_sqrt(
    input string       label,
    input logic [63:0] v_exact,
    input int          slot
  );
    bit no_sqrt_hw;
    no_sqrt_hw = ((ACCEL_TYPE == "PAU" && (DATA_WIDTH == 8 || DATA_WIDTH == 16)) ||
                  ACCEL_TYPE == "FLO_PAU");
    if (no_sqrt_hw)
      check({label, " [no hw->NaR]"}, V_NAR, slot);
    else if (SQRT_MODE == "DISABLE")
      check({label, " [disabled->NaR]"}, V_NAR, slot);
    else if (SQRT_MODE == "APPROX")
      check_not_nar({label, " [approx]"}, slot);
    else
      check(label, v_exact, slot);
  endtask

  // Result of an instruction that consumed a SQRT output as operand.
  task automatic check_after_sqrt(
    input string       label,
    input logic [63:0] v_exact,
    input int          slot
  );
    bit no_sqrt_hw;
    no_sqrt_hw = ((ACCEL_TYPE == "PAU" && (DATA_WIDTH == 8 || DATA_WIDTH == 16)) ||
                  ACCEL_TYPE == "FLO_PAU");
    if (no_sqrt_hw)
      check({label, " [no hw->NaR prop]"}, V_NAR_PROP, slot);
    else if (SQRT_MODE == "DISABLE")
      check({label, " [disabled->NaR prop]"}, V_NAR_PROP, slot);
    else if (SQRT_MODE == "APPROX")
      check_not_nar({label, " [sqrt approx fwd]"}, slot);
    else
      check(label, v_exact, slot);
  endtask

  // DIV where the dividend came from a SQRT: compound check.
  // DIV-disabled beats SQRT-disabled; if SQRT was NaR, DIV propagates NaR.
  task automatic check_div_of_sqrt(
    input string       label,
    input logic [63:0] v_exact,
    input int          slot
  );
    bit no_sqrt_hw, sqrt_was_nar;
    no_sqrt_hw   = ((ACCEL_TYPE == "PAU" && (DATA_WIDTH == 8 || DATA_WIDTH == 16)) ||
                    ACCEL_TYPE == "FLO_PAU");
    sqrt_was_nar = no_sqrt_hw || (SQRT_MODE == "DISABLE");
    if (DIV_MODE == "DISABLE")
      check({label, " [div disabled->NaR]"}, V_NAR, slot);
    else if (sqrt_was_nar)
      check({label, " [sqrt NaR->NaR prop]"}, V_NAR, slot);
    else if (SQRT_MODE == "APPROX" || DIV_MODE == "APPROX")
      check_not_nar({label, " [approx]"}, slot);
    else
      check(label, v_exact, slot);
  endtask

  // QACC result: QUIRE_MODE="DISABLED" makes all QACC ops return NaR.
  task automatic check_qacc(
    input string       label,
    input logic [63:0] v_exact,
    input int          slot
  );
    if (QUIRE_MODE == "DISABLED")
      check({label, " [disabled->NaR]"}, V_NAR, slot);
    else
      check(label, v_exact, slot);
  endtask

  // -- Test -------------------------------------------------------------
  initial begin
    pass_count = 0;
    fail_count = 0;
    start      = 0;
    ibram_addr = 0; ibram_wdata = 0; ibram_we = 0;
    dbram_addr = 0; dbram_wdata = 0; dbram_we = 0;

    @(posedge rst_n);
    repeat(3) @(posedge clk);

    $display("===================================================================");
    $display("Config: %s-%0d quire=%s mul=%s div=%s sqrt=%s",
             ACCEL_TYPE, DATA_WIDTH, QUIRE_MODE, MUL_MODE, DIV_MODE, SQRT_MODE);
    $display("===================================================================");

    // ==================================================================
    // PROGRAM 1: Main arithmetic + forwarding + quire
    // ==================================================================
    // Data: d[0]=1.0  d[1]=2.0  d[2]=4.0  d[3]=0.0  d[4]=NaR/NaN
    write_dbram(0, V_1[DATA_WIDTH-1:0]);
    write_dbram(1, V_2[DATA_WIDTH-1:0]);
    write_dbram(2, V_4[DATA_WIDTH-1:0]);
    write_dbram(3, V_0[DATA_WIDTH-1:0]);
    write_dbram(4, V_NAR[DATA_WIDTH-1:0]);

    // Section 1: ADD/SUB chain with forwarding
    write_ibram( 0, make_instr(OP_ADD,  20'd0,  20'd1,  20'd10)); // 1+2=3
    write_ibram( 1, make_instr(OP_ADD,  20'd10, 20'd0,  20'd11)); // 3+1=4  fwd d[10]
    write_ibram( 2, make_instr(OP_SUB,  20'd11, 20'd1,  20'd12)); // 4-2=2  fwd d[11]
    // Section 2: MUL chain with forwarding
    write_ibram( 3, make_instr(OP_MUL,  20'd0,  20'd1,  20'd13)); // 1*2=2
    write_ibram( 4, make_instr(OP_MUL,  20'd1,  20'd13, 20'd14)); // 2*2=4  fwd d[13]
    // Section 3: DIV + long-stall forwarding
    write_ibram( 5, make_instr(OP_DIV,  20'd2,  20'd1,  20'd15)); // 4/2=2
    write_ibram( 6, make_instr(OP_ADD,  20'd15, 20'd0,  20'd16)); // 2+1=3  fwd d[15]
    // Section 4: SQRT + long-stall forwarding
    write_ibram( 7, make_instr(OP_SQRT, 20'd2,  20'd0,  20'd17)); // sqrt(4)=2
    write_ibram( 8, make_instr(OP_ADD,  20'd17, 20'd1,  20'd18)); // 2+2=4  fwd d[17]
    // Section 5: Unary ops with forwarding
    write_ibram( 9, make_instr(OP_NEG,  20'd1,  20'd0,  20'd19)); // -2.0
    write_ibram(10, make_instr(OP_ABS,  20'd19, 20'd0,  20'd20)); // |-2|=2  fwd d[19]
    write_ibram(11, make_instr(OP_MOV,  20'd0,  20'd0,  20'd21)); // 1.0
    write_ibram(12, make_instr(OP_RELU, 20'd19, 20'd0,  20'd22)); // max(0,-2)=0
    write_ibram(13, make_instr(OP_RELU, 20'd21, 20'd0,  20'd23)); // max(0,1)=1
    // Section 6: Quire/accumulator
    write_ibram(14, make_instr(OP_QACC_CLEAR, 20'd0, 20'd0, 20'd0));
    write_ibram(15, make_instr(OP_QACC_ADD,   20'd0, 20'd0, 20'd0)); // acc=1
    write_ibram(16, make_instr(OP_QACC_MADD,  20'd1, 20'd1, 20'd0)); // acc=1+4=5
    write_ibram(17, make_instr(OP_QACC_MSUB,  20'd0, 20'd1, 20'd0)); // acc=5-2=3
    write_ibram(18, make_instr(OP_QACC_NEG,   20'd0, 20'd0, 20'd0)); // acc=-3
    write_ibram(19, make_instr(OP_QACC_MADD,  20'd1, 20'd1, 20'd0)); // acc=-3+4=1
    write_ibram(20, make_instr(OP_QACC_READ,  20'd0, 20'd0, 20'd24));// d[24]=1
    // Section 7: Zero operand tests
    write_ibram(21, make_instr(OP_ADD,  20'd3,  20'd3,  20'd30)); // 0+0=0
    write_ibram(22, make_instr(OP_MUL,  20'd3,  20'd1,  20'd31)); // 0*2=0
    write_ibram(23, make_instr(OP_MUL,  20'd0,  20'd3,  20'd32)); // 1*0=0
    // Section 8: NaR/NaN propagation
    write_ibram(24, make_instr(OP_ADD,  20'd4,  20'd0,  20'd40)); // NaR+1
    write_ibram(25, make_instr(OP_MUL,  20'd4,  20'd1,  20'd41)); // NaR*2
    write_ibram(26, make_instr(OP_NEG,  20'd4,  20'd0,  20'd42)); // -NaR
    write_ibram(27, make_instr(OP_ABS,  20'd4,  20'd0,  20'd43)); // |NaR|
    // Section 9: Same-address WAW (read from d[0]=1, write back to d[0])
    write_ibram(28, make_instr(OP_ADD,  20'd0,  20'd1,  20'd0));  // d[0] = 1+2 = 3
    write_ibram(29, make_instr(OP_MOV,  20'd0,  20'd0,  20'd50)); // d[50] = d[0] (should be 3)
    // Section 10: Back-to-back comb ops (tests zero-latency path)
    write_ibram(30, make_instr(OP_NEG,  20'd1,  20'd0,  20'd51)); // -2
    write_ibram(31, make_instr(OP_NEG,  20'd51, 20'd0,  20'd52)); // -(-2)=2 fwd
    write_ibram(32, make_instr(OP_ABS,  20'd51, 20'd0,  20'd53)); // |-2|=2  fwd
    write_ibram(33, make_instr(OP_RELU, 20'd51, 20'd0,  20'd54)); // max(0,-2)=0 fwd
    write_ibram(34, make_instr(OP_HALT, 20'd0,  20'd0,  20'd0));

    repeat(3) @(posedge clk);

    $display("[%0t] Starting Program 1...", $time);
    run_program();
    $display("[%0t] Program 1 done.", $time);

    // -- Check Program 1 results -------------------------------------------
    $display("-- Section 1: ADD/SUB chain with forwarding --");
    check("ADD  1+2=3             [10]",  V_3,    10);
    check("ADD  3+1=4 (fwd[10])  [11]",  V_4,    11);
    check("SUB  4-2=2 (fwd[11])  [12]",  V_2,    12);

    $display("-- Section 2: MUL chain with forwarding --");
    check("MUL  1*2=2             [13]",  V_2,    13);
    check("MUL  2*2=4 (fwd[13])  [14]",  V_4,    14);

    $display("-- Section 3: DIV + forwarding after long stall --");
    check_div      ("DIV  4/2=2            [15]", V_2, 15);
    check_after_div("ADD  (DIV result)+1=3 [16]", V_3, 16);

    $display("-- Section 4: SQRT + forwarding after long stall --");
    check_sqrt      ("SQRT sqrt(4)=2         [17]", V_SQRT_2,   17);
    check_after_sqrt("ADD  (SQRT result)+2=4 [18]", V_SQRT_FWD, 18);

    $display("-- Section 5: Unary ops with forwarding --");
    check("NEG  -2.0              [19]",  V_NEG2, 19);
    check("ABS  |-2|=2 (fwd[19]) [20]",  V_2,    20);
    check("MOV  1.0               [21]",  V_1,    21);
    check("RELU max(0,-2)=0       [22]",  V_0,    22);
    check("RELU max(0,1)=1        [23]",  V_1,    23);

    $display("-- Section 6: Quire/accumulator --");
    check_qacc("QACC 1+4-2->neg->+4=1 [24]", V_1, 24);

    $display("-- Section 7: Zero operand tests --");
    check("ADD  0+0=0             [30]",  V_0,    30);
    check("MUL  0*2=0             [31]",  V_0,    31);
    check("MUL  1*0=0             [32]",  V_0,    32);

    $display("-- Section 8: NaR/NaN propagation --");
    if (ACCEL_TYPE == "PAU" || ACCEL_TYPE == "FLO_PAU") begin
      check("ADD  NaR+1=NaR        [40]",  V_NAR_PROP, 40);
      check("MUL  NaR*2=NaR        [41]",  V_NAR_PROP, 41);
      check("NEG  -NaR=NaR         [42]",  V_NAR,      42);
      check("ABS  |NaR|=NaR        [43]",  V_NAR,      43);
    end else begin
      // FPU: any NaN output counts as pass (NaN payload may differ)
      check_nan("ADD  NaN+1=NaN        [40]", 40);
      check_nan("MUL  NaN*2=NaN        [41]", 41);
      // NEG of NaN: just flips sign bit, still a NaN
      check_nan("NEG  -NaN=NaN         [42]", 42);
      // ABS of NaN: clears sign bit, still a NaN
      check_nan("ABS  |NaN|=NaN        [43]", 43);
    end

    $display("-- Section 9: Same-address WAW --");
    // d[0] was overwritten from 1.0 to 3.0 (ADD d[0],d[1]->d[0])
    check("WAW  d[0]=1+2=3        [50]",  V_3,    50);

    $display("-- Section 10: Back-to-back comb ops --");
    check("NEG  -2                 [51]", V_NEG2, 51);
    check("NEG  -(-2)=2 (fwd)     [52]", V_2,    52);
    check("ABS  |-2|=2  (fwd)     [53]", V_2,    53);
    check("RELU max(0,-2)=0 (fwd) [54]", V_0,    54);

    // ==================================================================
    // PROGRAM 2: Halt-then-restart with new program
    // Verifies sequencer resets PC and runs fresh instructions after HALT.
    // ==================================================================
    $display("-- Halt-then-restart --");

    // Restore d[0]=1.0 (was overwritten by WAW test)
    write_dbram(0, V_1[DATA_WIDTH-1:0]);

    // Write a short second program starting at address 0
    write_ibram(0, make_instr(OP_MUL,  20'd0, 20'd2, 20'd60)); // 1*4=4
    write_ibram(1, make_instr(OP_ADD,  20'd60,20'd0, 20'd61)); // 4+1=5
    write_ibram(2, make_instr(OP_HALT, 20'd0, 20'd0, 20'd0));

    repeat(3) @(posedge clk);

    $display("[%0t] Starting Program 2 (restart after HALT)...", $time);
    run_program();
    $display("[%0t] Program 2 done.", $time);

    check("MUL  1*4=4 (restart)   [60]", V_4, 60);
    check("ADD  4+1=5 (restart)   [61]", V_5, 61);

    // ==================================================================
    // PROGRAM 3: Max BRAM address
    // Write data to DATA_DEPTH-1, read it via MOV.
    // ==================================================================
    $display("-- Max BRAM address --");

    write_dbram(DATA_DEPTH-1, V_2[DATA_WIDTH-1:0]);  // 2.0 at max address

    write_ibram(0, make_instr(OP_MOV,  20'(DATA_DEPTH-1), 20'd0, 20'd70)); // d[70]=d[max]
    write_ibram(1, make_instr(OP_HALT, 20'd0, 20'd0, 20'd0));

    repeat(3) @(posedge clk);
    run_program();

    check("MOV  d[max]=2.0        [70]", V_2, 70);

    // ==================================================================
    // PROGRAM 4: Pipeline stress -- consecutive long-latency ops
    // Two back-to-back DIVs, then SQRT->DIV forwarding.
    // ==================================================================
    $display("-- Pipeline stress: consecutive DIV/SQRT --");

    // Restore d[0]=1.0 (may have been overwritten)
    write_dbram(0, V_1[DATA_WIDTH-1:0]);

    write_ibram(0, make_instr(OP_DIV,  20'd2,  20'd1,  20'd80)); // 4/2=2
    write_ibram(1, make_instr(OP_DIV,  20'd2,  20'd2,  20'd81)); // 4/4=1 (stalls behind [80])
    write_ibram(2, make_instr(OP_ADD,  20'd80, 20'd81, 20'd82)); // 2+1=3 (verifies both)
    write_ibram(3, make_instr(OP_SQRT, 20'd2,  20'd0,  20'd83)); // sqrt(4)=2
    write_ibram(4, make_instr(OP_DIV,  20'd83, 20'd0,  20'd84)); // 2/1=2 (fwd from SQRT)
    write_ibram(5, make_instr(OP_HALT, 20'd0,  20'd0,  20'd0));

    repeat(3) @(posedge clk);

    $display("[%0t] Starting Program 4 (pipeline stress)...", $time);
    run_program();
    $display("[%0t] Program 4 done.", $time);

    check_div      ("DIV  4/2=2 (b2b)              [80]", V_2, 80);
    check_div      ("DIV  4/4=1 (b2b)              [81]", V_1, 81);
    check_after_div("ADD  (DIV b2b)+( DIV b2b)=3   [82]", V_3, 82);
    check_sqrt     ("SQRT sqrt(4)=2                [83]", V_2, 83);
    check_div_of_sqrt("DIV  (SQRT result)/1=2      [84]", V_2, 84);

    // ==================================================================
    // PROGRAM 5: Quire accumulation stress test
    // Longer sequence: multiple QACC_ADD, QACC_MADD, QACC_MSUB, QACC_NEG.
    // Also tests QACC_NEG on a freshly cleared (zero) accumulator.
    // ==================================================================
    $display("-- Quire stress test --");

    // Need d[0]=1.0, d[1]=2.0, d[2]=4.0 (should already be set)
    // Also need d[5]=3.0 for QACC_MSUB(1, 3)
    write_dbram(0, V_1[DATA_WIDTH-1:0]);
    write_dbram(1, V_2[DATA_WIDTH-1:0]);
    write_dbram(5, V_3[DATA_WIDTH-1:0]);

    write_ibram( 0, make_instr(OP_QACC_CLEAR, 20'd0, 20'd0, 20'd0));
    write_ibram( 1, make_instr(OP_QACC_ADD,   20'd0, 20'd0, 20'd0)); // acc=1
    write_ibram( 2, make_instr(OP_QACC_ADD,   20'd0, 20'd0, 20'd0)); // acc=2
    write_ibram( 3, make_instr(OP_QACC_ADD,   20'd0, 20'd0, 20'd0)); // acc=3
    write_ibram( 4, make_instr(OP_QACC_MADD,  20'd1, 20'd1, 20'd0)); // acc=3+4=7
    write_ibram( 5, make_instr(OP_QACC_MADD,  20'd1, 20'd1, 20'd0)); // acc=7+4=11
    write_ibram( 6, make_instr(OP_QACC_MSUB,  20'd0, 20'd5, 20'd0)); // acc=11-3=8
    write_ibram( 7, make_instr(OP_QACC_NEG,   20'd0, 20'd0, 20'd0)); // acc=-8
    write_ibram( 8, make_instr(OP_QACC_MADD,  20'd5, 20'd5, 20'd0)); // acc=-8+9=1
    write_ibram( 9, make_instr(OP_QACC_READ,  20'd0, 20'd0, 20'd90));// d[90]=1
    // Test QACC_NEG on zero accumulator
    write_ibram(10, make_instr(OP_QACC_CLEAR, 20'd0, 20'd0, 20'd0));
    write_ibram(11, make_instr(OP_QACC_NEG,   20'd0, 20'd0, 20'd0)); // acc=-0=0
    write_ibram(12, make_instr(OP_QACC_READ,  20'd0, 20'd0, 20'd91));// d[91]=0
    write_ibram(13, make_instr(OP_HALT,        20'd0, 20'd0, 20'd0));

    repeat(3) @(posedge clk);

    $display("[%0t] Starting Program 5 (quire stress)...", $time);
    run_program();
    $display("[%0t] Program 5 done.", $time);

    check_qacc("QACC 3*ADD+2*MADD-MSUB-NEG+MADD=1 [90]", V_1, 90);
    check_qacc("QACC NEG(0)=0                      [91]", V_0, 91);

    // ==================================================================
    // PROGRAM 6: Instruction BRAM saturation
    // Fill all INSTR_DEPTH slots with MOVs, real op near end, HALT at last slot.
    // ==================================================================
    $display("-- Instruction BRAM saturation --");

    // Restore d[0]=1.0, d[1]=2.0
    write_dbram(0, V_1[DATA_WIDTH-1:0]);
    write_dbram(1, V_2[DATA_WIDTH-1:0]);

    for (int i = 0; i < INSTR_DEPTH-2; i++)
      write_ibram(i, make_instr(OP_MOV, 20'd0, 20'd0, 20'd0)); // NOP-like: MOV d[0]->d[0]
    write_ibram(INSTR_DEPTH-2, make_instr(OP_ADD, 20'd0, 20'd1, 20'd95)); // 1+2=3
    write_ibram(INSTR_DEPTH-1, make_instr(OP_HALT, 20'd0, 20'd0, 20'd0));

    repeat(3) @(posedge clk);

    $display("[%0t] Starting Program 6 (BRAM saturation, %0d instrs)...", $time, INSTR_DEPTH);
    run_program();
    $display("[%0t] Program 6 done.", $time);

    check("ADD 1+2=3 at INSTR_DEPTH-2 [95]", V_3, 95);

    // ==================================================================
    // PROGRAM 7: QACC_NEG double-fire regression
    // Verifies that two back-to-back QACC_NEG calls negate twice (net = identity)
    // rather than cancelling out (which would be the symptom of the double-fire
    // bug where operator_delay holds QNEG for an extra cycle without gating).
    //
    // For PAU QUIRE_MODE="QUIRE" this exercises the pau_top QNEG gate.
    // For no-quire PAU and FPU this exercises arith_unit's acc_q NEG path.
    // ==================================================================
    $display("-- QACC_NEG double-fire regression --");

    write_dbram(0, V_1[DATA_WIDTH-1:0]);
    write_dbram(1, V_2[DATA_WIDTH-1:0]);

    // Single NEG: acc starts 0, add 2.0, negate -> expect -2.0
    write_ibram(0, make_instr(OP_QACC_CLEAR, 20'd0, 20'd0, 20'd0));
    write_ibram(1, make_instr(OP_QACC_ADD,   20'd1, 20'd0, 20'd0)); // acc = 2.0
    write_ibram(2, make_instr(OP_QACC_NEG,   20'd0, 20'd0, 20'd0)); // acc = -2.0
    write_ibram(3, make_instr(OP_QACC_READ,  20'd0, 20'd0, 20'd96)); // d[96] = -2.0

    // Double NEG: accumulate 2.0, negate twice -> expect +2.0
    write_ibram(4, make_instr(OP_QACC_CLEAR, 20'd0, 20'd0, 20'd0));
    write_ibram(5, make_instr(OP_QACC_ADD,   20'd1, 20'd0, 20'd0)); // acc = 2.0
    write_ibram(6, make_instr(OP_QACC_NEG,   20'd0, 20'd0, 20'd0)); // acc = -2.0
    write_ibram(7, make_instr(OP_QACC_NEG,   20'd0, 20'd0, 20'd0)); // acc = 2.0 (double-neg)
    write_ibram(8, make_instr(OP_QACC_READ,  20'd0, 20'd0, 20'd97)); // d[97] = 2.0

    write_ibram(9, make_instr(OP_HALT, 20'd0, 20'd0, 20'd0));

    repeat(3) @(posedge clk);

    $display("[%0t] Starting Program 7 (QACC_NEG regression)...", $time);
    run_program();
    $display("[%0t] Program 7 done.", $time);

    check_qacc("QACC_NEG:   acc=2, neg->-2      [96]", V_NEG2, 96);
    check_qacc("QACC_NEGx2: acc=2, neg,neg->+2  [97]", V_2,    97);

    // ==================================================================
    // PROGRAM 8: QMADD/QMSUB single-cycle accumulator
    // Specifically validates the flo_posit_top nacc_q path for PAU-8/16 no-quire.
    // Correct for all configs (quire-present PAU and FPU also produce exact results).
    //
    // Sequence:
    //   QCLR: acc = 0
    //   QMADD(d[1]=2, d[0]=1): acc = 2*1 + 0 = 2
    //   QMADD(d[1]=2, d[0]=1): acc = 2*1 + 2 = 4   -> QROUND -> d[100] = V_4
    //   QMSUB(d[1]=2, d[0]=1): acc = 4 - 2*1 = 2   -> QROUND -> d[101] = V_2
    // ==================================================================
    $display("-- QMADD/QMSUB accumulator (PAU-8/16 no-quire focus) --");

    write_dbram(0, V_1[DATA_WIDTH-1:0]);
    write_dbram(1, V_2[DATA_WIDTH-1:0]);

    write_ibram(0, make_instr(OP_QACC_CLEAR, 20'd0, 20'd0, 20'd0));
    write_ibram(1, make_instr(OP_QACC_MADD,  20'd1, 20'd0, 20'd0)); // acc = 2*1+0 = 2
    write_ibram(2, make_instr(OP_QACC_MADD,  20'd1, 20'd0, 20'd0)); // acc = 2*1+2 = 4
    write_ibram(3, make_instr(OP_QACC_READ,  20'd0, 20'd0, 20'd100)); // d[100] = 4
    write_ibram(4, make_instr(OP_QACC_MSUB,  20'd1, 20'd0, 20'd0)); // acc = 4-2*1 = 2
    write_ibram(5, make_instr(OP_QACC_READ,  20'd0, 20'd0, 20'd101)); // d[101] = 2
    write_ibram(6, make_instr(OP_HALT,        20'd0, 20'd0, 20'd0));

    repeat(3) @(posedge clk);

    $display("[%0t] Starting Program 8 (QMADD/QMSUB accumulator)...", $time);
    run_program();
    $display("[%0t] Program 8 done.", $time);

    check_qacc("QMADDx2: 2*1+0, 2*1+2=4 [100]", V_4, 100);
    check_qacc("QMSUB:   4-2*1=2         [101]", V_2, 101);

    // -- Summary ---------------------------------------------------------
    $display("===================================================================");
    $display("Results: %0d passed, %0d failed  (%s-%0d quire=%s mul=%s div=%s sqrt=%s)",
             pass_count, fail_count,
             ACCEL_TYPE, DATA_WIDTH, QUIRE_MODE, MUL_MODE, DIV_MODE, SQRT_MODE);
    if (fail_count > 0)
      $display("FAIL: %0d test(s) failed", fail_count);
    else
      $display("PASS: all tests passed");
    $display("===================================================================");

    $finish;
  end

  // Watchdog
  initial begin
    #50_000_000;
    $display("TIMEOUT: simulation did not complete");
    $finish;
  end

endmodule
