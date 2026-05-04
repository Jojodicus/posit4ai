// full implementation top (PS7 + accel_axi + accel_core).
// Clocking: 100 MHz crystal (GCLK/Y9) -> clk_wiz_0 -> clk_core (CLOCK_FREQ_MHZ)
//                                                    -> clk_bram (2x clk_core).
// clk_bram drives M_AXI_GP0/GP1_ACLK (via PL_CLK BD port), accel_axi,
// accel_axi_burst, and accel_ibram_burst, doubling AXI throughput vs clk_core.
// accel_core runs at clk_core (datapath + sequencer) and clk_bram (BRAMs).
//
// CDC paths:
//   accel_core.running_o / done_o  (clk_core -> clk_bram): 2-FF synchronizers
//   accel_axi.start_o              (clk_bram -> clk_core): toggle + 3-FF sync
//   accel_axi.sw_reset_o           (clk_bram -> clk_core): toggle + 3-FF sync
//
// GP1 AXI4 address demux (AWADDR/ARADDR bit 20):
//   bit 20 = 0 -> DBRAM burst (accel_axi_burst)
//   bit 20 = 1 -> IBRAM burst (accel_ibram_burst)
// Both slaves share the single GP1 bus; only one transaction active at a time.

module zynq_accel_top (
  input  logic        GCLK,
  inout  logic [14:0] DDR_addr,
  inout  logic [2:0]  DDR_ba,
  inout  logic        DDR_cas_n,
  inout  logic        DDR_ck_n,
  inout  logic        DDR_ck_p,
  inout  logic        DDR_cke,
  inout  logic        DDR_cs_n,
  inout  logic [3:0]  DDR_dm,
  inout  logic [31:0] DDR_dq,
  inout  logic [3:0]  DDR_dqs_n,
  inout  logic [3:0]  DDR_dqs_p,
  inout  logic        DDR_odt,
  inout  logic        DDR_ras_n,
  inout  logic        DDR_reset_n,
  inout  logic        DDR_we_n,
  inout  logic [53:0] FIXED_IO_mio,
  inout  logic        FIXED_IO_ddr_vrn,
  inout  logic        FIXED_IO_ddr_vrp,
  inout  logic        FIXED_IO_ps_clk,
  inout  logic        FIXED_IO_ps_porb,
  inout  logic        FIXED_IO_ps_srstb
);

  import config_pkg::*;

  // -- Clocking: one MMCM for both core and BRAM -----------------------
  logic clk_core, clk_bram, clk_locked;

  clk_wiz_0 u_clk_wiz (
    .clk_in1  ( GCLK       ),
    .reset    ( 1'b0       ),
    .clk_out1 ( clk_core   ),
    .clk_out2 ( clk_bram   ),
    .locked   ( clk_locked )
  );

  // -- POR shift-register reset ----------------------------------------
  // Holds peripheral_aresetn (and DCM_LOCKED fed into the BD) low for 8
  // clk_bram cycles after clk_locked goes high.  With USE_SAFE_CLOCK_STARTUP,
  // clk_bram only starts after MMCM lock, so the SR shifts 0->1 starting from
  // cycle 0.  Without SAFE_CLOCK_STARTUP it still works: clk_locked=0 keeps
  // the SR at 0 until lock.
  // peripheral_aresetn is computed here, NOT exported from the BD wrapper.
  // Exporting it as a BD feedthrough output port (O port wired to I port) can
  // produce an undriven net in the generated wrapper, permanently asserting
  // the AXI slave resets and deadlocking all GP0 transactions.
  logic [7:0]  por_sr_q;
  always_ff @(posedge clk_bram) por_sr_q <= {por_sr_q[6:0], clk_locked};
  logic        pl_reset_n;
  assign pl_reset_n = &por_sr_q;  // 1 after 8 consecutive clk_bram cycles with clk_locked=1

  // -- Block design: PS7 + axi_protocol_converter ----------------------
  // PL_CLK = clk_bram: M_AXI_GP0/GP1_ACLK run at 2x clk_core.
  // peripheral_aresetn = pl_reset_n (derived above, not from BD).
  logic        peripheral_aresetn;
  assign peripheral_aresetn = pl_reset_n;

  // AXI-Lite master (GP0 via protocol converter)
  logic [31:0] M_AXI_LITE_awaddr,  M_AXI_LITE_araddr,  M_AXI_LITE_wdata,  M_AXI_LITE_rdata;
  logic [3:0]  M_AXI_LITE_wstrb;
  logic [1:0]  M_AXI_LITE_bresp,   M_AXI_LITE_rresp;
  logic        M_AXI_LITE_awvalid, M_AXI_LITE_awready;
  logic        M_AXI_LITE_wvalid,  M_AXI_LITE_wready;
  logic        M_AXI_LITE_bvalid,  M_AXI_LITE_bready;
  logic        M_AXI_LITE_arvalid, M_AXI_LITE_arready;
  logic        M_AXI_LITE_rvalid,  M_AXI_LITE_rready;
  logic [2:0]  M_AXI_LITE_arprot_unused, M_AXI_LITE_awprot_unused;

  // AXI4 burst master (GP1 via protocol converter, 32-bit data, 12-bit IDs)
  logic [11:0] M_AXI_BURST_awid,   M_AXI_BURST_arid,   M_AXI_BURST_bid,   M_AXI_BURST_rid;
  logic [31:0] M_AXI_BURST_awaddr, M_AXI_BURST_araddr, M_AXI_BURST_wdata, M_AXI_BURST_rdata;
  logic [7:0]  M_AXI_BURST_awlen,  M_AXI_BURST_arlen;
  logic [2:0]  M_AXI_BURST_awsize, M_AXI_BURST_arsize;
  logic [1:0]  M_AXI_BURST_awburst,M_AXI_BURST_arburst,M_AXI_BURST_bresp, M_AXI_BURST_rresp;
  logic [3:0]  M_AXI_BURST_wstrb;
  logic        M_AXI_BURST_awlock, M_AXI_BURST_arlock;
  logic [3:0]  M_AXI_BURST_awcache,M_AXI_BURST_arcache,M_AXI_BURST_awqos, M_AXI_BURST_arqos;
  logic [2:0]  M_AXI_BURST_awprot, M_AXI_BURST_arprot;
  logic        M_AXI_BURST_awvalid,M_AXI_BURST_awready;
  logic        M_AXI_BURST_wlast,  M_AXI_BURST_wvalid, M_AXI_BURST_wready;
  logic        M_AXI_BURST_bvalid, M_AXI_BURST_bready;
  logic        M_AXI_BURST_arvalid,M_AXI_BURST_arready;
  logic        M_AXI_BURST_rlast,  M_AXI_BURST_rvalid, M_AXI_BURST_rready;
  logic [3:0]  M_AXI_BURST_awregion_unused, M_AXI_BURST_arregion_unused;

  zynq_ps_wrapper u_zynq_ps (
    .DDR_0_addr           ( DDR_addr             ),
    .DDR_0_ba             ( DDR_ba               ),
    .DDR_0_cas_n          ( DDR_cas_n            ),
    .DDR_0_ck_n           ( DDR_ck_n             ),
    .DDR_0_ck_p           ( DDR_ck_p             ),
    .DDR_0_cke            ( DDR_cke              ),
    .DDR_0_cs_n           ( DDR_cs_n             ),
    .DDR_0_dm             ( DDR_dm               ),
    .DDR_0_dq             ( DDR_dq               ),
    .DDR_0_dqs_n          ( DDR_dqs_n            ),
    .DDR_0_dqs_p          ( DDR_dqs_p            ),
    .DDR_0_odt            ( DDR_odt              ),
    .DDR_0_ras_n          ( DDR_ras_n            ),
    .DDR_0_reset_n        ( DDR_reset_n          ),
    .DDR_0_we_n           ( DDR_we_n             ),
    .FIXED_IO_0_mio       ( FIXED_IO_mio         ),
    .FIXED_IO_0_ddr_vrn   ( FIXED_IO_ddr_vrn     ),
    .FIXED_IO_0_ddr_vrp   ( FIXED_IO_ddr_vrp     ),
    .FIXED_IO_0_ps_clk    ( FIXED_IO_ps_clk      ),
    .FIXED_IO_0_ps_porb   ( FIXED_IO_ps_porb     ),
    .FIXED_IO_0_ps_srstb  ( FIXED_IO_ps_srstb    ),
    // PL_CLK = clk_bram: M_AXI_GP0/GP1_ACLK run at 2x clk_core.
    .PL_CLK               ( clk_bram             ),
    // pl_reset_n: POR SR output (see above); resets axi_pc/axi_pc_gp1 inside BD.
    .DCM_LOCKED           ( pl_reset_n           ),
    .M_AXI_LITE_awaddr    ( M_AXI_LITE_awaddr    ),
    .M_AXI_LITE_awprot    ( M_AXI_LITE_awprot_unused ),
    .M_AXI_LITE_awvalid   ( M_AXI_LITE_awvalid   ),
    .M_AXI_LITE_awready   ( M_AXI_LITE_awready   ),
    .M_AXI_LITE_wdata     ( M_AXI_LITE_wdata     ),
    .M_AXI_LITE_wstrb     ( M_AXI_LITE_wstrb     ),
    .M_AXI_LITE_wvalid    ( M_AXI_LITE_wvalid    ),
    .M_AXI_LITE_wready    ( M_AXI_LITE_wready    ),
    .M_AXI_LITE_bresp     ( M_AXI_LITE_bresp     ),
    .M_AXI_LITE_bvalid    ( M_AXI_LITE_bvalid    ),
    .M_AXI_LITE_bready    ( M_AXI_LITE_bready    ),
    .M_AXI_LITE_araddr    ( M_AXI_LITE_araddr    ),
    .M_AXI_LITE_arprot    ( M_AXI_LITE_arprot_unused ),
    .M_AXI_LITE_arvalid   ( M_AXI_LITE_arvalid   ),
    .M_AXI_LITE_arready   ( M_AXI_LITE_arready   ),
    .M_AXI_LITE_rdata     ( M_AXI_LITE_rdata     ),
    .M_AXI_LITE_rresp     ( M_AXI_LITE_rresp     ),
    .M_AXI_LITE_rvalid    ( M_AXI_LITE_rvalid    ),
    .M_AXI_LITE_rready    ( M_AXI_LITE_rready    ),
    .M_AXI_BURST_awid     ( M_AXI_BURST_awid     ),
    .M_AXI_BURST_awaddr   ( M_AXI_BURST_awaddr   ),
    .M_AXI_BURST_awlen    ( M_AXI_BURST_awlen    ),
    .M_AXI_BURST_awsize   ( M_AXI_BURST_awsize   ),
    .M_AXI_BURST_awburst  ( M_AXI_BURST_awburst  ),
    .M_AXI_BURST_awlock   ( M_AXI_BURST_awlock   ),
    .M_AXI_BURST_awcache  ( M_AXI_BURST_awcache  ),
    .M_AXI_BURST_awprot   ( M_AXI_BURST_awprot   ),
    .M_AXI_BURST_awqos    ( M_AXI_BURST_awqos    ),
    .M_AXI_BURST_awvalid  ( M_AXI_BURST_awvalid  ),
    .M_AXI_BURST_awready  ( M_AXI_BURST_awready  ),
    .M_AXI_BURST_wdata    ( M_AXI_BURST_wdata    ),
    .M_AXI_BURST_wstrb    ( M_AXI_BURST_wstrb    ),
    .M_AXI_BURST_wlast    ( M_AXI_BURST_wlast    ),
    .M_AXI_BURST_wvalid   ( M_AXI_BURST_wvalid   ),
    .M_AXI_BURST_wready   ( M_AXI_BURST_wready   ),
    .M_AXI_BURST_bid      ( M_AXI_BURST_bid      ),
    .M_AXI_BURST_bresp    ( M_AXI_BURST_bresp    ),
    .M_AXI_BURST_bvalid   ( M_AXI_BURST_bvalid   ),
    .M_AXI_BURST_bready   ( M_AXI_BURST_bready   ),
    .M_AXI_BURST_arid     ( M_AXI_BURST_arid     ),
    .M_AXI_BURST_araddr   ( M_AXI_BURST_araddr   ),
    .M_AXI_BURST_arlen    ( M_AXI_BURST_arlen    ),
    .M_AXI_BURST_arsize   ( M_AXI_BURST_arsize   ),
    .M_AXI_BURST_arburst  ( M_AXI_BURST_arburst  ),
    .M_AXI_BURST_arlock   ( M_AXI_BURST_arlock   ),
    .M_AXI_BURST_arcache  ( M_AXI_BURST_arcache  ),
    .M_AXI_BURST_arprot   ( M_AXI_BURST_arprot   ),
    .M_AXI_BURST_arqos    ( M_AXI_BURST_arqos    ),
    .M_AXI_BURST_arvalid  ( M_AXI_BURST_arvalid  ),
    .M_AXI_BURST_arready  ( M_AXI_BURST_arready  ),
    .M_AXI_BURST_rid      ( M_AXI_BURST_rid      ),
    .M_AXI_BURST_rdata    ( M_AXI_BURST_rdata    ),
    .M_AXI_BURST_rresp    ( M_AXI_BURST_rresp    ),
    .M_AXI_BURST_rlast    ( M_AXI_BURST_rlast    ),
    .M_AXI_BURST_rvalid   ( M_AXI_BURST_rvalid   ),
    .M_AXI_BURST_rready   ( M_AXI_BURST_rready   )
  );

  // -----------------------------------------------------------------------
  // Internal control signals
  // -----------------------------------------------------------------------

  // accel_axi control outputs (clk_bram domain)
  logic accel_start_bram;      // start pulse from AXI-Lite slave
  logic accel_sw_reset_bram;   // software reset pulse from AXI-Lite slave

  // accel_core status (clk_core domain)
  logic accel_done_core, accel_running_core;

  // Synchronized status for clk_bram consumers (AXI slaves)
  logic accel_done_bram, accel_running_bram;

  // Synchronized control for clk_core consumer (accel_core)
  logic start_core, sw_reset_core;

  // -----------------------------------------------------------------------
  // CDC: accel_core status (clk_core -> clk_bram), 2-FF synchronizers
  // -----------------------------------------------------------------------
  logic [1:0] running_sync_q, done_sync_q;
  always_ff @(posedge clk_bram or negedge peripheral_aresetn) begin
    if (!peripheral_aresetn) begin
      running_sync_q <= 2'b0;
      done_sync_q    <= 2'b0;
    end else begin
      running_sync_q <= {running_sync_q[0], accel_running_core};
      done_sync_q    <= {done_sync_q[0],    accel_done_core};
    end
  end
  assign accel_running_bram = running_sync_q[1];
  assign accel_done_bram    = done_sync_q[1];

  // -----------------------------------------------------------------------
  // CDC: start and sw_reset requests (clk_bram -> clk_core) with ack return.
  // KISS handshake: BRAM side holds req high until CORE side emits one pulse
  // and flips ack toggle; BRAM side then clears req.
  // -----------------------------------------------------------------------
  logic start_req_q, sw_reset_req_q;
  logic start_ack_toggle_core_q, sw_reset_ack_toggle_core_q;
  logic [1:0] start_req_sync_q, sw_reset_req_sync_q;
  logic [1:0] start_ack_sync_q, sw_reset_ack_sync_q;
  logic start_req_seen_core_q, sw_reset_req_seen_core_q;
  logic start_ack_seen_bram_q, sw_reset_ack_seen_bram_q;

  always_ff @(posedge clk_bram or negedge peripheral_aresetn) begin
    if (!peripheral_aresetn) begin
      start_req_q            <= 1'b0;
      sw_reset_req_q         <= 1'b0;
      start_ack_sync_q       <= 2'b0;
      sw_reset_ack_sync_q    <= 2'b0;
      start_ack_seen_bram_q  <= 1'b0;
      sw_reset_ack_seen_bram_q <= 1'b0;
    end else begin
      start_ack_sync_q    <= {start_ack_sync_q[0],    start_ack_toggle_core_q};
      sw_reset_ack_sync_q <= {sw_reset_ack_sync_q[0], sw_reset_ack_toggle_core_q};

      if (accel_start_bram)
        start_req_q <= 1'b1;
      else if (start_ack_sync_q[1] != start_ack_seen_bram_q) begin
        start_req_q           <= 1'b0;
        start_ack_seen_bram_q <= start_ack_sync_q[1];
      end

      if (accel_sw_reset_bram)
        sw_reset_req_q <= 1'b1;
      else if (sw_reset_ack_sync_q[1] != sw_reset_ack_seen_bram_q) begin
        sw_reset_req_q           <= 1'b0;
        sw_reset_ack_seen_bram_q <= sw_reset_ack_sync_q[1];
      end
    end
  end

  always_ff @(posedge clk_core or negedge peripheral_aresetn) begin
    if (!peripheral_aresetn) begin
      start_req_sync_q         <= 2'b0;
      sw_reset_req_sync_q      <= 2'b0;
      start_req_seen_core_q    <= 1'b0;
      sw_reset_req_seen_core_q <= 1'b0;
      start_ack_toggle_core_q  <= 1'b0;
      sw_reset_ack_toggle_core_q <= 1'b0;
    end else begin
      start_req_sync_q    <= {start_req_sync_q[0],    start_req_q};
      sw_reset_req_sync_q <= {sw_reset_req_sync_q[0], sw_reset_req_q};

      if (start_req_sync_q[1] && !start_req_seen_core_q) begin
        start_req_seen_core_q   <= 1'b1;
        start_ack_toggle_core_q <= ~start_ack_toggle_core_q;
      end else if (!start_req_sync_q[1]) begin
        start_req_seen_core_q <= 1'b0;
      end

      if (sw_reset_req_sync_q[1] && !sw_reset_req_seen_core_q) begin
        sw_reset_req_seen_core_q   <= 1'b1;
        sw_reset_ack_toggle_core_q <= ~sw_reset_ack_toggle_core_q;
      end else if (!sw_reset_req_sync_q[1]) begin
        sw_reset_req_seen_core_q <= 1'b0;
      end
    end
  end

  assign start_core    = start_req_sync_q[1]    && !start_req_seen_core_q;
  assign sw_reset_core = sw_reset_req_sync_q[1] && !sw_reset_req_seen_core_q;

  // -----------------------------------------------------------------------
  // GP1 address demux: AWADDR/ARADDR bit 20 selects DBRAM vs IBRAM burst
  // -----------------------------------------------------------------------

  // dburst_* : signals for accel_axi_burst (DBRAM, 64-bit data port)
  logic [3:0]  dburst_awid,   dburst_arid,   dburst_bid,   dburst_rid;
  logic [31:0] dburst_awaddr, dburst_araddr;
  logic [7:0]  dburst_awlen,  dburst_arlen;
  logic [2:0]  dburst_awsize, dburst_arsize;
  logic [1:0]  dburst_awburst,dburst_arburst;
  logic        dburst_awvalid,dburst_awready;
  logic [63:0] dburst_wdata;
  logic [7:0]  dburst_wstrb;
  logic        dburst_wlast,  dburst_wvalid, dburst_wready;
  logic [1:0]  dburst_bresp;
  logic        dburst_bvalid, dburst_bready;
  logic        dburst_arvalid,dburst_arready;
  logic [63:0] dburst_rdata;
  logic [1:0]  dburst_rresp;
  logic        dburst_rlast,  dburst_rvalid, dburst_rready;

  // iburst_* : signals for accel_ibram_burst (IBRAM, 32-bit data port)
  logic [3:0]  iburst_awid,   iburst_arid,   iburst_bid,   iburst_rid;
  logic [31:0] iburst_awaddr, iburst_araddr;
  logic [7:0]  iburst_awlen,  iburst_arlen;
  logic [2:0]  iburst_awsize, iburst_arsize;
  logic [1:0]  iburst_awburst,iburst_arburst;
  logic        iburst_awvalid,iburst_awready;
  logic        iburst_wlast,  iburst_wvalid, iburst_wready;
  logic [1:0]  iburst_bresp;
  logic        iburst_bvalid, iburst_bready;
  logic        iburst_arvalid,iburst_arready;
  logic [1:0]  iburst_rresp;
  logic        iburst_rlast,  iburst_rvalid, iburst_rready;

  // Write-path demux state (exactly one outstanding write transaction)
  logic gwr_active_q, gwr_sel_q;  // sel: 0=dburst, 1=iburst
  logic aw_fire_dburst, aw_fire_iburst;
  logic b_fire_dburst, b_fire_iburst;

  assign aw_fire_dburst = (!gwr_active_q && M_AXI_BURST_awvalid && !M_AXI_BURST_awaddr[20] && dburst_awready);
  assign aw_fire_iburst = (!gwr_active_q && M_AXI_BURST_awvalid &&  M_AXI_BURST_awaddr[20] && iburst_awready);
  assign b_fire_dburst  = ( gwr_active_q && !gwr_sel_q && dburst_bvalid && M_AXI_BURST_bready);
  assign b_fire_iburst  = ( gwr_active_q &&  gwr_sel_q && iburst_bvalid && M_AXI_BURST_bready);

  always_ff @(posedge clk_bram or negedge peripheral_aresetn) begin
    if (!peripheral_aresetn) begin
      gwr_active_q <= 1'b0;
      gwr_sel_q    <= 1'b0;
    end else begin
      if (aw_fire_dburst) begin
        gwr_active_q <= 1'b1;
        gwr_sel_q    <= 1'b0;
      end else if (aw_fire_iburst) begin
        gwr_active_q <= 1'b1;
        gwr_sel_q    <= 1'b1;
      end else if (b_fire_dburst || b_fire_iburst) begin
        gwr_active_q <= 1'b0;
      end
    end
  end

  // AW channel mux
  always_comb begin
    dburst_awid     = M_AXI_BURST_awid[3:0];
    dburst_awaddr   = M_AXI_BURST_awaddr;
    dburst_awlen    = M_AXI_BURST_awlen;
    dburst_awsize   = M_AXI_BURST_awsize;
    dburst_awburst  = M_AXI_BURST_awburst;
    dburst_awvalid  = 1'b0;
    iburst_awid     = M_AXI_BURST_awid[3:0];
    iburst_awaddr   = M_AXI_BURST_awaddr;
    iburst_awlen    = M_AXI_BURST_awlen;
    iburst_awsize   = M_AXI_BURST_awsize;
    iburst_awburst  = M_AXI_BURST_awburst;
    iburst_awvalid  = 1'b0;
    M_AXI_BURST_awready = 1'b0;
    if (!gwr_active_q) begin
      if (!M_AXI_BURST_awaddr[20]) begin
        dburst_awvalid      = M_AXI_BURST_awvalid;
        M_AXI_BURST_awready = dburst_awready;
      end else begin
        iburst_awvalid      = M_AXI_BURST_awvalid;
        M_AXI_BURST_awready = iburst_awready;
      end
    end
  end

  // W channel: route to selected write transaction (zero-extend 32->64 for dburst)
  assign dburst_wvalid = (!gwr_sel_q && gwr_active_q) ? M_AXI_BURST_wvalid : 1'b0;
  assign iburst_wvalid = ( gwr_sel_q && gwr_active_q) ? M_AXI_BURST_wvalid : 1'b0;
  assign M_AXI_BURST_wready = gwr_active_q
                              ? (!gwr_sel_q ? dburst_wready : iburst_wready)
                              : 1'b0;
  assign dburst_wdata  = {32'b0, M_AXI_BURST_wdata};
  assign dburst_wstrb  = {4'b0,  M_AXI_BURST_wstrb};
  assign dburst_wlast  = M_AXI_BURST_wlast;
  assign iburst_wlast  = M_AXI_BURST_wlast;

  // B channel: mux response from selected write transaction only
  assign M_AXI_BURST_bvalid = gwr_active_q ? (!gwr_sel_q ? dburst_bvalid : iburst_bvalid) : 1'b0;
  assign M_AXI_BURST_bresp  = gwr_active_q ? (!gwr_sel_q ? dburst_bresp  : iburst_bresp ) : 2'b00;
  assign M_AXI_BURST_bid    = gwr_active_q ? {8'b0, (!gwr_sel_q ? dburst_bid : iburst_bid)} : 12'b0;
  assign dburst_bready      = (gwr_active_q && !gwr_sel_q) ? M_AXI_BURST_bready : 1'b0;
  assign iburst_bready      = (gwr_active_q &&  gwr_sel_q) ? M_AXI_BURST_bready : 1'b0;

  // Read-path demux state (exactly one outstanding read transaction)
  logic grd_active_q, grd_sel_q;
  logic ar_fire_dburst, ar_fire_iburst;
  logic r_fire_dburst, r_fire_iburst;

  assign ar_fire_dburst = (!grd_active_q && M_AXI_BURST_arvalid && !M_AXI_BURST_araddr[20] && dburst_arready);
  assign ar_fire_iburst = (!grd_active_q && M_AXI_BURST_arvalid &&  M_AXI_BURST_araddr[20] && iburst_arready);
  assign r_fire_dburst  = ( grd_active_q && !grd_sel_q && dburst_rvalid && M_AXI_BURST_rready && dburst_rlast);
  assign r_fire_iburst  = ( grd_active_q &&  grd_sel_q && iburst_rvalid && M_AXI_BURST_rready && iburst_rlast);

  always_ff @(posedge clk_bram or negedge peripheral_aresetn) begin
    if (!peripheral_aresetn) begin
      grd_active_q <= 1'b0;
      grd_sel_q    <= 1'b0;
    end else begin
      if (ar_fire_dburst) begin
        grd_sel_q    <= 1'b0;
        grd_active_q <= 1'b1;
      end else if (ar_fire_iburst) begin
        grd_sel_q    <= 1'b1;
        grd_active_q <= 1'b1;
      end else if (r_fire_dburst || r_fire_iburst) begin
        grd_active_q <= 1'b0;
      end
    end
  end

  // AR channel mux
  always_comb begin
    dburst_arid     = M_AXI_BURST_arid[3:0];
    dburst_araddr   = M_AXI_BURST_araddr;
    dburst_arlen    = M_AXI_BURST_arlen;
    dburst_arsize   = M_AXI_BURST_arsize;
    dburst_arburst  = M_AXI_BURST_arburst;
    dburst_arvalid  = 1'b0;
    iburst_arid     = M_AXI_BURST_arid[3:0];
    iburst_araddr   = M_AXI_BURST_araddr;
    iburst_arlen    = M_AXI_BURST_arlen;
    iburst_arsize   = M_AXI_BURST_arsize;
    iburst_arburst  = M_AXI_BURST_arburst;
    iburst_arvalid  = 1'b0;
    M_AXI_BURST_arready = 1'b0;
    if (!grd_active_q) begin
      if (!M_AXI_BURST_araddr[20]) begin
        dburst_arvalid      = M_AXI_BURST_arvalid;
        M_AXI_BURST_arready = dburst_arready;
      end else begin
        iburst_arvalid      = M_AXI_BURST_arvalid;
        M_AXI_BURST_arready = iburst_arready;
      end
    end
  end

  // R channel: mux data/resp from selected read transaction only
  assign M_AXI_BURST_rvalid = grd_active_q ? (!grd_sel_q ? dburst_rvalid : iburst_rvalid) : 1'b0;
  assign M_AXI_BURST_rlast  = grd_active_q ? (!grd_sel_q ? dburst_rlast  : iburst_rlast ) : 1'b0;
  assign M_AXI_BURST_rresp  = grd_active_q ? (!grd_sel_q ? dburst_rresp  : iburst_rresp ) : 2'b00;
  assign M_AXI_BURST_rid    = grd_active_q ? {8'b0, (!grd_sel_q ? dburst_rid : iburst_rid)} : 12'b0;
  assign M_AXI_BURST_rdata  = grd_active_q ? (!grd_sel_q ? dburst_rdata[31:0] : 32'b0) : 32'b0;
  assign dburst_rready      = (grd_active_q && !grd_sel_q) ? M_AXI_BURST_rready : 1'b0;
  assign iburst_rready      = (grd_active_q &&  grd_sel_q) ? M_AXI_BURST_rready : 1'b0;

  // -----------------------------------------------------------------------
  // Internal wires
  // -----------------------------------------------------------------------

  // accel_axi -> IBRAM host port (clk_bram domain)
  logic [$clog2(INSTR_DEPTH)-1:0]  ibram_addr;
  logic [63:0]                     ibram_wdata;
  logic                            ibram_we;
  logic [63:0]                     ibram_rdata;

  // accel_ibram_burst -> IBRAM host port (clk_bram domain)
  logic                            iburst_b_req;
  logic [$clog2(INSTR_DEPTH)-1:0]  iburst_b_addr;
  logic [63:0]                     iburst_b_wdata;
  logic                            iburst_b_we;

  // IBRAM host port arbiter (inline): iburst has priority when b_req=1
  logic [$clog2(INSTR_DEPTH)-1:0]  core_ibram_addr;
  logic [63:0]                     core_ibram_wdata;
  logic                            core_ibram_we;
  logic [63:0]                     core_ibram_rdata;

  assign core_ibram_addr  = iburst_b_req ? iburst_b_addr  : ibram_addr;
  assign core_ibram_wdata = iburst_b_req ? iburst_b_wdata : ibram_wdata;
  assign core_ibram_we    = iburst_b_req ? iburst_b_we    : ibram_we;
  assign ibram_rdata      = core_ibram_rdata;

  // accel_axi -> DBRAM arbiter port A (clk_bram domain)
  logic [$clog2(DATA_DEPTH)-1:0]   axi_dbram_addr;
  logic [DATA_WIDTH-1:0]           axi_dbram_wdata;
  logic                            axi_dbram_we;
  logic [DATA_WIDTH-1:0]           axi_dbram_rdata;

  // accel_axi_burst -> DBRAM arbiter port B (clk_bram domain)
  logic                            dburst_b_req;
  logic [$clog2(DATA_DEPTH)-1:0]   dburst_b_addr;
  logic [DATA_WIDTH-1:0]           dburst_b_wdata;
  logic                            dburst_b_we;
  logic [DATA_WIDTH-1:0]           dburst_b_rdata;

  // arbiter -> accel_core DBRAM host port (clk_bram domain)
  logic [$clog2(DATA_DEPTH)-1:0]   core_dbram_addr;
  logic [DATA_WIDTH-1:0]           core_dbram_wdata;
  logic                            core_dbram_we;
  logic [DATA_WIDTH-1:0]           core_dbram_rdata;

  // -----------------------------------------------------------------------
  // AXI-Lite accelerator slave (clk_bram)
  // -----------------------------------------------------------------------
  accel_axi u_accel_axi (
    .clk_i             ( clk_bram             ),
    .rst_ni            ( peripheral_aresetn   ),
    .s_axi_awaddr      ( M_AXI_LITE_awaddr    ),
    .s_axi_awvalid     ( M_AXI_LITE_awvalid   ),
    .s_axi_awready     ( M_AXI_LITE_awready   ),
    .s_axi_wdata       ( M_AXI_LITE_wdata     ),
    .s_axi_wstrb       ( M_AXI_LITE_wstrb     ),
    .s_axi_wvalid      ( M_AXI_LITE_wvalid    ),
    .s_axi_wready      ( M_AXI_LITE_wready    ),
    .s_axi_bresp       ( M_AXI_LITE_bresp     ),
    .s_axi_bvalid      ( M_AXI_LITE_bvalid    ),
    .s_axi_bready      ( M_AXI_LITE_bready    ),
    .s_axi_araddr      ( M_AXI_LITE_araddr    ),
    .s_axi_arvalid     ( M_AXI_LITE_arvalid   ),
    .s_axi_arready     ( M_AXI_LITE_arready   ),
    .s_axi_rdata       ( M_AXI_LITE_rdata     ),
    .s_axi_rresp       ( M_AXI_LITE_rresp     ),
    .s_axi_rvalid      ( M_AXI_LITE_rvalid    ),
    .s_axi_rready      ( M_AXI_LITE_rready    ),
    .start_o           ( accel_start_bram     ),
    .sw_reset_o        ( accel_sw_reset_bram  ),
    .done_i            ( accel_done_bram      ),
    .running_i         ( accel_running_bram   ),
    .ibram_addr_o      ( ibram_addr           ),
    .ibram_wdata_o     ( ibram_wdata          ),
    .ibram_we_o        ( ibram_we             ),
    .ibram_rdata_i     ( ibram_rdata          ),
    .dbram_addr_o      ( axi_dbram_addr       ),
    .dbram_wdata_o     ( axi_dbram_wdata      ),
    .dbram_we_o        ( axi_dbram_we         ),
    .dbram_rdata_i     ( axi_dbram_rdata      )
  );

  // -----------------------------------------------------------------------
  // GP1 DBRAM burst slave (clk_bram)
  // -----------------------------------------------------------------------
  accel_axi_burst u_dburst (
    .clk_i             ( clk_bram             ),
    .rst_ni            ( peripheral_aresetn   ),
    .running_i         ( accel_running_bram   ),
    .s_axi_awid        ( dburst_awid          ),
    .s_axi_awaddr      ( dburst_awaddr        ),
    .s_axi_awlen       ( dburst_awlen         ),
    .s_axi_awsize      ( dburst_awsize        ),
    .s_axi_awburst     ( dburst_awburst       ),
    .s_axi_awvalid     ( dburst_awvalid       ),
    .s_axi_awready     ( dburst_awready       ),
    .s_axi_wdata       ( dburst_wdata         ),
    .s_axi_wstrb       ( dburst_wstrb         ),
    .s_axi_wlast       ( dburst_wlast         ),
    .s_axi_wvalid      ( dburst_wvalid        ),
    .s_axi_wready      ( dburst_wready        ),
    .s_axi_bid         ( dburst_bid           ),
    .s_axi_bresp       ( dburst_bresp         ),
    .s_axi_bvalid      ( dburst_bvalid        ),
    .s_axi_bready      ( dburst_bready        ),
    .s_axi_arid        ( dburst_arid          ),
    .s_axi_araddr      ( dburst_araddr        ),
    .s_axi_arlen       ( dburst_arlen         ),
    .s_axi_arsize      ( dburst_arsize        ),
    .s_axi_arburst     ( dburst_arburst       ),
    .s_axi_arvalid     ( dburst_arvalid       ),
    .s_axi_arready     ( dburst_arready       ),
    .s_axi_rid         ( dburst_rid           ),
    .s_axi_rdata       ( dburst_rdata         ),
    .s_axi_rresp       ( dburst_rresp         ),
    .s_axi_rlast       ( dburst_rlast         ),
    .s_axi_rvalid      ( dburst_rvalid        ),
    .s_axi_rready      ( dburst_rready        ),
    .b_req             ( dburst_b_req         ),
    .b_addr            ( dburst_b_addr        ),
    .b_wdata           ( dburst_b_wdata       ),
    .b_we              ( dburst_b_we          ),
    .b_rdata           ( dburst_b_rdata       )
  );

  // -----------------------------------------------------------------------
  // GP1 IBRAM burst slave (clk_bram, write-only)
  // -----------------------------------------------------------------------
  accel_ibram_burst u_iburst (
    .clk_i             ( clk_bram             ),
    .rst_ni            ( peripheral_aresetn   ),
    .running_i         ( accel_running_bram   ),
    .s_axi_awid        ( iburst_awid          ),
    .s_axi_awaddr      ( iburst_awaddr        ),
    .s_axi_awlen       ( iburst_awlen         ),
    .s_axi_awsize      ( iburst_awsize        ),
    .s_axi_awburst     ( iburst_awburst       ),
    .s_axi_awvalid     ( iburst_awvalid       ),
    .s_axi_awready     ( iburst_awready       ),
    .s_axi_wdata       ( M_AXI_BURST_wdata    ),
    .s_axi_wstrb       ( M_AXI_BURST_wstrb    ),
    .s_axi_wlast       ( iburst_wlast         ),
    .s_axi_wvalid      ( iburst_wvalid        ),
    .s_axi_wready      ( iburst_wready        ),
    .s_axi_bid         ( iburst_bid           ),
    .s_axi_bresp       ( iburst_bresp         ),
    .s_axi_bvalid      ( iburst_bvalid        ),
    .s_axi_bready      ( iburst_bready        ),
    .s_axi_arid        ( iburst_arid          ),
    .s_axi_araddr      ( iburst_araddr        ),
    .s_axi_arlen       ( iburst_arlen         ),
    .s_axi_arsize      ( iburst_arsize        ),
    .s_axi_arburst     ( iburst_arburst       ),
    .s_axi_arvalid     ( iburst_arvalid       ),
    .s_axi_arready     ( iburst_arready       ),
    .s_axi_rid         ( iburst_rid           ),
    .s_axi_rresp       ( iburst_rresp         ),
    .s_axi_rlast       ( iburst_rlast         ),
    .s_axi_rvalid      ( iburst_rvalid        ),
    .s_axi_rready      ( iburst_rready        ),
    .b_req             ( iburst_b_req         ),
    .ibram_addr_o      ( iburst_b_addr        ),
    .ibram_wdata_o     ( iburst_b_wdata       ),
    .ibram_we_o        ( iburst_b_we          ),
    .ibram_rdata_i     ( core_ibram_rdata     )
  );

  // -----------------------------------------------------------------------
  // DBRAM host-port arbiter
  // -----------------------------------------------------------------------
  accel_dbram_arb u_arb (
    .a_addr            ( axi_dbram_addr       ),
    .a_wdata           ( axi_dbram_wdata      ),
    .a_we              ( axi_dbram_we         ),
    .a_rdata           ( axi_dbram_rdata      ),
    .b_req             ( dburst_b_req         ),
    .b_addr            ( dburst_b_addr        ),
    .b_wdata           ( dburst_b_wdata       ),
    .b_we              ( dburst_b_we          ),
    .b_rdata           ( dburst_b_rdata       ),
    .dbram_addr_o      ( core_dbram_addr      ),
    .dbram_wdata_o     ( core_dbram_wdata     ),
    .dbram_we_o        ( core_dbram_we        ),
    .dbram_rdata_i     ( core_dbram_rdata     )
  );

  // -----------------------------------------------------------------------
  // Accelerator core
  // -----------------------------------------------------------------------
  accel_core u_core (
    .clk_i         ( clk_core          ),
    .clk_bram_i    ( clk_bram          ),
    .rst_ni        ( peripheral_aresetn ),
    .soft_reset_i  ( sw_reset_core     ),
    .start_i       ( start_core        ),
    .done_o        ( accel_done_core   ),
    .running_o     ( accel_running_core),
    .ibram_addr_i  ( core_ibram_addr   ),
    .ibram_wdata_i ( core_ibram_wdata  ),
    .ibram_we_i    ( core_ibram_we     ),
    .ibram_rdata_o ( core_ibram_rdata  ),
    .dbram_addr_i  ( core_dbram_addr   ),
    .dbram_wdata_i ( core_dbram_wdata  ),
    .dbram_we_i    ( core_dbram_we     ),
    .dbram_rdata_o ( core_dbram_rdata  )
  );

endmodule
