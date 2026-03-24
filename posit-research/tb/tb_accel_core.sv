// Testbench for accel_core.
// Loads a short posit (or float) program into instruction BRAM,
// writes operands into data BRAM, runs the accelerator, and
// checks the result.
//
// Program (PAU 32-bit posit, es=2):
//   IBRAM[0]:  ADD   data[0], data[1] → data[2]   ; 1.0 + 1.0 = 2.0
//   IBRAM[1]:  MUL   data[0], data[0] → data[3]   ; 1.0 * 1.0 = 1.0
//   IBRAM[2]:  QACC_CLEAR
//   IBRAM[3]:  QACC_MADD data[0], data[0]          ; acc += 1.0 * 1.0 = 1.0
//   IBRAM[4]:  QACC_MADD data[4], data[4]          ; acc += 3.0 * 3.0 = 10.0
//   IBRAM[5]:  QACC_READ → data[5]                 ; data[5] = 10.0
//   IBRAM[6]:  HALT
//
// Posit 32-bit es=2 values used:
//   1.0  = 0x40000000
//   2.0  = 0x48000000  (expected at data[2])
//   3.0  = 0x4C000000
//   10.0 = 0x57800000  (expected at data[5])

`timescale 1ns/1ps

module tb_accel_core
  import config_pkg::*;
  import opcodes_pkg::*;
();

  localparam CLK_PERIOD = 10;   // 10 ns = 100 MHz

  // ── Clock and reset ────────────────────────────────────────────────────────
  logic clk, rst_n;
  initial clk = 0;
  always #(CLK_PERIOD/2) clk = ~clk;

  initial begin
    rst_n = 0;
    repeat(5) @(posedge clk);
    rst_n = 1;
  end

  // ── DUT signals ────────────────────────────────────────────────────────────
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
    .clk_i         ( clk        ),
    .rst_ni        ( rst_n      ),
    .start_i       ( start      ),
    .done_o        ( done       ),
    .running_o     ( running    ),
    .ibram_addr_i  ( ibram_addr  ),
    .ibram_wdata_i ( ibram_wdata ),
    .ibram_we_i    ( ibram_we    ),
    .ibram_rdata_o ( ibram_rdata ),
    .dbram_addr_i  ( dbram_addr  ),
    .dbram_wdata_i ( dbram_wdata ),
    .dbram_we_i    ( dbram_we    ),
    .dbram_rdata_o ( dbram_rdata )
  );

  // ── Helpers ────────────────────────────────────────────────────────────────
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

  // Build a 64-bit instruction word
  function automatic logic [63:0] make_instr(
    input opcode_t op,
    input logic [11:0] a, b, res
  );
    return {op, a, b, res, 20'b0};
  endfunction

  // ── Test program ────────────────────────────────────────────────────────────
  logic [DATA_WIDTH-1:0] result;

  initial begin
    start      = 0;
    ibram_addr = 0; ibram_wdata = 0; ibram_we = 0;
    dbram_addr = 0; dbram_wdata = 0; dbram_we = 0;

    // Wait for reset
    @(posedge rst_n);
    repeat(3) @(posedge clk);

    // ── Load instruction BRAM ────────────────────────────────────────────────
    write_ibram(0, make_instr(OP_ADD,        12'd0, 12'd1, 12'd2));  // data[2] = data[0]+data[1]
    write_ibram(1, make_instr(OP_MUL,        12'd0, 12'd0, 12'd3));  // data[3] = data[0]*data[0]
    write_ibram(2, make_instr(OP_QACC_CLEAR, 12'd0, 12'd0, 12'd0));
    write_ibram(3, make_instr(OP_QACC_MADD,  12'd0, 12'd0, 12'd0));  // acc += 1*1
    write_ibram(4, make_instr(OP_QACC_MADD,  12'd4, 12'd4, 12'd0));  // acc += 3*3
    write_ibram(5, make_instr(OP_QACC_READ,  12'd0, 12'd0, 12'd5));  // data[5] = round(acc)
    write_ibram(6, make_instr(OP_HALT,       12'd0, 12'd0, 12'd0));

    // ── Load data BRAM ────────────────────────────────────────────────────────
    // Using posit32 (es=2) encodings:
    write_dbram(0, 32'h40000000);  // 1.0
    write_dbram(1, 32'h40000000);  // 1.0
    write_dbram(4, 32'h4C000000);  // 3.0

    repeat(3) @(posedge clk);

    // ── Start the accelerator ─────────────────────────────────────────────────
    $display("[%0t] Starting accelerator...", $time);
    @(posedge clk); start = 1;
    @(posedge clk); start = 0;

    // ── Wait for HALT ─────────────────────────────────────────────────────────
    wait(done);
    repeat(5) @(posedge clk);

    // ── Read and check results ────────────────────────────────────────────────
    read_dbram(2, result);
    if (result == 32'h48000000)
      $display("PASS: data[2] = 0x%08X (2.0) ✓", result);
    else
      $display("FAIL: data[2] = 0x%08X (expected 0x48000000 = 2.0)", result);

    read_dbram(3, result);
    if (result == 32'h40000000)
      $display("PASS: data[3] = 0x%08X (1.0) ✓", result);
    else
      $display("FAIL: data[3] = 0x%08X (expected 0x40000000 = 1.0)", result);

    read_dbram(5, result);
    if (result == 32'h57800000)
      $display("PASS: data[5] = 0x%08X (10.0) ✓", result);
    else
      $display("FAIL: data[5] = 0x%08X (expected 0x57800000 = 10.0)", result);

    $display("[%0t] Simulation complete.", $time);
    $finish;
  end

  // Watchdog
  initial begin
    #1_000_000;
    $display("TIMEOUT: simulation did not complete in 1 ms");
    $finish;
  end

endmodule
