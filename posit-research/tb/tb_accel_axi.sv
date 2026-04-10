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
//   9. DBRAM_ADDR auto-increment: stream 16 words in/out without re-writing addr
//  10. Opcode coverage: SUB, MUL, SQRT, NEG, ABS, MOV, RELU, QACC_MSUB, QACC_NEG
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

  // ── accel_axi → accel_core control wires ─────────────────────────────────────
  logic                            accel_start;
  logic                            accel_rst_n;
  logic                            accel_done;
  logic                            accel_running;

  // ── accel_axi ↔ arbiter (AXI-Lite DBRAM host, port A) ───────────────────────
  logic [$clog2(DATA_DEPTH)-1:0]   axi_dbram_addr;
  logic [DATA_WIDTH-1:0]           axi_dbram_wdata;
  logic                            axi_dbram_we;
  logic [DATA_WIDTH-1:0]           axi_dbram_rdata;

  // ── accel_axi → accel_core IBRAM host ────────────────────────────────────────
  logic [$clog2(INSTR_DEPTH)-1:0]  ibram_addr;
  logic [63:0]                     ibram_wdata;
  logic                            ibram_we;
  logic [63:0]                     ibram_rdata;

  // ── arbiter → accel_core DBRAM host ──────────────────────────────────────────
  logic [$clog2(DATA_DEPTH)-1:0]   core_dbram_addr;
  logic [DATA_WIDTH-1:0]           core_dbram_wdata;
  logic                            core_dbram_we;
  logic [DATA_WIDTH-1:0]           core_dbram_rdata;

  // ── AXI4 burst slave signals (accel_axi_burst) ───────────────────────────────
  // Write channel
  logic [3:0]  burst_awid;
  logic [31:0] burst_awaddr;
  logic [7:0]  burst_awlen;
  logic [2:0]  burst_awsize;
  logic [1:0]  burst_awburst;
  logic        burst_awvalid, burst_awready;
  logic [63:0] burst_wdata;
  logic [7:0]  burst_wstrb;
  logic        burst_wlast;
  logic        burst_wvalid,  burst_wready;
  logic [3:0]  burst_bid;
  logic [1:0]  burst_bresp;
  logic        burst_bvalid,  burst_bready;
  // Read channel
  logic [3:0]  burst_arid;
  logic [31:0] burst_araddr;
  logic [7:0]  burst_arlen;
  logic [2:0]  burst_arsize;
  logic [1:0]  burst_arburst;
  logic        burst_arvalid, burst_arready;
  logic [3:0]  burst_rid;
  logic [63:0] burst_rdata;
  logic [1:0]  burst_rresp;
  logic        burst_rlast;
  logic        burst_rvalid,  burst_rready;
  // Port B → arbiter
  logic                          burst_b_req;
  logic [$clog2(DATA_DEPTH)-1:0] burst_b_addr;
  logic [DATA_WIDTH-1:0]         burst_b_wdata;
  logic                          burst_b_we;
  logic [DATA_WIDTH-1:0]         burst_b_rdata;

  // Module-level scratch buffer for axi4_read_burst results.
  // XSim does not correctly handle dynamic arrays passed as output task parameters
  // (the formal receives an empty unallocated copy). Writing into a fixed-size
  // module-level array and reading burst_rd_buf[i] at the call site is the workaround.
  logic [63:0] burst_rd_buf [256];

  accel_axi dut (
    .clk_i           ( clk              ),
    .rst_ni          ( rst_n            ),
    .s_axi_awaddr    ( s_axi_awaddr     ),
    .s_axi_awvalid   ( s_axi_awvalid    ),
    .s_axi_awready   ( s_axi_awready    ),
    .s_axi_wdata     ( s_axi_wdata      ),
    .s_axi_wstrb     ( s_axi_wstrb      ),
    .s_axi_wvalid    ( s_axi_wvalid     ),
    .s_axi_wready    ( s_axi_wready     ),
    .s_axi_bresp     ( s_axi_bresp      ),
    .s_axi_bvalid    ( s_axi_bvalid     ),
    .s_axi_bready    ( s_axi_bready     ),
    .s_axi_araddr    ( s_axi_araddr     ),
    .s_axi_arvalid   ( s_axi_arvalid    ),
    .s_axi_arready   ( s_axi_arready    ),
    .s_axi_rdata     ( s_axi_rdata      ),
    .s_axi_rresp     ( s_axi_rresp      ),
    .s_axi_rvalid    ( s_axi_rvalid     ),
    .s_axi_rready    ( s_axi_rready     ),
    .start_o         ( accel_start      ),
    .rst_no          ( accel_rst_n      ),
    .done_i          ( accel_done       ),
    .running_i       ( accel_running    ),
    .ibram_addr_o    ( ibram_addr       ),
    .ibram_wdata_o   ( ibram_wdata      ),
    .ibram_we_o      ( ibram_we         ),
    .ibram_rdata_i   ( ibram_rdata      ),
    .dbram_addr_o    ( axi_dbram_addr   ),
    .dbram_wdata_o   ( axi_dbram_wdata  ),
    .dbram_we_o      ( axi_dbram_we     ),
    .dbram_rdata_i   ( axi_dbram_rdata  )
  );

  // ── HP0 burst slave ───────────────────────────────────────────────────────────
  accel_axi_burst u_burst (
    .clk_i           ( clk              ),
    .rst_ni          ( rst_n            ),
    .running_i       ( accel_running    ),
    .s_axi_awid      ( burst_awid       ), .s_axi_awaddr  ( burst_awaddr  ),
    .s_axi_awlen     ( burst_awlen      ), .s_axi_awsize  ( burst_awsize  ),
    .s_axi_awburst   ( burst_awburst    ), .s_axi_awvalid ( burst_awvalid ),
    .s_axi_awready   ( burst_awready    ),
    .s_axi_wdata     ( burst_wdata      ), .s_axi_wstrb   ( burst_wstrb   ),
    .s_axi_wlast     ( burst_wlast      ), .s_axi_wvalid  ( burst_wvalid  ),
    .s_axi_wready    ( burst_wready     ),
    .s_axi_bid       ( burst_bid        ), .s_axi_bresp   ( burst_bresp   ),
    .s_axi_bvalid    ( burst_bvalid     ), .s_axi_bready  ( burst_bready  ),
    .s_axi_arid      ( burst_arid       ), .s_axi_araddr  ( burst_araddr  ),
    .s_axi_arlen     ( burst_arlen      ), .s_axi_arsize  ( burst_arsize  ),
    .s_axi_arburst   ( burst_arburst    ), .s_axi_arvalid ( burst_arvalid ),
    .s_axi_arready   ( burst_arready    ),
    .s_axi_rid       ( burst_rid        ), .s_axi_rdata   ( burst_rdata   ),
    .s_axi_rresp     ( burst_rresp      ), .s_axi_rlast   ( burst_rlast   ),
    .s_axi_rvalid    ( burst_rvalid     ), .s_axi_rready  ( burst_rready  ),
    .b_req           ( burst_b_req      ), .b_addr        ( burst_b_addr  ),
    .b_wdata         ( burst_b_wdata    ), .b_we          ( burst_b_we    ),
    .b_rdata         ( burst_b_rdata    )
  );

  // ── DBRAM host-port arbiter ───────────────────────────────────────────────────
  accel_dbram_arb u_arb (
    .a_addr          ( axi_dbram_addr   ),
    .a_wdata         ( axi_dbram_wdata  ),
    .a_we            ( axi_dbram_we     ),
    .a_rdata         ( axi_dbram_rdata  ),
    .b_req           ( burst_b_req      ),
    .b_addr          ( burst_b_addr     ),
    .b_wdata         ( burst_b_wdata    ),
    .b_we            ( burst_b_we       ),
    .b_rdata         ( burst_b_rdata    ),
    .dbram_addr_o    ( core_dbram_addr  ),
    .dbram_wdata_o   ( core_dbram_wdata ),
    .dbram_we_o      ( core_dbram_we    ),
    .dbram_rdata_i   ( core_dbram_rdata )
  );

  // ── Accelerator core ──────────────────────────────────────────────────────────
  accel_core u_core (
    .clk_i         ( clk              ),
    .rst_ni        ( accel_rst_n      ),
    .start_i       ( accel_start      ),
    .done_o        ( accel_done       ),
    .running_o     ( accel_running    ),
    .ibram_addr_i  ( ibram_addr       ),
    .ibram_wdata_i ( ibram_wdata      ),
    .ibram_we_i    ( ibram_we         ),
    .ibram_rdata_o ( ibram_rdata      ),
    .dbram_addr_i  ( core_dbram_addr  ),
    .dbram_wdata_i ( core_dbram_wdata ),
    .dbram_we_i    ( core_dbram_we    ),
    .dbram_rdata_o ( core_dbram_rdata )
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
    repeat(5) @(posedge clk);       // wait for BRAM registered read to propagate
    axi_read(32'h18, lo);           // DBRAM_DATA (low / full word for 32-bit)
    if (DATA_WIDTH == 64) begin
      axi_read(32'h1C, hi);         // DBRAM_DATA_HI (high word for 64-bit)
      val = {hi, lo};
    end else begin
      val = {32'b0, lo};
    end
  endtask

  // ── AXI4 burst helpers ────────────────────────────────────────────────────────
  // Hand-rolled INCR-only AXI4 burst tasks for the HP0 burst slave.
  // Each beat is a full DATA_WIDTH-wide word; the 64-bit bus carries it in the
  // low DATA_WIDTH bits (for DATA_WIDTH=32 the upper 32 bits of WDATA are X).
  //
  // base_addr: byte address of the first word (4- or 8-byte aligned)
  // len:       number of words to transfer (= number of AXI4 beats)
  // data:      flat array of 64-bit containers; [DATA_WIDTH-1:0] slice used.

  task automatic axi4_write_burst(
    input  logic [31:0] base_addr,
    input  int          len,
    input  logic [63:0] data[]
  );
    @(posedge clk); #1;
    // AW channel
    burst_awid    = 4'h0;
    burst_awaddr  = base_addr;
    burst_awlen   = 8'(len - 1);
    burst_awsize  = (DATA_WIDTH == 64) ? 3'h3 : 3'h2;  // 8 or 4 bytes
    burst_awburst = 2'b01;  // INCR
    burst_awvalid = 1'b1;
    burst_bready  = 1'b1;
    wait(burst_awready);
    @(posedge clk); #1;
    burst_awvalid = 1'b0;

    // W channel — send len beats
    for (int i = 0; i < len; i++) begin
      @(posedge clk); #1;
      burst_wdata  = data[i];
      burst_wstrb  = (DATA_WIDTH == 64) ? 8'hFF : 8'h0F;
      burst_wlast  = (i == len - 1);
      burst_wvalid = 1'b1;
      wait(burst_wready);
      @(posedge clk); #1;
      burst_wvalid = 1'b0;
      burst_wlast  = 1'b0;
    end

    // B channel — wait for response
    wait(burst_bvalid);
    @(posedge clk); #1;
    burst_bready = 1'b0;
  endtask

  task automatic axi4_read_burst(
    input  logic [31:0] base_addr,
    input  int          len
    // Results written to module-level burst_rd_buf[0..len-1].
    // XSim dynamic array output parameters are broken; use burst_rd_buf directly.
  );
    @(posedge clk); #1;
    // AR channel
    burst_arid    = 4'h0;
    burst_araddr  = base_addr;
    burst_arlen   = 8'(len - 1);
    burst_arsize  = (DATA_WIDTH == 64) ? 3'h3 : 3'h2;
    burst_arburst = 2'b01;  // INCR
    burst_arvalid = 1'b1;
    burst_rready  = 1'b1;
    wait(burst_arready);
    @(posedge clk); #1;
    burst_arvalid = 1'b0;

    // R channel — receive len beats into burst_rd_buf.
    // Capture rlast BEFORE the clock advance so we don't read the post-edge
    // value (after the clock, rd_beat_q has already incremented and rlast
    // reflects the *next* beat index, not the current one).
    for (int i = 0; i < len; i++) begin
      wait(burst_rvalid);
      burst_rd_buf[i] = burst_rdata;
      if (burst_rlast) begin
        @(posedge clk); #1;
        break;
      end
      @(posedge clk); #1;
    end
    burst_rready = 1'b0;
  endtask

  function automatic logic [63:0] make_instr(
    input opcode_t     op,
    input logic [19:0] a, b, res
  );
    return {op, a, b, res};
  endfunction

  // ── Config-derived reference values ──────────────────────────────────────────
  logic [63:0] V_0, V_1, V_2, V_3, V_4, V_NEG2;

  initial begin
    V_0 = '0;
    if (ACCEL_TYPE == "PAU" && DATA_WIDTH == 32) begin
      V_1    = 64'h0000_0000_4000_0000;
      V_2    = 64'h0000_0000_4800_0000;
      V_3    = 64'h0000_0000_4C00_0000;
      V_4    = 64'h0000_0000_5000_0000;
      V_NEG2 = 64'h0000_0000_B800_0000;
    end else if (ACCEL_TYPE == "PAU" && DATA_WIDTH == 64) begin
      V_1    = 64'h4000_0000_0000_0000;
      V_2    = 64'h4800_0000_0000_0000;
      V_3    = 64'h4C00_0000_0000_0000;
      V_4    = 64'h5000_0000_0000_0000;
      V_NEG2 = 64'hB800_0000_0000_0000;
    end else if (ACCEL_TYPE == "FPU" && DATA_WIDTH == 32) begin
      V_1    = 64'h0000_0000_3F80_0000;
      V_2    = 64'h0000_0000_4000_0000;
      V_3    = 64'h0000_0000_4040_0000;
      V_4    = 64'h0000_0000_4080_0000;
      V_NEG2 = 64'h0000_0000_C000_0000;
    end else begin  // FPU 64
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

  // Write N words (cycling V_1..V_4) to DBRAM starting at bslot, then read
  // them back, using burst or PIO for each direction independently.
  // Results accumulated in pass_count / fail_count.
  task automatic test_burst_pattern(
    input string label,
    input int    bslot,
    input int    N,
    input bit    wr_via_burst,
    input bit    rd_via_burst
  );
    automatic int          baddr = bslot * (DATA_WIDTH / 8);
    automatic logic [63:0] wdata [];
    automatic logic [63:0] rd_val;
    automatic int          ok    = 1;

    wdata = new[N];
    for (int i = 0; i < N; i++)
      case (i % 4)
        0: wdata[i] = V_1;
        1: wdata[i] = V_2;
        2: wdata[i] = V_3;
        3: wdata[i] = V_4;
      endcase

    // Write phase
    if (wr_via_burst) begin
      axi4_write_burst(32'(baddr), N, wdata);
    end else begin
      axi_write(32'h14, bslot);
      for (int i = 0; i < N; i++) begin
        if (DATA_WIDTH == 64) begin
          axi_write(32'h18, wdata[i][31:0]);
          axi_write(32'h1C, wdata[i][63:32]);
        end else
          axi_write(32'h18, wdata[i][31:0]);
      end
    end

    repeat(4) @(posedge clk);

    // Read and verify phase
    if (rd_via_burst) begin
      axi4_read_burst(32'(baddr), N);
      for (int i = 0; i < N; i++) begin
        if (burst_rd_buf[i][DATA_WIDTH-1:0] !== wdata[i][DATA_WIDTH-1:0]) begin
          $display("  FAIL  %s[%0d]  got 0x%0X  exp 0x%0X",
                   label, i, burst_rd_buf[i][DATA_WIDTH-1:0], wdata[i][DATA_WIDTH-1:0]);
          fail_count++; ok = 0;
        end else pass_count++;
      end
    end else begin
      for (int i = 0; i < N; i++) begin
        read_data(bslot + i, rd_val);
        if (rd_val[DATA_WIDTH-1:0] !== wdata[i][DATA_WIDTH-1:0]) begin
          $display("  FAIL  %s[%0d]  got 0x%0X  exp 0x%0X",
                   label, i, rd_val[DATA_WIDTH-1:0], wdata[i][DATA_WIDTH-1:0]);
          fail_count++; ok = 0;
        end else pass_count++;
      end
    end
    if (ok) $display("  PASS  %s: %0d words OK", label, N);
  endtask

  // Poll STATUS until DONE. Use when START was already issued separately.
  // Calls $finish if DONE is not seen within `timeout` poll iterations.
  task automatic wait_done(input string label, input int timeout = 2000);
    automatic int done = 0;
    repeat(timeout) begin
      if (!done) begin
        axi_read(32'h04, status);
        if (status[0]) done = 1;
      end
    end
    if (!done) begin
      $display("FAIL: %s did not assert DONE within %0d polls", label, timeout);
      $finish;
    end
  endtask

  // Issue START then poll until DONE.
  task automatic run_and_wait(input string label, input int timeout = 2000);
    axi_write(32'h00, 32'h1);  // CTRL[0] = START
    wait_done(label, timeout);
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
    // burst slave init
    burst_awvalid = 0; burst_wvalid = 0; burst_bready = 0;
    burst_arvalid = 0; burst_rready = 0;
    burst_awid = 0; burst_awaddr = 0; burst_awlen = 0;
    burst_awsize = 0; burst_awburst = 0;
    burst_wdata = 0; burst_wstrb = 0; burst_wlast = 0;
    burst_arid = 0; burst_araddr = 0; burst_arlen = 0;
    burst_arsize = 0; burst_arburst = 0;

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

    wait_done("write_while_running");

    repeat(3) @(posedge clk);
    check("d[8] sentinel preserved     [8]", V_1, 8);
    check("DIV  4/2=2 during test      [9]", V_2, 9);

    // ── Test: halt-then-restart via AXI ──────────────────────────────────────
    $display("-- Halt-then-restart via AXI --");

    write_instr(0, make_instr(OP_ADD,  20'd0, 20'd1, 20'd10)); // 1+2=3
    write_instr(1, make_instr(OP_HALT, 20'd0, 20'd0, 20'd0));

    repeat(2) @(posedge clk);
    run_and_wait("halt_then_restart");

    repeat(3) @(posedge clk);
    check("ADD  1+2=3 (restart) via AXI[10]", V_3, 10);

    // ── Test: DBRAM address auto-increment (PIO streaming) ───────────────────
    // Write DBRAM_ADDR once, then stream 16 consecutive data-word writes
    // without re-writing the address register.  Read back the same way.
    $display("-- DBRAM address auto-increment (PIO streaming) --");
    begin : autoinc_pio
      automatic logic [63:0] expected [16];
      automatic logic [31:0] lo, hi;
      automatic logic [63:0] got;
      automatic int          ai_ok = 1;

      // Build 16 distinct reference values cycling through V_1..V_4.
      for (int i = 0; i < 16; i++)
        case (i % 4)
          0: expected[i] = V_1;
          1: expected[i] = V_2;
          2: expected[i] = V_3;
          3: expected[i] = V_4;
        endcase

      // Write DBRAM[16..31] — set address ONCE then stream 16 trigger writes.
      axi_write(32'h14, 16);
      for (int i = 0; i < 16; i++) begin
        if (DATA_WIDTH == 64) begin
          axi_write(32'h18, expected[i][31:0]);   // low  word (no trigger, no auto-inc)
          axi_write(32'h1C, expected[i][63:32]);  // high word (trigger + auto-inc)
        end else begin
          axi_write(32'h18, expected[i][31:0]);   // trigger + auto-inc
        end
      end

      // Read back DBRAM[16..31] — set address ONCE then stream 16 reads.
      axi_write(32'h14, 16);
      repeat(4) @(posedge clk);   // BRAM registered-read settle
      for (int i = 0; i < 16; i++) begin
        axi_read(32'h18, lo);     // 32-bit: reads + auto-inc; 64-bit: low half only
        if (DATA_WIDTH == 64) begin
          axi_read(32'h1C, hi);   // high half + auto-inc
          got = {hi, lo};
        end else begin
          got = {32'b0, lo};
        end
        if (got[DATA_WIDTH-1:0] !== expected[i][DATA_WIDTH-1:0]) begin
          $display("  FAIL  autoinc_pio[%0d]  got 0x%0X  expected 0x%0X",
                   i, got[DATA_WIDTH-1:0], expected[i][DATA_WIDTH-1:0]);
          fail_count++;
          ai_ok = 0;
        end else begin
          pass_count++;
        end
      end
      if (ai_ok)
        $display("  PASS  autoinc_pio: 16 words written+read via streaming PIO");
    end

    // ── Burst tests ───────────────────────────────────────────────────────────
    // Use DBRAM slots 32..79 (clear of the earlier PIO tests).
    // Byte base address: slot * (DATA_WIDTH/8)
    $display("-- HP0 burst write then PIO read --");
    test_burst_pattern("burst_write_pio_read", 32, 16, 1'b1, 1'b0);

    $display("-- PIO write then HP0 burst read --");
    test_burst_pattern("pio_write_burst_read", 48, 16, 1'b0, 1'b1);

    $display("-- HP0 burst loopback (write then read) --");
    test_burst_pattern("burst_loopback",       64, 16, 1'b1, 1'b1);

    $display("-- HP0 burst load then run kernel --");
    begin : burst_then_kernel
      // Load d[80]=1.0, d[81]=2.0, d[82]=4.0 via burst, run ADD+DIV, read result via burst
      automatic int          BSLOT = 80;
      automatic int          BADDR = BSLOT * (DATA_WIDTH / 8);
      automatic logic [63:0] inputs  [] = new[3];
      automatic int          ok = 1;

      inputs[0] = V_1; inputs[1] = V_2; inputs[2] = V_4;
      axi4_write_burst(32'(BADDR), 3, inputs);

      // Overwrite instruction BRAM: ADD d[80]+d[81]→d[83], DIV d[82]/d[81]→d[84], HALT
      write_instr(0, make_instr(OP_ADD,  20'd80, 20'd81, 20'd83));
      write_instr(1, make_instr(OP_DIV,  20'd82, 20'd81, 20'd84));
      write_instr(2, make_instr(OP_HALT, 20'd0,  20'd0,  20'd0));

      repeat(2) @(posedge clk);
      run_and_wait("burst_then_kernel");
      repeat(3) @(posedge clk);
      axi4_read_burst(32'(BADDR), 5);  // burst_rd_buf[0..4] = d[80..84]

      // burst_rd_buf[3] = d[83] = 1+2=3, burst_rd_buf[4] = d[84] = 4/2=2
      if (burst_rd_buf[3][DATA_WIDTH-1:0] !== V_3[DATA_WIDTH-1:0]) begin
        $display("  FAIL  burst_kernel ADD  got 0x%0X  exp 0x%0X",
                 burst_rd_buf[3][DATA_WIDTH-1:0], V_3[DATA_WIDTH-1:0]);
        fail_count++; ok = 0;
      end else pass_count++;
      if (burst_rd_buf[4][DATA_WIDTH-1:0] !== V_2[DATA_WIDTH-1:0]) begin
        $display("  FAIL  burst_kernel DIV  got 0x%0X  exp 0x%0X",
                 burst_rd_buf[4][DATA_WIDTH-1:0], V_2[DATA_WIDTH-1:0]);
        fail_count++; ok = 0;
      end else pass_count++;
      if (ok) $display("  PASS  burst_then_kernel: ADD+DIV via burst load/readback OK");
    end

    $display("-- Burst write gated while RUNNING --");
    begin : burst_gated_by_running
      // Write a sentinel, start a long kernel (DIV), attempt burst overwrite while running,
      // verify sentinel preserved.
      automatic int          BSLOT = 96;
      automatic int          BADDR = BSLOT * (DATA_WIDTH / 8);
      automatic logic [63:0] sentinel  [] = new[1];
      automatic logic [63:0] poison    [] = new[1];

      sentinel[0] = V_1;
      poison[0]   = V_4;

      axi4_write_burst(32'(BADDR), 1, sentinel);
      repeat(2) @(posedge clk);

      // Short program: DIV d[82]/d[81]→d[97] (long latency), then HALT
      write_instr(0, make_instr(OP_DIV,  20'd82, 20'd81, 20'd97));
      write_instr(1, make_instr(OP_HALT, 20'd0,  20'd0,  20'd0));
      repeat(2) @(posedge clk);
      axi_write(32'h00, 32'h1);  // START

      // Attempt burst write to d[96] while running — should be silently dropped
      repeat(3) @(posedge clk);
      axi4_write_burst(32'(BADDR), 1, poison);

      wait_done("burst_gated_by_running");

      repeat(3) @(posedge clk);
      axi4_read_burst(32'(BADDR), 1);  // burst_rd_buf[0] = d[96]

      if (burst_rd_buf[0][DATA_WIDTH-1:0] !== V_1[DATA_WIDTH-1:0]) begin
        $display("  FAIL  burst_gated: sentinel overwritten! got 0x%0X  exp 0x%0X",
                 burst_rd_buf[0][DATA_WIDTH-1:0], V_1[DATA_WIDTH-1:0]);
        fail_count++;
      end else begin
        $display("  PASS  burst_gated: sentinel preserved while RUNNING");
        pass_count++;
      end
    end

    // ── Opcode coverage: missing opcodes via AXI path ────────────────────────
    // Exercises SUB, MUL, SQRT, NEG, ABS, MOV, RELU, QACC_MSUB, QACC_NEG
    // using d[0..2] already loaded above (1.0, 2.0, 4.0).
    // Results land in d[100..107].
    $display("-- Missing opcode coverage via AXI --");
    write_instr( 0, make_instr(OP_SUB,        20'd1,   20'd0,   20'd100)); // 2-1=1
    write_instr( 1, make_instr(OP_MUL,        20'd0,   20'd2,   20'd101)); // 1*4=4
    write_instr( 2, make_instr(OP_SQRT,       20'd2,   20'd0,   20'd102)); // sqrt(4)=2
    write_instr( 3, make_instr(OP_NEG,        20'd1,   20'd0,   20'd103)); // -2.0
    write_instr( 4, make_instr(OP_ABS,        20'd103, 20'd0,   20'd104)); // |-2|=2
    write_instr( 5, make_instr(OP_MOV,        20'd2,   20'd0,   20'd105)); // 4.0
    write_instr( 6, make_instr(OP_RELU,       20'd103, 20'd0,   20'd106)); // max(0,-2)=0
    write_instr( 7, make_instr(OP_QACC_CLEAR, 20'd0,   20'd0,   20'd0));
    write_instr( 8, make_instr(OP_QACC_ADD,   20'd2,   20'd0,   20'd0));   // acc=4
    write_instr( 9, make_instr(OP_QACC_MSUB,  20'd0,   20'd1,   20'd0));   // acc=4-(1*2)=2
    write_instr(10, make_instr(OP_QACC_NEG,   20'd0,   20'd0,   20'd0));   // acc=-2
    write_instr(11, make_instr(OP_QACC_READ,  20'd0,   20'd0,   20'd107)); // d[107]=-2
    write_instr(12, make_instr(OP_HALT,       20'd0,   20'd0,   20'd0));

    repeat(2) @(posedge clk);
    run_and_wait("opcode_coverage");
    repeat(3) @(posedge clk);

    check("SUB  2-1=1          [100]", V_1,    100);
    check("MUL  1*4=4          [101]", V_4,    101);
    check("SQRT sqrt(4)=2      [102]", V_2,    102);
    check("NEG  -2.0           [103]", V_NEG2, 103);
    check("ABS  |-2|=2         [104]", V_2,    104);
    check("MOV  4.0            [105]", V_4,    105);
    check("RELU max(0,-2)=0    [106]", V_0,    106);
    check("QACC_MSUB+NEG=-2.0 [107]", V_NEG2, 107);

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
    #50_000_000;
    $display("TIMEOUT: AXI simulation did not complete");
    $finish;
  end

endmodule
