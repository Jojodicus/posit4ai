// 64-bit AXI4 burst slave for data BRAM (HP0 path).
//
// Maps the entire data BRAM as a flat, word-addressable memory window.
// The host (PS7 CPU via S_AXI_HP0) performs AXI4 INCR burst memcpy to load
// or read back data, replacing the slow AXI-Lite single-word register pokes.
//
// Beat <-> BRAM word mapping:
//   DATA_WIDTH=32: AWADDR[BAW+1:2] -> base index; low 32 bits of WDATA used
//   DATA_WIDTH=64: AWADDR[BAW+2:3] -> base index; all 64 bits of WDATA used
//   One AXI4 beat = one BRAM word (simple, avoids sub-beat packing complexity).
//   For DATA_WIDTH=32 reads: RDATA[63:32] = 0 (host uses only RDATA[31:0]).
//
// Protocol:
//   - AXI4, 64-bit data bus (native HP0 width -- no Vivado width converter)
//   - INCR bursts only; WRAP/FIXED -> SLVERR response
//   - AWLEN/ARLEN[7:0] = beats - 1  (AXI4 encoding)
//   - WSTRB: low DATA_WIDTH/8 bytes must be all-1 or all-0; upper bytes ignored
//   - Burst writes gated by running_i; burst reads always allowed
//   - b_req to arbiter held HIGH from first address cycle through final handshake
//
// Read pipeline (1-cycle registered BRAM latency):
//   R_IDLE  ->  R_ADDR (assert b_req, issue addr[beat=0])
//          ->  R_DATA  (RVALID, pre-fetch addr[beat+1] each cycle)
//          ->  R_IDLE  on RLAST+RREADY

module accel_axi_burst
  import config_pkg::*;
  import opcodes_pkg::*;
#(
  parameter int AXI_ADDR_WIDTH = 32,
  parameter int AXI_ID_WIDTH   = 4
) (
  input  logic clk_i,
  input  logic rst_ni,

  input  logic running_i,

  // -- AXI4 slave (64-bit data) ------------------------------------
  input  logic [AXI_ID_WIDTH-1:0]   s_axi_awid,
  input  logic [AXI_ADDR_WIDTH-1:0] s_axi_awaddr,
  input  logic [7:0]                s_axi_awlen,
  input  logic [2:0]                s_axi_awsize,
  input  logic [1:0]                s_axi_awburst,
  input  logic                      s_axi_awvalid,
  output logic                      s_axi_awready,

  input  logic [63:0]               s_axi_wdata,
  input  logic [7:0]                s_axi_wstrb,
  input  logic                      s_axi_wlast,
  input  logic                      s_axi_wvalid,
  output logic                      s_axi_wready,

  output logic [AXI_ID_WIDTH-1:0]   s_axi_bid,
  output logic [1:0]                s_axi_bresp,
  output logic                      s_axi_bvalid,
  input  logic                      s_axi_bready,

  input  logic [AXI_ID_WIDTH-1:0]   s_axi_arid,
  input  logic [AXI_ADDR_WIDTH-1:0] s_axi_araddr,
  input  logic [7:0]                s_axi_arlen,
  input  logic [2:0]                s_axi_arsize,
  input  logic [1:0]                s_axi_arburst,
  input  logic                      s_axi_arvalid,
  output logic                      s_axi_arready,

  output logic [AXI_ID_WIDTH-1:0]   s_axi_rid,
  output logic [63:0]               s_axi_rdata,
  output logic [1:0]                s_axi_rresp,
  output logic                      s_axi_rlast,
  output logic                      s_axi_rvalid,
  input  logic                      s_axi_rready,

  // -- Arbiter port B -------------------------------------------
  output logic                           b_req,
  output logic [$clog2(DATA_DEPTH)-1:0]  b_addr,
  output logic [DATA_WIDTH-1:0]          b_wdata,
  output logic                           b_we,
  input  logic [DATA_WIDTH-1:0]          b_rdata
);

  localparam int BAW = $clog2(DATA_DEPTH);
  // Shift amount to move the posit encoding between bus [31:0] high bits and BRAM [DATA_WIDTH-1:0].
  // DATA_WIDTH=8: 24, DATA_WIDTH=16: 16, DATA_WIDTH=32: 0.  Unused for DATA_WIDTH=64.
  localparam int BRAM_SHIFT = (DATA_WIDTH < 64) ? (32 - DATA_WIDTH) : 0;

  // -- Address -> BRAM index ------------------------------------
  function automatic logic [BAW-1:0] bram_index(logic [AXI_ADDR_WIDTH-1:0] a);
    if (DATA_WIDTH == 64)
      return a[BAW+2:3];   // 8-byte words
    else
      return a[BAW+1:2];   // 4-byte words
  endfunction

  // -- High-bits extract for write: posit lives in [31:32-DATA_WIDTH] of bus word.
  function automatic logic [DATA_WIDTH-1:0] extract_wdata(logic [63:0] wdata);
    if (DATA_WIDTH == 64) return wdata;
    else                  return wdata[31 -: DATA_WIDTH];
  endfunction

  // -- High-bits pack for read: shift BRAM value into [31:32-DATA_WIDTH] of rdata.
  function automatic logic [63:0] pack_rdata(logic [DATA_WIDTH-1:0] rdata);
    if (DATA_WIDTH == 64) return rdata;
    else                  return {32'b0, 32'(rdata) << BRAM_SHIFT};
  endfunction

  // -- Write FSM (W_IDLE -> W_BURST -> W_RESP) --------------------
  typedef enum logic [1:0] { W_IDLE, W_BURST, W_RESP } wr_state_t;
  wr_state_t wr_state_q, wr_state_d;

  logic [AXI_ID_WIDTH-1:0]  wr_id_q;
  logic [BAW-1:0]            wr_base_q;    // BRAM base for this burst
  logic [7:0]                wr_awlen_q;
  logic [7:0]                wr_beat_q;    // 0 .. AWLEN
  logic                      wr_illegal_q; // non-INCR burst
  logic                      wr_slverr_q;  // sticky: bad WSTRB seen this burst

  // WSTRB valid check for the low DATA_WIDTH/8 bytes
  function automatic logic wstrb_ok(logic [7:0] strb);
    logic [3:0] lo = strb[3:0];
    if (DATA_WIDTH == 64) return (strb == 8'hFF) || (strb == 8'h00);
    else                  return (lo   == 4'hF)  || (lo   == 4'h0);
  endfunction

  function automatic logic wstrb_write(logic [7:0] strb);
    if (DATA_WIDTH == 64) return (strb != 8'h00);
    else                  return (strb[3:0] != 4'h0);
  endfunction

  always_comb begin
    wr_state_d    = wr_state_q;
    s_axi_awready = 1'b0;
    s_axi_wready  = 1'b0;
    s_axi_bvalid  = 1'b0;
    s_axi_bid     = wr_id_q;
    s_axi_bresp   = wr_slverr_q ? 2'b10 : 2'b00;

    unique case (wr_state_q)
      W_IDLE: begin
        s_axi_awready = 1'b1;
        if (s_axi_awvalid) wr_state_d = W_BURST;
      end
      W_BURST: begin
        // Always accept W-channel beats (no backpressure from running_i).
        // When running_i is asserted, beats are accepted but BRAM WE is gated
        // (see b_we below) and SLVERR is sticky-set in always_ff.
        s_axi_wready = 1'b1;
        if (s_axi_wvalid)
          if (wr_beat_q == wr_awlen_q) wr_state_d = W_RESP;
      end
      W_RESP: begin
        s_axi_bvalid = 1'b1;
        if (s_axi_bready) wr_state_d = W_IDLE;
      end
      default: wr_state_d = W_IDLE;
    endcase
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      wr_state_q   <= W_IDLE;
      wr_id_q      <= '0;
      wr_base_q    <= '0;
      wr_awlen_q   <= '0;
      wr_beat_q    <= '0;
      wr_illegal_q <= 1'b0;
      wr_slverr_q  <= 1'b0;
    end else begin
      wr_state_q <= wr_state_d;
      if (wr_state_q == W_IDLE && s_axi_awvalid) begin
        wr_id_q      <= s_axi_awid;
        wr_awlen_q   <= s_axi_awlen;
        wr_beat_q    <= '0;
        wr_slverr_q  <= 1'b0;
        wr_illegal_q <= (s_axi_awburst != 2'b01);
        wr_base_q    <= bram_index(s_axi_awaddr);
      end
      if (wr_state_q == W_BURST && s_axi_wvalid) begin
        wr_beat_q <= wr_beat_q + 8'd1;
        if (!wstrb_ok(s_axi_wstrb)) wr_slverr_q <= 1'b1;
      end
      // Sticky SLVERR if running_i is seen at any point during a burst write
      // (data was silently dropped; inform master via BRESP=SLVERR).
      if (wr_state_q == W_BURST && running_i) wr_slverr_q <= 1'b1;
    end
  end

  // -- Read FSM (R_IDLE -> R_ADDR -> R_DATA -> R_IDLE) ------------
  // R_ADDR: assert b_req, issue addr[beat=0], wait 1 cycle for BRAM output.
  // R_DATA: RVALID=1; pre-fetch addr[beat+1] each cycle to fill the pipeline.

  typedef enum logic [1:0] { R_IDLE, R_ADDR, R_DATA } rd_state_t;
  rd_state_t rd_state_q, rd_state_d;

  logic [AXI_ID_WIDTH-1:0]  rd_id_q;
  logic [BAW-1:0]            rd_base_q;
  logic [7:0]                rd_arlen_q;
  logic [7:0]                rd_beat_q;
  logic                      rd_illegal_q;

  // Current BRAM read address driven by the read FSM
  logic [BAW-1:0] rd_bram_addr;

  always_comb begin
    rd_state_d    = rd_state_q;
    s_axi_arready = 1'b0;
    s_axi_rvalid  = 1'b0;
    s_axi_rid     = rd_id_q;
    s_axi_rresp   = rd_illegal_q ? 2'b10 : 2'b00;
    s_axi_rlast   = (rd_beat_q == rd_arlen_q);
    s_axi_rdata   = pack_rdata(b_rdata);
    rd_bram_addr  = rd_base_q + BAW'(rd_beat_q);

    unique case (rd_state_q)
      R_IDLE: begin
        s_axi_arready = 1'b1;
        if (s_axi_arvalid) rd_state_d = R_ADDR;
        rd_bram_addr = bram_index(s_axi_araddr);  // peek ahead (doesn't matter, b_req=0)
      end
      R_ADDR: begin
        // Assert b_req, drive addr[beat=0], wait 1 cycle for BRAM registered output
        rd_bram_addr = rd_base_q;
        rd_state_d   = R_DATA;
      end
      R_DATA: begin
        s_axi_rvalid = 1'b1;
        // Pre-fetch next beat address (beat_q advances in ff on RREADY)
        rd_bram_addr = rd_base_q + BAW'(rd_beat_q + 8'd1);
        if (s_axi_rready) begin
          if (rd_beat_q == rd_arlen_q) rd_state_d = R_IDLE;
        end
      end
      default: rd_state_d = R_IDLE;
    endcase
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      rd_state_q   <= R_IDLE;
      rd_id_q      <= '0;
      rd_base_q    <= '0;
      rd_arlen_q   <= '0;
      rd_beat_q    <= '0;
      rd_illegal_q <= 1'b0;
    end else begin
      rd_state_q <= rd_state_d;
      if (rd_state_q == R_IDLE && s_axi_arvalid) begin
        rd_id_q      <= s_axi_arid;
        rd_arlen_q   <= s_axi_arlen;
        rd_beat_q    <= '0;
        rd_illegal_q <= (s_axi_arburst != 2'b01);
        rd_base_q    <= bram_index(s_axi_araddr);
      end
      if (rd_state_q == R_DATA && s_axi_rready)
        rd_beat_q <= rd_beat_q + 8'd1;
    end
  end

  // -- Arbiter port B output ------------------------------------
  // b_req held during write burst (W_BURST + W_RESP) and read burst (R_ADDR + R_DATA).
  // Write has priority over read when both happen simultaneously (shouldn't in practice).
  assign b_req = (wr_state_q == W_BURST) || (wr_state_q == W_RESP) ||
                 (rd_state_q == R_ADDR)  || (rd_state_q == R_DATA);

  always_comb begin
    if (wr_state_q == W_BURST && s_axi_wvalid) begin
      // Write path: drive beat address; WE is gated by !running_i so that
      // beats accepted during an active run are silently dropped (SLVERR returned).
      b_addr  = wr_base_q + BAW'(wr_beat_q);
      b_wdata = extract_wdata(s_axi_wdata);
      b_we    = wstrb_write(s_axi_wstrb) && !wr_illegal_q && !running_i;
    end else begin
      // Read path: drive the pre-computed read address
      b_addr  = rd_bram_addr;
      b_wdata = '0;
      b_we    = 1'b0;
    end
  end

endmodule
