// PERCIVAL Accelerator — full implementation top (PS7 + accel_axi).
// Used by ./impl.sh for full synthesis, place-and-route, and bitstream generation.
// Connects the Zynq PS7 block design wrapper to the AXI-Lite accelerator slave.

module zynq_accel_top (
  // Zedboard DDR and fixed I/O (passed through to PS7 block design)
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

  // ── Block design: PS7 + proc_sys_reset + axi_protocol_converter ──────────────
  logic        FCLK_CLK0;           // 100 MHz from PS7
  logic        peripheral_aresetn;  // synchronised active-low reset from proc_sys_reset

  // AXI-Lite master from PS7 (via AXI protocol converter)
  logic [31:0] M_AXI_LITE_awaddr;
  logic        M_AXI_LITE_awvalid;
  logic        M_AXI_LITE_awready;
  logic [31:0] M_AXI_LITE_wdata;
  logic [3:0]  M_AXI_LITE_wstrb;
  logic        M_AXI_LITE_wvalid;
  logic        M_AXI_LITE_wready;
  logic [1:0]  M_AXI_LITE_bresp;
  logic        M_AXI_LITE_bvalid;
  logic        M_AXI_LITE_bready;
  logic [31:0] M_AXI_LITE_araddr;
  logic        M_AXI_LITE_arvalid;
  logic        M_AXI_LITE_arready;
  logic [31:0] M_AXI_LITE_rdata;
  logic [1:0]  M_AXI_LITE_rresp;
  logic        M_AXI_LITE_rvalid;
  logic        M_AXI_LITE_rready;

  zynq_ps_wrapper u_zynq_ps (
    .DDR_addr             ( DDR_addr             ),
    .DDR_ba               ( DDR_ba               ),
    .DDR_cas_n            ( DDR_cas_n            ),
    .DDR_ck_n             ( DDR_ck_n             ),
    .DDR_ck_p             ( DDR_ck_p             ),
    .DDR_cke              ( DDR_cke              ),
    .DDR_cs_n             ( DDR_cs_n             ),
    .DDR_dm               ( DDR_dm               ),
    .DDR_dq               ( DDR_dq               ),
    .DDR_dqs_n            ( DDR_dqs_n            ),
    .DDR_dqs_p            ( DDR_dqs_p            ),
    .DDR_odt              ( DDR_odt              ),
    .DDR_ras_n            ( DDR_ras_n            ),
    .DDR_reset_n          ( DDR_reset_n          ),
    .DDR_we_n             ( DDR_we_n             ),
    .FIXED_IO_mio         ( FIXED_IO_mio         ),
    .FIXED_IO_ddr_vrn     ( FIXED_IO_ddr_vrn     ),
    .FIXED_IO_ddr_vrp     ( FIXED_IO_ddr_vrp     ),
    .FIXED_IO_ps_clk      ( FIXED_IO_ps_clk      ),
    .FIXED_IO_ps_porb     ( FIXED_IO_ps_porb     ),
    .FIXED_IO_ps_srstb    ( FIXED_IO_ps_srstb    ),
    .FCLK_CLK0            ( FCLK_CLK0            ),
    .peripheral_aresetn   ( peripheral_aresetn   ),
    .M_AXI_LITE_awaddr    ( M_AXI_LITE_awaddr    ),
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
    .M_AXI_LITE_arvalid   ( M_AXI_LITE_arvalid   ),
    .M_AXI_LITE_arready   ( M_AXI_LITE_arready   ),
    .M_AXI_LITE_rdata     ( M_AXI_LITE_rdata     ),
    .M_AXI_LITE_rresp     ( M_AXI_LITE_rresp     ),
    .M_AXI_LITE_rvalid    ( M_AXI_LITE_rvalid    ),
    .M_AXI_LITE_rready    ( M_AXI_LITE_rready    )
  );

  // ── AXI-Lite accelerator slave ────────────────────────────────────────────────
  accel_axi u_accel_axi (
    .clk_i             ( FCLK_CLK0            ),
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
    .s_axi_rready      ( M_AXI_LITE_rready    )
  );

endmodule
