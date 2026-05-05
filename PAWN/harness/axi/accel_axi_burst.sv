// 32-bit AXI4 burst slave for data BRAM (GP1 path).
//
// Maps the entire data BRAM as a flat, word-addressable memory window.
// Supports both multi-beat AXI4 INCR bursts AND single-beat (AWLEN=0)
// transactions. The Cortex-A9 with /dev/mem mappings (Strongly-Ordered or
// Device memory) does NOT merge consecutive volatile stores into multi-beat
// bursts -- each 32-bit store becomes a separate AWLEN=0 transaction. So the
// 64-bit path must still work when lo and hi halves arrive in separate AXI
// transactions; we track absolute beat parity (AWADDR[2] XOR beat_q[0]) so
// the lo/hi alignment is independent of how the master frames bursts.
//
// Beat <-> BRAM word mapping (32-bit AXI bus):
//   DATA_WIDTH < 64: one AXI beat = one BRAM word. Posit value in upper bits
//     of WDATA; reads return same layout. AWADDR[BAW+1:2] -> base BRAM index.
//   DATA_WIDTH == 64: two AXI beats per BRAM word.
//     parity 0 (lo): WDATA[31:0] -> wr_lo_q (latched, no BRAM write)
//     parity 1 (hi): {WDATA, wr_lo_q} -> BRAM[wr_idx_q]; WE fires; idx++
//     parity = AWADDR[2] XOR wr_beat_q[0], so a single-beat lone-hi
//       transaction (AWADDR[2]=1, AWLEN=0) writes using the wr_lo_q latched
//       by the prior lone-lo transaction.
//   Reads (DATA_WIDTH==64): symmetric.
//     parity 0 (lo): RDATA = b_rdata[31:0]
//     parity 1 (hi): RDATA = b_rdata[63:32]; idx advances after handshake.
//   Multi-beat bursts starting hi-aligned (AWADDR[2]=1 with AWLEN>0) ->
//     SLVERR -- the lo/hi pairing across the burst would be ambiguous.
//
// Read addressing is back-pressure safe. rd_idx_q tracks the BRAM word
// currently being addressed; when the master deasserts RREADY the index
// holds, so the BRAM stays parked on the same word.
//
// Protocol:
//   - AXI4, 32-bit data bus
//   - INCR bursts only; WRAP/FIXED -> SLVERR
//   - Burst writes gated by running_i; beats accepted but WE inhibited, SLVERR sticky
//   - Burst reads always allowed
//   - b_req held during W_BURST / R_ADDR / R_DATA; dropped in W_RESP

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

  // -- AXI4 slave (32-bit data) ------------------------------------
  input  logic [AXI_ID_WIDTH-1:0]   s_axi_awid,
  input  logic [AXI_ADDR_WIDTH-1:0] s_axi_awaddr,
  input  logic [7:0]                s_axi_awlen,
  input  logic [2:0]                s_axi_awsize,
  input  logic [1:0]                s_axi_awburst,
  input  logic                      s_axi_awvalid,
  output logic                      s_axi_awready,

  input  logic [31:0]               s_axi_wdata,
  input  logic [3:0]                s_axi_wstrb,
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
  output logic [31:0]               s_axi_rdata,
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
  // Shift to place sub-32-bit posit in upper bits of 32-bit AXI word.
  // DATA_WIDTH=8: 24, DATA_WIDTH=16: 16, DATA_WIDTH=32: 0. Unused for DATA_WIDTH=64.
  localparam int BRAM_SHIFT = (DATA_WIDTH < 32) ? (32 - DATA_WIDTH) : 0;

  // -- Address -> BRAM word index ----------------------------
  function automatic logic [BAW-1:0] bram_index(logic [AXI_ADDR_WIDTH-1:0] a);
    if (DATA_WIDTH == 64)
      return a[BAW+2:3];   // 8-byte words
    else
      return a[BAW+1:2];   // 4-byte words
  endfunction

  // Extract posit from upper DATA_WIDTH bits of 32-bit write word (DATA_WIDTH < 64).
  function automatic logic [DATA_WIDTH-1:0] extract_wdata(logic [31:0] wdata);
    if (DATA_WIDTH == 64) return '0;        // unreachable; 64-bit handled separately
    else if (DATA_WIDTH == 32) return wdata;
    else return DATA_WIDTH'(wdata >> BRAM_SHIFT);
  endfunction

  // Pack DATA_WIDTH-bit BRAM value into upper bits of 32-bit read word (DATA_WIDTH < 64).
  function automatic logic [31:0] pack_rdata(logic [DATA_WIDTH-1:0] rdata);
    if (DATA_WIDTH >= 32) return 32'(rdata);
    else return 32'(rdata) << BRAM_SHIFT;
  endfunction

  // -- Write FSM (W_IDLE -> W_BURST -> W_RESP) ----------------
  typedef enum logic [1:0] { W_IDLE, W_BURST, W_RESP } wr_state_t;
  wr_state_t wr_state_q, wr_state_d;

  logic [AXI_ID_WIDTH-1:0]   wr_id_q;
  logic [BAW-1:0]            wr_idx_q;     // current BRAM word index
  logic [7:0]                wr_awlen_q;
  logic [7:0]                wr_beat_q;
  logic                      wr_addr2_q;   // AWADDR[2] latched at AW (DATA_WIDTH=64 only)
  logic                      wr_illegal_q;
  logic                      wr_slverr_q;
  logic [31:0]               wr_lo_q;      // DATA_WIDTH=64: latched lo half

  // Absolute parity of the current write beat: 0=lo, 1=hi (DATA_WIDTH=64 only).
  logic wr_parity_now;
  assign wr_parity_now = wr_addr2_q ^ wr_beat_q[0];

  // Single handshake event used everywhere below.
  logic wr_handshake;
  assign wr_handshake = (wr_state_q == W_BURST) && s_axi_wvalid;

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
      wr_idx_q     <= '0;
      wr_awlen_q   <= '0;
      wr_beat_q    <= '0;
      wr_addr2_q   <= 1'b0;
      wr_illegal_q <= 1'b0;
      wr_slverr_q  <= 1'b0;
      wr_lo_q      <= '0;
    end else begin
      wr_state_q <= wr_state_d;
      if (wr_state_q == W_IDLE && s_axi_awvalid) begin
        wr_id_q     <= s_axi_awid;
        wr_awlen_q  <= s_axi_awlen;
        wr_beat_q   <= '0;
        wr_addr2_q  <= s_axi_awaddr[2];
        wr_idx_q    <= bram_index(s_axi_awaddr);
        wr_slverr_q <= 1'b0;
        // SLVERR conditions:
        //   - non-INCR burst
        //   - non-32-bit beat size
        //   - DATA_WIDTH=64: AWADDR[2]=1 with AWLEN>0 (misaligned multi-beat)
        // Single-beat lone-hi (AWADDR[2]=1, AWLEN=0) is legal: WE fires using
        // wr_lo_q latched by the prior lone-lo transaction.
        wr_illegal_q <= (s_axi_awburst != 2'b01) ||
                        (s_axi_awsize  != 3'b010) ||
                        (DATA_WIDTH == 64 && s_axi_awaddr[2] && s_axi_awlen != 8'd0);
        if ((s_axi_awburst != 2'b01) ||
            (s_axi_awsize  != 3'b010) ||
            (DATA_WIDTH == 64 && s_axi_awaddr[2] && s_axi_awlen != 8'd0))
          wr_slverr_q <= 1'b1;
      end
      if (wr_handshake) begin
        wr_beat_q <= wr_beat_q + 8'd1;
        if ((wr_beat_q == wr_awlen_q) != s_axi_wlast)
          wr_slverr_q <= 1'b1;
        if (DATA_WIDTH == 64 && !wr_parity_now)
          wr_lo_q <= s_axi_wdata;            // lo: latch
        if (DATA_WIDTH == 64 && wr_parity_now)
          wr_idx_q <= wr_idx_q + BAW'(1);    // hi: advance after this BRAM write
        if (DATA_WIDTH != 64)
          wr_idx_q <= wr_idx_q + BAW'(1);    // non-64: every beat advances
        if (DATA_WIDTH != 64 && s_axi_wstrb != 4'hF && s_axi_wstrb != 4'h0)
          wr_slverr_q <= 1'b1;
      end
      // Sticky SLVERR if running during a write burst (data silently dropped)
      if (wr_state_q == W_BURST && running_i) wr_slverr_q <= 1'b1;
    end
  end

  // -- Read FSM (R_IDLE -> R_ADDR -> R_DATA -> R_IDLE) ------------
  // Address pipeline (back-pressure safe):
  //   R_ADDR : drive b_addr = rd_idx_q (= base index). At edge, BRAM samples;
  //            R_DATA cycle 0 then has b_rdata = BRAM[base].
  //   R_DATA : drive b_addr = rd_idx_next, where rd_idx_next advances by 1
  //            iff this cycle's R-handshake fires AND parity says we are done
  //            with this BRAM word. If RREADY is low, rd_idx_q holds, b_addr
  //            stays on the same word, BRAM stays parked.

  typedef enum logic [1:0] { R_IDLE, R_ADDR, R_DATA } rd_state_t;
  rd_state_t rd_state_q, rd_state_d;

  logic [AXI_ID_WIDTH-1:0]   rd_id_q;
  logic [BAW-1:0]            rd_idx_q;
  logic [7:0]                rd_arlen_q;
  logic [7:0]                rd_beat_q;
  logic                      rd_addr2_q;   // ARADDR[2] latched at AR (DATA_WIDTH=64 only)
  logic                      rd_illegal_q;

  logic rd_parity_now;
  assign rd_parity_now = rd_addr2_q ^ rd_beat_q[0];

  logic rd_handshake;
  assign rd_handshake = (rd_state_q == R_DATA) && s_axi_rvalid && s_axi_rready;

  // Advance the BRAM word index after a handshake?
  //   non-64-bit: yes (one beat = one word)
  //   64-bit:     only on hi-parity beat (lo+hi consume one word)
  logic rd_advance_idx;
  assign rd_advance_idx = rd_handshake &&
                          ((DATA_WIDTH != 64) || rd_parity_now);

  logic [BAW-1:0] rd_idx_next;
  assign rd_idx_next = rd_idx_q + (rd_advance_idx ? BAW'(1) : BAW'(0));

  always_comb begin
    rd_state_d    = rd_state_q;
    s_axi_arready = 1'b0;
    s_axi_rvalid  = 1'b0;
    s_axi_rid     = rd_id_q;
    s_axi_rresp   = rd_illegal_q ? 2'b10 : 2'b00;
    s_axi_rlast   = (rd_beat_q == rd_arlen_q);

    if (DATA_WIDTH == 64) begin
      s_axi_rdata = rd_parity_now ? b_rdata[63:32] : b_rdata[31:0];
    end else begin
      s_axi_rdata = pack_rdata(b_rdata);
    end

    unique case (rd_state_q)
      R_IDLE: begin
        s_axi_arready = 1'b1;
        if (s_axi_arvalid) rd_state_d = R_ADDR;
      end
      R_ADDR: begin
        rd_state_d = R_DATA;
      end
      R_DATA: begin
        s_axi_rvalid = 1'b1;
        if (s_axi_rready && (rd_beat_q == rd_arlen_q)) rd_state_d = R_IDLE;
      end
      default: rd_state_d = R_IDLE;
    endcase
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      rd_state_q   <= R_IDLE;
      rd_id_q      <= '0;
      rd_idx_q     <= '0;
      rd_arlen_q   <= '0;
      rd_beat_q    <= '0;
      rd_addr2_q   <= 1'b0;
      rd_illegal_q <= 1'b0;
    end else begin
      rd_state_q <= rd_state_d;
      if (rd_state_q == R_IDLE && s_axi_arvalid) begin
        rd_id_q    <= s_axi_arid;
        rd_arlen_q <= s_axi_arlen;
        rd_beat_q  <= '0;
        rd_addr2_q <= s_axi_araddr[2];
        rd_idx_q   <= bram_index(s_axi_araddr);
        // SLVERR: non-INCR / wrong size / misaligned multi-beat for 64-bit.
        rd_illegal_q <= (s_axi_arburst != 2'b01) ||
                        (s_axi_arsize  != 3'b010) ||
                        (DATA_WIDTH == 64 && s_axi_araddr[2] && s_axi_arlen != 8'd0);
      end
      if (rd_handshake) begin
        rd_beat_q <= rd_beat_q + 8'd1;
        if (rd_advance_idx)
          rd_idx_q <= rd_idx_next;
      end
    end
  end

  // -- Arbiter port B output ------------------------------------
  // b_req held during all BRAM-active states. Dropped in W_RESP.
  assign b_req = (wr_state_q == W_BURST) ||
                 (rd_state_q == R_ADDR)  || (rd_state_q == R_DATA);

  always_comb begin
    // Default: drive read address. In R_ADDR drive rd_idx_q (current=base);
    // in R_DATA drive rd_idx_next (one cycle ahead so BRAM is parked on the
    // word we will need at the next cycle, modulo back-pressure).
    if (rd_state_q == R_ADDR)
      b_addr = rd_idx_q;
    else
      b_addr = rd_idx_next;

    b_wdata = '0;
    b_we    = 1'b0;
    if (wr_handshake) begin
      b_addr = wr_idx_q;
      if (DATA_WIDTH == 64) begin
        b_wdata = {s_axi_wdata, wr_lo_q};      // {hi_beat, latched_lo}
        b_we    = wr_parity_now && !wr_illegal_q && !running_i;
      end else begin
        b_wdata = extract_wdata(s_axi_wdata);
        b_we    = (s_axi_wstrb != 4'h0) && !wr_illegal_q && !running_i;
      end
    end
  end

endmodule
