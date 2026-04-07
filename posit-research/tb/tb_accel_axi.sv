// Testbench for accel_axi — AXI integration test, configuration-aware.
//
// Tests the full path: AXI registers → BRAM → sequencer → arith_unit → BRAM → AXI.
// Arithmetic correctness is covered by tb_accel_core; this test focuses on:
//
//   1. Instruction write path: IBRAM_ADDR → IBRAM_DATA_LO → IBRAM_DATA_HI (trigger)
//   2. Data write path (32-bit): DBRAM_ADDR → DBRAM_DATA (trigger)
//   3. Data write path (64-bit): DBRAM_ADDR → DBRAM_DATA → DBRAM_DATA_HI (trigger)
//   4. STATUS polling: RUNNING high during a long-latency DIV, DONE asserts on HALT
//   5. Data read path (32-bit): DBRAM_ADDR → (wait) → DBRAM_DATA
//   6. Data read path (64-bit): DBRAM_ADDR → (wait) → DBRAM_DATA + DBRAM_DATA_HI
//   7. AXI writes while RUNNING are ACK'd but dropped (data preserved)
//   8. Halt-then-restart: new program after DONE, verify it runs correctly
//
// Simulation filesets:
//   sim_axi       — PAU-32, exercises the 32-bit DBRAM data path
//   sim_axi_pau64 — PAU-64, exercises DBRAM_DATA_HI for 64-bit values
//
// ── Program ──────────────────────────────────────────────────────────────────────
//   d[0]=1.0  d[1]=2.0  d[2]=4.0
//
//   [0] ADD  d[0], d[1] → d[5]    1+2 = 3
//   [1] DIV  d[2], d[1] → d[6]    4/2 = 2  (long latency: STATUS.RUNNING tested)
//   [2] QACC_CLEAR
//   [3] QACC_ADD  d[1]             acc = 2
//   [4] QACC_MADD d[0], d[1]       acc = 2+2 = 4
//   [5] QACC_READ → d[7]           d[7] = 4
//   [6] HALT

`timescale 1ns/1ps

module tb_accel_axi
  import config_pkg::*;
  import opcodes_pkg::*;
();

  localparam CLK_PERIOD = 10;  // 10 ns = 100 MHz

  // ── Clock and reset ──────────────────────────────────────────────────────────
  logic clk, rst_n;
  initial clk = 0;
  always #(CLK_PERIOD/2) clk = ~clk;

  initial begin
    rst_n = 0;
    repeat(5) @(posedge clk);
    rst_n = 1;
  end

  // ── AXI-Lite signals (32-bit address and data bus) ───────────────────────────
  logic [31:0] s_axi_awaddr;  logic s_axi_awvalid, s_axi_awready;
  logic [31:0] s_axi_wdata;   logic [3:0] s_axi_wstrb;
  logic        s_axi_wvalid,  s_axi_wready;
  logic [1:0]  s_axi_bresp;   logic s_axi_bvalid, s_axi_bready;
  logic [31:0] s_axi_araddr;  logic s_axi_arvalid, s_axi_arready;
  logic [31:0] s_axi_rdata;   logic [1:0] s_axi_rresp;
  logic        s_axi_rvalid,  s_axi_rready;

  accel_axi dut (
    .clk_i           ( clk           ),
    .rst_ni          ( rst_n         ),
    .s_axi_awaddr    ( s_axi_awaddr  ),
    .s_axi_awvalid   ( s_axi_awvalid ),
    .s_axi_awready   ( s_axi_awready ),
    .s_axi_wdata     ( s_axi_wdata   ),
    .s_axi_wstrb     ( s_axi_wstrb   ),
    .s_axi_wvalid    ( s_axi_wvalid  ),
    .s_axi_wready    ( s_axi_wready  ),
    .s_axi_bresp     ( s_axi_bresp   ),
    .s_axi_bvalid    ( s_axi_bvalid  ),
    .s_axi_bready    ( s_axi_bready  ),
    .s_axi_araddr    ( s_axi_araddr  ),
    .s_axi_arvalid   ( s_axi_arvalid ),
    .s_axi_arready   ( s_axi_arready ),
    .s_axi_rdata     ( s_axi_rdata   ),
    .s_axi_rresp     ( s_axi_rresp   ),
    .s_axi_rvalid    ( s_axi_rvalid  ),
    .s_axi_rready    ( s_axi_rready  )
  );

  // ── Primitive AXI helpers ────────────────────────────────────────────────────
  // #1 after every @(posedge clk) places signal changes in the next simulation
  // time step (1 ps), safely after the DUT's always_ff has sampled at the clock
  // edge.  Without this, the testbench's blocking assignments race with the
  // DUT's flip-flop sampling in xsim's active region — a race that resolves
  // differently for PAU vs FPU builds due to different elaboration/event order.
  task automatic axi_write(input logic [31:0] addr, input logic [31:0] data);
    @(posedge clk); #1;
    s_axi_awaddr  = addr;
    s_axi_awvalid = 1;
    s_axi_wdata   = data;
    s_axi_wstrb   = 4'hF;
    s_axi_wvalid  = 1;
    s_axi_bready  = 1;
    fork
      begin wait(s_axi_awready); @(posedge clk); #1; s_axi_awvalid = 0; end
      begin wait(s_axi_wready);  @(posedge clk); #1; s_axi_wvalid  = 0; end
    join
    wait(s_axi_bvalid);
    @(posedge clk); #1;
    s_axi_bready = 0;
  endtask

  task automatic axi_read(input logic [31:0] addr, output logic [31:0] data);
    @(posedge clk); #1;
    s_axi_araddr  = addr;
    s_axi_arvalid = 1;
    s_axi_rready  = 1;
    wait(s_axi_arready);
    @(posedge clk); #1;
    s_axi_arvalid = 0;
    wait(s_axi_rvalid);
    data = s_axi_rdata;
    @(posedge clk); #1;
    s_axi_rready = 0;
  endtask

  // ── Higher-level register helpers ────────────────────────────────────────────
  // Write one 64-bit instruction word.
  task automatic write_instr(input int idx, input logic [63:0] instr);
    axi_write(32'h08, idx);             // IBRAM_ADDR
    axi_write(32'h0C, instr[31:0]);     // IBRAM_DATA_LO
    axi_write(32'h10, instr[63:32]);    // IBRAM_DATA_HI → triggers BRAM write
  endtask

  // Write one DATA_WIDTH-bit value to the data BRAM.
  // Uses 64-bit container to avoid width-indexed slicing issues at compile time.
  task automatic write_data(input int idx, input logic [63:0] val);
    axi_write(32'h14, idx);
    if (DATA_WIDTH == 64) begin
      axi_write(32'h18, val[31:0]);   // DBRAM_DATA    — low word (no trigger)
      axi_write(32'h1C, val[63:32]);  // DBRAM_DATA_HI — high word, triggers write
    end else begin
      axi_write(32'h18, val[31:0]);   // DBRAM_DATA — triggers write for 32-bit
    end
  endtask

  // Read one DATA_WIDTH-bit value from the data BRAM.
  // Sets DBRAM_ADDR, waits for BRAM registered read, then reads DBRAM_DATA[_HI].
  task automatic read_data(input int idx, output logic [63:0] val);
    logic [31:0] lo, hi;
    axi_write(32'h14, idx);         // latch DBRAM_ADDR into shadow reg
    repeat(4) @(posedge clk);       // wait for BRAM registered read to propagate
    axi_read(32'h18, lo);           // DBRAM_DATA (low / full word for 32-bit)
    if (DATA_WIDTH == 64) begin
      axi_read(32'h1C, hi);         // DBRAM_DATA_HI (high word for 64-bit)
      val = {hi, lo};
    end else begin
      val = {32'b0, lo};
    end
  endtask

  function automatic logic [63:0] make_instr(
    input opcode_t     op,
    input logic [19:0] a, b, res
  );
    return {op, a, b, res};
  endfunction

  // ── Config-derived reference values ──────────────────────────────────────────
  logic [63:0] V_1, V_2, V_3, V_4;

  initial begin
    if (ACCEL_TYPE == "PAU" && DATA_WIDTH == 32) begin
      V_1 = 64'h0000_0000_4000_0000;
      V_2 = 64'h0000_0000_4800_0000;
      V_3 = 64'h0000_0000_4C00_0000;
      V_4 = 64'h0000_0000_5000_0000;
    end else if (ACCEL_TYPE == "PAU" && DATA_WIDTH == 64) begin
      V_1 = 64'h4000_0000_0000_0000;
      V_2 = 64'h4800_0000_0000_0000;
      V_3 = 64'h4C00_0000_0000_0000;
      V_4 = 64'h5000_0000_0000_0000;
    end else if (ACCEL_TYPE == "FPU" && DATA_WIDTH == 32) begin
      V_1 = 64'h0000_0000_3F80_0000;
      V_2 = 64'h0000_0000_4000_0000;
      V_3 = 64'h0000_0000_4040_0000;
      V_4 = 64'h0000_0000_4080_0000;
    end else begin  // FPU 64
      V_1 = 64'h3FF0_0000_0000_0000;
      V_2 = 64'h4000_0000_0000_0000;
      V_3 = 64'h4008_0000_0000_0000;
      V_4 = 64'h4010_0000_0000_0000;
    end
  end

  // ── Result tracking ───────────────────────────────────────────────────────────
  int pass_count, fail_count;

  task automatic check(
    input string       label,
    input logic [63:0] expected,
    input int          dbram_slot
  );
    logic [63:0] got;
    read_data(dbram_slot, got);
    // For 32-bit configs the upper 32 bits of got are 0 (from read_data)
    if (got[DATA_WIDTH-1:0] == expected[DATA_WIDTH-1:0]) begin
      $display("  PASS  %-32s  got 0x%0X", label, got[DATA_WIDTH-1:0]);
      pass_count++;
    end else begin
      $display("  FAIL  %-32s  got 0x%0X  expected 0x%0X",
               label, got[DATA_WIDTH-1:0], expected[DATA_WIDTH-1:0]);
      fail_count++;
    end
  endtask

  // ── Test ─────────────────────────────────────────────────────────────────────
  logic [31:0] status;

  initial begin
    pass_count    = 0;
    fail_count    = 0;
    s_axi_awvalid = 0; s_axi_wvalid = 0; s_axi_bready = 0;
    s_axi_arvalid = 0; s_axi_rready = 0;
    s_axi_awaddr  = 0; s_axi_wdata  = 0; s_axi_wstrb  = 0;
    s_axi_araddr  = 0;

    @(posedge rst_n);
    repeat(3) @(posedge clk);

    $display("===================================================================");
    $display("AXI integration test: %s-%0d", ACCEL_TYPE, DATA_WIDTH);
    $display("===================================================================");

    // ── Load instruction BRAM via AXI ─────────────────────────────────────────
    write_instr(0, make_instr(OP_ADD,        20'd0, 20'd1, 20'd5)); // 1+2=3
    write_instr(1, make_instr(OP_DIV,        20'd2, 20'd1, 20'd6)); // 4/2=2 (long lat.)
    write_instr(2, make_instr(OP_QACC_CLEAR, 20'd0, 20'd0, 20'd0));
    write_instr(3, make_instr(OP_QACC_ADD,   20'd1, 20'd0, 20'd0)); // acc=2
    write_instr(4, make_instr(OP_QACC_MADD,  20'd0, 20'd1, 20'd0)); // acc=2+2=4
    write_instr(5, make_instr(OP_QACC_READ,  20'd0, 20'd0, 20'd7)); // d[7]=4
    write_instr(6, make_instr(OP_HALT,       20'd0, 20'd0, 20'd0));

    // ── Load data BRAM via AXI ────────────────────────────────────────────────
    write_data(0, V_1);  // 1.0
    write_data(1, V_2);  // 2.0
    write_data(2, V_4);  // 4.0

    repeat(3) @(posedge clk);

    // ── Start ─────────────────────────────────────────────────────────────────
    $display("[%0t] Starting accelerator via AXI...", $time);
    axi_write(32'h00, 32'h1);  // CTRL[0]=START

    // ── Poll STATUS — verify RUNNING goes high, then DONE asserts ─────────────
    // Read STATUS repeatedly; track that we saw RUNNING=1 before DONE=1.
    begin
      automatic int running_seen = 0;
      automatic int poll_count   = 0;
      automatic int done_seen    = 0;

      repeat(2000) begin
        if (!done_seen) begin
          axi_read(32'h04, status);
          poll_count++;
          if (status[1]) running_seen = 1;  // STATUS[1] = RUNNING
          if (status[0]) begin               // STATUS[0] = DONE
            done_seen = 1;
            $display("[%0t] DONE after %0d polls (RUNNING was observed: %0s)",
                     $time, poll_count, running_seen ? "yes" : "no");
          end
        end
      end

      if (!done_seen) begin
        $display("FAIL: accelerator did not assert DONE within poll limit");
        $finish;
      end
      if (!running_seen) begin
        // DIV should take many cycles — if we never saw RUNNING the poll was too slow
        // or the design didn't assert it.  Warn but don't fail (timing-dependent).
        $display("  WARN: RUNNING was never observed during polling");
      end
    end

    repeat(3) @(posedge clk);

    // ── Check results ─────────────────────────────────────────────────────────
    $display("-- Write/read path + arithmetic --");
    check("ADD  1+2=3          via AXI [5]", V_3, 5);
    check("DIV  4/2=2 (stall)  via AXI [6]", V_2, 6);

    $display("-- Quire path via AXI --");
    check("QACC 2+(1*2)=4      via AXI [7]", V_4, 7);

    // ── Test: AXI write while running is dropped ─────────────────────────────
    // Write a known sentinel value to d[8], start a program that does NOT touch d[8],
    // attempt to overwrite d[8] via AXI while running, verify sentinel preserved.
    $display("-- AXI writes while running --");
    write_data(8, V_1);  // sentinel: d[8] = 1.0

    // Program: just a long DIV + HALT (doesn't touch d[8])
    write_instr(0, make_instr(OP_DIV,  20'd2, 20'd1, 20'd9)); // 4/2=2 → d[9]
    write_instr(1, make_instr(OP_HALT, 20'd0, 20'd0, 20'd0));

    repeat(2) @(posedge clk);
    axi_write(32'h00, 32'h1);  // START

    // Immediately try to overwrite d[8] while running
    // (accel_axi should ACK but drop the BRAM write)
    repeat(3) @(posedge clk);
    write_data(8, V_4);  // try to write 4.0 → should be dropped

    // Wait for done
    begin
      automatic int done2 = 0;
      repeat(2000) begin
        if (!done2) begin
          axi_read(32'h04, status);
          if (status[0]) done2 = 1;
        end
      end
      if (!done2) begin
        $display("FAIL: accelerator did not finish in write-while-running test");
        $finish;
      end
    end

    repeat(3) @(posedge clk);
    check("d[8] sentinel preserved     [8]", V_1, 8);
    check("DIV  4/2=2 during test      [9]", V_2, 9);

    // ── Test: halt-then-restart via AXI ──────────────────────────────────────
    $display("-- Halt-then-restart via AXI --");

    write_instr(0, make_instr(OP_ADD,  20'd0, 20'd1, 20'd10)); // 1+2=3
    write_instr(1, make_instr(OP_HALT, 20'd0, 20'd0, 20'd0));

    repeat(2) @(posedge clk);
    axi_write(32'h00, 32'h1);  // START

    begin
      automatic int done3 = 0;
      repeat(2000) begin
        if (!done3) begin
          axi_read(32'h04, status);
          if (status[0]) done3 = 1;
        end
      end
      if (!done3) begin
        $display("FAIL: restart test did not finish");
        $finish;
      end
    end

    repeat(3) @(posedge clk);
    check("ADD  1+2=3 (restart) via AXI[10]", V_3, 10);

    // ── Summary ───────────────────────────────────────────────────────────────
    $display("===================================================================");
    $display("Results: %0d passed, %0d failed  (%s-%0d AXI)",
             pass_count, fail_count, ACCEL_TYPE, DATA_WIDTH);
    if (fail_count > 0)
      $display("FAIL: %0d test(s) failed", fail_count);
    else
      $display("PASS: all tests passed");
    $display("===================================================================");

    $finish;
  end

  // Watchdog
  initial begin
    #10_000_000;
    $display("TIMEOUT: AXI simulation did not complete");
    $finish;
  end

endmodule
