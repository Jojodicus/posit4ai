// 32-bit AXI4 burst slave for data BRAM (GP1 path).
//
// Maps the entire data BRAM as a flat, word-addressable memory window.
// The host (PS7 CPU via S_AXI_GP1) performs AXI4 INCR burst memcpy to load
// or read back data.
//
// Beat <-> BRAM word mapping (32-bit AXI bus):
//   DATA_WIDTH < 64: one AXI beat = one BRAM word.
//     AWADDR[BAW+1:2] -> base BRAM index.
//     Posit value in WDATA[31:32-DATA_WIDTH]; reads return same layout.
//   DATA_WIDTH == 64: two AXI beats per BRAM word (lo then hi).
//     Beat 2i   (even): WDATA[31:0]  -> wr_lo_q (latch lower half)
//     Beat 2i+1 (odd):  {WDATA, wr_lo_q} -> BRAM[base+i]; WE fires.
//     AWADDR must be 8-byte aligned (AWADDR[2]=0); misaligned -> SLVERR.
//     BRAM word index = AWADDR[BAW+2:3].
//   Reads (DATA_WIDTH==64): even beat returns BRAM[i][31:0];
//     odd beat returns buffered BRAM[i][63:32] from rd_hi_buf_q.
//     Back-pressure safe: beat counter, hi-half capture, and address advance
//     occur only on R-channel handshake (RVALID && RREADY).
//
// Protocol:
//   - AXI4, 32-bit data bus
//   - INCR bursts only; WRAP/FIXED -> SLVERR
//   - Burst writes gated by running_i; beats accepted but WE inhibited, SLVERR sticky
//   - Burst reads always allowed
//   - b_req held from W_BURST / R_ADDR / R_DATA; dropped in W_RESP

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

  logic [AXI_ID_WIDTH-1:0]  wr_id_q;
  logic [BAW-1:0]            wr_base_q;
  logic [7:0]                wr_awlen_q;
  logic [7:0]                wr_beat_q;
  logic                      wr_illegal_q;
  logic                      wr_slverr_q;
  logic [31:0]               wr_lo_q;      // DATA_WIDTH=64: latched lo beat

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
      wr_base_q    <= '0;
      wr_awlen_q   <= '0;
      wr_beat_q    <= '0;
      wr_illegal_q <= 1'b0;
      wr_slverr_q  <= 1'b0;
      wr_lo_q      <= '0;
    end else begin
      wr_state_q <= wr_state_d;
      if (wr_state_q == W_IDLE && s_axi_awvalid) begin
        wr_id_q      <= s_axi_awid;
        wr_awlen_q   <= s_axi_awlen;
        wr_beat_q    <= '0;
        wr_slverr_q  <= 1'b0;
        // SLVERR: non-INCR burst; non-32-bit beat size; misaligned start for DATA_WIDTH=64 (AWADDR[2]=1)
        wr_illegal_q <= (s_axi_awburst != 2'b01) ||
                        (s_axi_awsize  != 3'b010) ||
                        (DATA_WIDTH == 64 && s_axi_awaddr[2]);
        if ((s_axi_awburst != 2'b01) ||
            (s_axi_awsize  != 3'b010) ||
            (DATA_WIDTH == 64 && s_axi_awaddr[2]))
          wr_slverr_q <= 1'b1;
        wr_base_q    <= bram_index(s_axi_awaddr);
      end
      if (wr_state_q == W_BURST && s_axi_wvalid) begin
        wr_beat_q <= wr_beat_q + 8'd1;
        if ((wr_beat_q == wr_awlen_q) != s_axi_wlast)
          wr_slverr_q <= 1'b1;
        if (DATA_WIDTH == 64 && !wr_beat_q[0])
          wr_lo_q <= s_axi_wdata;   // even beat: latch lo half
        if (DATA_WIDTH != 64 && s_axi_wstrb != 4'hF && s_axi_wstrb != 4'h0)
          wr_slverr_q <= 1'b1;
      end
      // Sticky SLVERR if running during a write burst (data silently dropped)
      if (wr_state_q == W_BURST && running_i) wr_slverr_q <= 1'b1;
    end
  end

  // -- Read FSM (R_IDLE -> R_ADDR -> R_DATA -> R_IDLE) ------------
  // R_ADDR: assert b_req, drive addr[word=0]; BRAM output ready next cycle.
  // R_DATA: RVALID=1; pre-fetch next address each cycle.
  //   DATA_WIDTH=64: even beats serve b_rdata[31:0] and buffer b_rdata[63:32];
  //                  odd beats serve rd_hi_buf_q and pre-fetch next word.

  typedef enum logic [1:0] { R_IDLE, R_ADDR, R_DATA } rd_state_t;
  rd_state_t rd_state_q, rd_state_d;

  logic [AXI_ID_WIDTH-1:0]  rd_id_q;
  logic [BAW-1:0]            rd_base_q;
  logic [7:0]                rd_arlen_q;
  logic [7:0]                rd_beat_q;
  logic                      rd_illegal_q;
  logic [31:0]               rd_hi_buf_q;  // DATA_WIDTH=64: hi half of current BRAM word
  logic                      rd_fire;

  logic [BAW-1:0] rd_bram_addr;
  assign rd_fire = (rd_state_q == R_DATA) && s_axi_rvalid && s_axi_rready;

  always_comb begin
    rd_state_d    = rd_state_q;
    s_axi_arready = 1'b0;
    s_axi_rvalid  = 1'b0;
    s_axi_rid     = rd_id_q;
    s_axi_rresp   = rd_illegal_q ? 2'b10 : 2'b00;
    s_axi_rlast   = (rd_beat_q == rd_arlen_q);
    s_axi_rdata   = '0;

    if (DATA_WIDTH == 64) begin
      // Even beats: output lo half; odd beats: output buffered hi half.
      s_axi_rdata  = rd_beat_q[0] ? rd_hi_buf_q : b_rdata[31:0];
      // Address derives from handshake-tracked beat index (rd_beat_q).
      // When RREADY is low rd_beat_q does not advance, so the BRAM address
      // and the even/odd data pairing remain stable under back-pressure.
      rd_bram_addr = rd_base_q + BAW'((rd_beat_q + 8'd1) >> 1);
    end else begin
      s_axi_rdata  = pack_rdata(b_rdata);
      rd_bram_addr = rd_base_q + BAW'(rd_beat_q + 8'd1);
    end

    unique case (rd_state_q)
      R_IDLE: begin
        s_axi_arready = 1'b1;
        if (s_axi_arvalid) rd_state_d = R_ADDR;
        rd_bram_addr = bram_index(s_axi_araddr);  // peek-ahead (b_req=0, harmless)
      end
      R_ADDR: begin
        rd_bram_addr = rd_base_q;   // issue word-0 address; output ready next cycle
        rd_state_d   = R_DATA;
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
      rd_base_q    <= '0;
      rd_arlen_q   <= '0;
      rd_beat_q    <= '0;
      rd_illegal_q <= 1'b0;
      rd_hi_buf_q  <= '0;
    end else begin
      rd_state_q <= rd_state_d;
      if (rd_state_q == R_IDLE && s_axi_arvalid) begin
        rd_id_q      <= s_axi_arid;
        rd_arlen_q   <= s_axi_arlen;
        rd_beat_q    <= '0;
        rd_illegal_q <= (s_axi_arburst != 2'b01) || (s_axi_arsize != 3'b010);
        rd_base_q    <= bram_index(s_axi_araddr);
      end
      if (rd_fire) begin
        rd_beat_q <= rd_beat_q + 8'd1;
        // DATA_WIDTH=64: capture hi half on even beats while b_rdata holds current word
        if (DATA_WIDTH == 64 && !rd_beat_q[0])
          rd_hi_buf_q <= b_rdata[63:32];
      end
    end
  end

  // -- Arbiter port B output ------------------------------------
  // b_req held during all BRAM-active states.
  // Dropped in W_RESP: no BRAM access while waiting for BVALID handshake.
  assign b_req = (wr_state_q == W_BURST) ||
                 (rd_state_q == R_ADDR)  || (rd_state_q == R_DATA);

  always_comb begin
    b_addr  = rd_bram_addr;
    b_wdata = '0;
    b_we    = 1'b0;
    if (wr_state_q == W_BURST && s_axi_wvalid) begin
      if (DATA_WIDTH == 64) begin
        b_addr  = wr_base_q + BAW'(wr_beat_q >> 1);
        b_wdata = {s_axi_wdata, wr_lo_q};   // {hi_beat[31:0], latched_lo[31:0]}
        b_we    = wr_beat_q[0] && !wr_illegal_q && !running_i;
      end else begin
        b_addr  = wr_base_q + BAW'(wr_beat_q);
        b_wdata = extract_wdata(s_axi_wdata);
        b_we    = (s_axi_wstrb != 4'h0) && !wr_illegal_q && !running_i;
      end
    end
  end

endmodule
