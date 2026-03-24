// Testbench for accel_axi.
// Writes a program into instruction BRAM via AXI-Lite, writes operands into
// data BRAM via AXI, starts the accelerator, polls STATUS until DONE, then
// reads back the result.
//
// Same program as tb_accel_core: ADD data[0]+data[1]→data[2], then HALT.
// posit32 es=2: 1.0=0x40000000, expected sum 2.0=0x48000000.

`timescale 1ns/1ps

module tb_accel_axi
  import config_pkg::*;
  import opcodes_pkg::*;
();

  localparam CLK_PERIOD = 10;

  logic clk, rst_n;
  initial clk = 0;
  always #(CLK_PERIOD/2) clk = ~clk;

  initial begin
    rst_n = 0;
    repeat(5) @(posedge clk);
    rst_n = 1;
  end

  // ── AXI-Lite signals ──────────────────────────────────────────────────────
  logic [31:0] s_axi_awaddr;  logic s_axi_awvalid, s_axi_awready;
  logic [31:0] s_axi_wdata;   logic [3:0] s_axi_wstrb;
  logic s_axi_wvalid, s_axi_wready;
  logic [1:0] s_axi_bresp;    logic s_axi_bvalid, s_axi_bready;
  logic [31:0] s_axi_araddr;  logic s_axi_arvalid, s_axi_arready;
  logic [31:0] s_axi_rdata;   logic [1:0] s_axi_rresp;
  logic s_axi_rvalid, s_axi_rready;

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

  // ── AXI helpers ────────────────────────────────────────────────────────────
  task automatic axi_write(input logic [31:0] addr, input logic [31:0] data);
    @(posedge clk);
    s_axi_awaddr  = addr;
    s_axi_awvalid = 1;
    s_axi_wdata   = data;
    s_axi_wstrb   = 4'hF;
    s_axi_wvalid  = 1;
    s_axi_bready  = 1;
    fork
      begin wait(s_axi_awready); @(posedge clk); s_axi_awvalid = 0; end
      begin wait(s_axi_wready);  @(posedge clk); s_axi_wvalid  = 0; end
    join
    wait(s_axi_bvalid);
    @(posedge clk);
    s_axi_bready = 0;
  endtask

  task automatic axi_read(input logic [31:0] addr, output logic [31:0] data);
    @(posedge clk);
    s_axi_araddr  = addr;
    s_axi_arvalid = 1;
    s_axi_rready  = 1;
    wait(s_axi_arready);
    @(posedge clk);
    s_axi_arvalid = 0;
    wait(s_axi_rvalid);
    data = s_axi_rdata;
    @(posedge clk);
    s_axi_rready = 0;
  endtask

  // Write a 64-bit instruction via IBRAM_DATA_LO / IBRAM_DATA_HI
  task automatic write_instr(input int idx, input logic [63:0] instr);
    axi_write(32'h08, idx);             // IBRAM_ADDR
    axi_write(32'h0C, instr[31:0]);     // IBRAM_DATA_LO
    axi_write(32'h10, instr[63:32]);    // IBRAM_DATA_HI → triggers BRAM write
  endtask

  // Write a data word via DBRAM
  task automatic write_data(input int idx, input logic [31:0] data);
    axi_write(32'h14, idx);     // DBRAM_ADDR
    axi_write(32'h18, data);    // DBRAM_DATA → triggers BRAM write for 32-bit
  endtask

  function automatic logic [63:0] make_instr(
    input opcode_t op,
    input logic [11:0] a, b, res
  );
    return {op, a, b, res, 20'b0};
  endfunction

  // ── Test ───────────────────────────────────────────────────────────────────
  initial begin
    s_axi_awvalid = 0; s_axi_wvalid = 0; s_axi_bready = 0;
    s_axi_arvalid = 0; s_axi_rready = 0;
    s_axi_awaddr = 0; s_axi_wdata = 0; s_axi_wstrb = 0; s_axi_araddr = 0;

    @(posedge rst_n);
    repeat(3) @(posedge clk);

    // Load instruction BRAM
    write_instr(0, make_instr(OP_ADD,  12'd0, 12'd1, 12'd2));
    write_instr(1, make_instr(OP_HALT, 12'd0, 12'd0, 12'd0));

    // Load data BRAM: data[0]=1.0, data[1]=1.0 (posit32 es=2)
    write_data(0, 32'h40000000);
    write_data(1, 32'h40000000);

    // Start accelerator (write CTRL[0]=1)
    $display("[%0t] Starting accelerator via AXI...", $time);
    axi_write(32'h00, 32'h1);

    // Poll STATUS until DONE (bit 0)
    logic [31:0] status;
    repeat(500) begin
      @(posedge clk);
      axi_read(32'h04, status);
      if (status[0]) break;  // DONE
    end

    if (!status[0]) begin
      $display("FAIL: accelerator did not complete");
      $finish;
    end
    $display("[%0t] DONE asserted.", $time);

    // Read data[2] via DBRAM_ADDR/DBRAM_DATA
    axi_write(32'h14, 32'd2);  // DBRAM_ADDR = 2
    repeat(3) @(posedge clk);   // allow read latency

    logic [31:0] result;
    axi_read(32'h18, result);

    if (result == 32'h48000000)
      $display("PASS: data[2] = 0x%08X (2.0) ✓", result);
    else
      $display("FAIL: data[2] = 0x%08X (expected 0x48000000 = 2.0)", result);

    $display("[%0t] Simulation complete.", $time);
    $finish;
  end

  initial begin
    #5_000_000;
    $display("TIMEOUT");
    $finish;
  end

endmodule
