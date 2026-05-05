// 32-bit AXI4 burst slave for instruction BRAM (write-only).
//
// Accepts AXI4 INCR burst writes and assembles 64-bit IBRAM words from
// consecutive 32-bit beats: lo[31:0] then hi[63:32].
// Each hi-beat fires one IBRAM write; IBRAM address auto-increments per 64-bit word.
//
// The module is write-only.  All read requests return SLVERR immediately.
//
// Beat <-> IBRAM word mapping (32-bit AXI bus, 8-byte IBRAM words):
//   Absolute beat parity = AWADDR[2] XOR wr_beat_q[0]
//     parity 0 (lo beat): wdata -> wr_lo_q
//     parity 1 (hi beat): {wdata, wr_lo_q} -> instr_mem[ibram_addr_o]
//   IBRAM word index = AWADDR[$clog2(INSTR_DEPTH)+2:3].
//   NOTE: requires $clog2(INSTR_DEPTH) <= 17 so the index field [BAW+2:3]
//         does not overlap the GP1 address-space selector bit [20].
//
// Single-beat transactions are supported: the PS7 may issue each 32-bit volatile
// store as a separate AWLEN=0 transaction.  AWADDR[2]=0 is a lo-beat; AWADDR[2]=1
// is a hi-beat that fires WE using the wr_lo_q latched by the prior lo-beat
// transaction.  Multi-beat bursts starting at AWADDR[2]=1 (misaligned) -> SLVERR.
//
// b_req is held from W_BURST through W_RESP for the IBRAM host-port arbiter.
//
// Protocol:
//   - AXI4, 32-bit data bus
//   - INCR bursts only; non-INCR -> SLVERR
//   - Burst writes gated by running_i; beats accepted but WE is inhibited and SLVERR sticky
//   - AWADDR[2]=1 with AWLEN>0 (misaligned multi-beat start) -> SLVERR
//   - AWADDR[2]=1 with AWLEN=0 (single hi-beat) -> OK, WE fires

module accel_ibram_burst
  import config_pkg::*;
#(
  parameter int AXI_ADDR_WIDTH = 32,
  parameter int AXI_ID_WIDTH   = 4
) (
  input  logic clk_i,
  input  logic rst_ni,

  input  logic running_i,

  // -- AXI4 slave (32-bit data) ----------------------------------------
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

  // -- Read channel (returns SLVERR) -----------------------------------
  input  logic [AXI_ID_WIDTH-1:0]   s_axi_arid,
  input  logic [AXI_ADDR_WIDTH-1:0] s_axi_araddr,
  input  logic [7:0]                s_axi_arlen,
  input  logic [2:0]                s_axi_arsize,
  input  logic [1:0]                s_axi_arburst,
  input  logic                      s_axi_arvalid,
  output logic                      s_axi_arready,

  output logic [AXI_ID_WIDTH-1:0]   s_axi_rid,
  output logic [1:0]                s_axi_rresp,
  output logic                      s_axi_rlast,
  output logic                      s_axi_rvalid,
  input  logic                      s_axi_rready,

  // -- IBRAM host port -------------------------------------------------
  output logic                           b_req,
  output logic [$clog2(INSTR_DEPTH)-1:0] ibram_addr_o,
  output logic [63:0]                    ibram_wdata_o,
  output logic                           ibram_we_o,
  input  logic [63:0]                    ibram_rdata_i   // unused (write-only slave)
);

  localparam int BAW = $clog2(INSTR_DEPTH);

  // Guard: index field [BAW+2:3] must not overlap GP1 selector bit [20].
  // synthesis translate_off
  initial begin
    if (BAW + 2 >= 20)
      $fatal(1, "accel_ibram_burst: INSTR_DEPTH too large; BAW+2 >= 20 overlaps GP1 demux bit");
  end
  // synthesis translate_on

  // Extract IBRAM word index (8-byte words) from AXI byte address.
  function automatic logic [BAW-1:0] ibram_index(logic [AXI_ADDR_WIDTH-1:0] a);
    return a[BAW+2:3];
  endfunction

  // -- Write FSM -------------------------------------------------------
  typedef enum logic [1:0] { W_IDLE, W_BURST, W_RESP } wr_state_t;
  wr_state_t wr_state_q, wr_state_d;

  logic [AXI_ID_WIDTH-1:0] wr_id_q;
  logic [BAW-1:0]          wr_ibram_addr_q;
  logic [7:0]              wr_awlen_q;
  logic [7:0]              wr_beat_q;
  logic                    wr_addr2_q;   // AWADDR[2] latched at AW: lo/hi start parity
  logic                    wr_illegal_q;
  logic                    wr_slverr_q;
  logic [31:0]             wr_lo_q;

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
      wr_state_q      <= W_IDLE;
      wr_id_q         <= '0;
      wr_ibram_addr_q <= '0;
      wr_awlen_q      <= '0;
      wr_beat_q       <= '0;
      wr_addr2_q      <= 1'b0;
      wr_illegal_q    <= 1'b0;
      wr_slverr_q     <= 1'b0;
      wr_lo_q         <= '0;
    end else begin
      wr_state_q <= wr_state_d;
      if (wr_state_q == W_IDLE && s_axi_awvalid) begin
        wr_id_q         <= s_axi_awid;
        wr_awlen_q      <= s_axi_awlen;
        wr_beat_q       <= '0;
        wr_slverr_q     <= 1'b0;
        wr_addr2_q      <= s_axi_awaddr[2];
        wr_ibram_addr_q <= ibram_index(s_axi_awaddr);
        // SLVERR: non-INCR burst, non-32-bit beat size, or AWADDR[2]=1 with multi-beat burst (misaligned
        // start).  Single-beat (AWLEN=0) with AWADDR[2]=1 is a lone hi-beat and
        // is legal: WE fires using wr_lo_q latched by the prior lo-beat transaction.
        wr_illegal_q    <= (s_axi_awburst != 2'b01) ||
                           (s_axi_awsize != 3'b010) ||
                           (s_axi_awaddr[2] && s_axi_awlen != 8'd0);
        if ((s_axi_awburst != 2'b01) ||
            (s_axi_awsize != 3'b010) ||
            (s_axi_awaddr[2] && s_axi_awlen != 8'd0))
          wr_slverr_q <= 1'b1;
      end
      if (wr_state_q == W_BURST && s_axi_wvalid) begin
        wr_beat_q <= wr_beat_q + 8'd1;
        if ((wr_beat_q == wr_awlen_q) != s_axi_wlast)
          wr_slverr_q <= 1'b1;
        if (s_axi_wstrb != 4'hF && s_axi_wstrb != 4'h0)
          wr_slverr_q <= 1'b1;
        if (!(wr_addr2_q ^ wr_beat_q[0])) begin
          // Lo beat (absolute parity 0): latch lower half
          wr_lo_q <= s_axi_wdata;
        end else begin
          // Hi beat (absolute parity 1): word written; advance address for next word
          wr_ibram_addr_q <= wr_ibram_addr_q + BAW'(1);
        end
      end
      // Sticky SLVERR if running during a write burst (data silently dropped)
      if (wr_state_q == W_BURST && running_i) wr_slverr_q <= 1'b1;
    end
  end

  // b_req held only during W_BURST (while beats are being written to IBRAM).
  // Dropped in W_RESP: no BRAM access needed while waiting for BVALID ack.
  assign b_req = (wr_state_q == W_BURST);

  // IBRAM write outputs: address is pre-edge value (correct current word)
  // ibram_wdata_o: {hi_beat_data, latched_lo}
  assign ibram_addr_o  = wr_ibram_addr_q;
  assign ibram_wdata_o = {s_axi_wdata, wr_lo_q};
  assign ibram_we_o    = (wr_state_q == W_BURST) && s_axi_wvalid
                         && (wr_addr2_q ^ wr_beat_q[0]) && !wr_illegal_q && !running_i;

  // -- Read FSM (returns SLVERR for all reads) -------------------------
  typedef enum logic { R_IDLE, R_DATA } rd_state_t;
  rd_state_t rd_state_q, rd_state_d;

  logic [AXI_ID_WIDTH-1:0] rd_id_q;
  logic [7:0]              rd_arlen_q;
  logic [7:0]              rd_beat_q;

  always_comb begin
    rd_state_d    = rd_state_q;
    s_axi_arready = 1'b0;
    s_axi_rvalid  = 1'b0;
    s_axi_rid     = rd_id_q;
    s_axi_rresp   = 2'b10;  // SLVERR always
    s_axi_rlast   = (rd_beat_q == rd_arlen_q);

    unique case (rd_state_q)
      R_IDLE: begin
        s_axi_arready = 1'b1;
        if (s_axi_arvalid) rd_state_d = R_DATA;
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
      rd_state_q <= R_IDLE;
      rd_id_q    <= '0;
      rd_arlen_q <= '0;
      rd_beat_q  <= '0;
    end else begin
      rd_state_q <= rd_state_d;
      if (rd_state_q == R_IDLE && s_axi_arvalid) begin
        rd_id_q    <= s_axi_arid;
        rd_arlen_q <= s_axi_arlen;
        rd_beat_q  <= '0;
      end
      if (rd_state_q == R_DATA && s_axi_rready)
        rd_beat_q <= rd_beat_q + 8'd1;
    end
  end

  // suppress unused-input warning for ibram_rdata_i
  logic unused_rdata;
  assign unused_rdata = |ibram_rdata_i;

endmodule
