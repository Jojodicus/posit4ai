// Top-level wrapper for Zynq PS7 + PAU/FPU Harness
// Instantiates the block design wrapper (PS7 + protocol converter)
// and connects its AXI-Lite master to pau_fpu_harness_axi.
//
// Port names match the auto-generated zynq_ps_wrapper.v from Vivado.
// DDR and FIXED_IO use "_0" suffix from make_bd_intf_pins_external.

module zynq_pau_top (
    inout  [14:0] DDR_0_addr,
    inout  [2:0]  DDR_0_ba,
    inout         DDR_0_cas_n,
    inout         DDR_0_ck_n,
    inout         DDR_0_ck_p,
    inout         DDR_0_cke,
    inout         DDR_0_cs_n,
    inout  [3:0]  DDR_0_dm,
    inout  [31:0] DDR_0_dq,
    inout  [3:0]  DDR_0_dqs_n,
    inout  [3:0]  DDR_0_dqs_p,
    inout         DDR_0_odt,
    inout         DDR_0_ras_n,
    inout         DDR_0_reset_n,
    inout         DDR_0_we_n,
    inout         FIXED_IO_0_ddr_vrn,
    inout         FIXED_IO_0_ddr_vrp,
    inout  [53:0] FIXED_IO_0_mio,
    inout         FIXED_IO_0_ps_clk,
    inout         FIXED_IO_0_ps_porb,
    inout         FIXED_IO_0_ps_srstb
);

    // Wires from BD wrapper
    wire         fclk_clk0;
    wire  [0:0]  peripheral_aresetn;

    // AXI-Lite signals from BD (protocol converter output)
    wire  [31:0] m_axi_lite_awaddr;
    wire  [2:0]  m_axi_lite_awprot;
    wire         m_axi_lite_awvalid;
    wire         m_axi_lite_awready;
    wire  [31:0] m_axi_lite_wdata;
    wire  [3:0]  m_axi_lite_wstrb;
    wire         m_axi_lite_wvalid;
    wire         m_axi_lite_wready;
    wire  [1:0]  m_axi_lite_bresp;
    wire         m_axi_lite_bvalid;
    wire         m_axi_lite_bready;
    wire  [31:0] m_axi_lite_araddr;
    wire  [2:0]  m_axi_lite_arprot;
    wire         m_axi_lite_arvalid;
    wire         m_axi_lite_arready;
    wire  [31:0] m_axi_lite_rdata;
    wire  [1:0]  m_axi_lite_rresp;
    wire         m_axi_lite_rvalid;
    wire         m_axi_lite_rready;

    // Zynq PS Block Design Wrapper
    zynq_ps_wrapper i_zynq_ps (
        // DDR Interface
        .DDR_0_addr          ( DDR_0_addr          ),
        .DDR_0_ba            ( DDR_0_ba            ),
        .DDR_0_cas_n         ( DDR_0_cas_n         ),
        .DDR_0_ck_n          ( DDR_0_ck_n          ),
        .DDR_0_ck_p          ( DDR_0_ck_p          ),
        .DDR_0_cke           ( DDR_0_cke           ),
        .DDR_0_cs_n          ( DDR_0_cs_n          ),
        .DDR_0_dm            ( DDR_0_dm            ),
        .DDR_0_dq            ( DDR_0_dq            ),
        .DDR_0_dqs_n         ( DDR_0_dqs_n         ),
        .DDR_0_dqs_p         ( DDR_0_dqs_p         ),
        .DDR_0_odt           ( DDR_0_odt           ),
        .DDR_0_ras_n         ( DDR_0_ras_n         ),
        .DDR_0_reset_n       ( DDR_0_reset_n       ),
        .DDR_0_we_n          ( DDR_0_we_n          ),
        // Fixed IO
        .FIXED_IO_0_ddr_vrn  ( FIXED_IO_0_ddr_vrn  ),
        .FIXED_IO_0_ddr_vrp  ( FIXED_IO_0_ddr_vrp  ),
        .FIXED_IO_0_mio      ( FIXED_IO_0_mio      ),
        .FIXED_IO_0_ps_clk   ( FIXED_IO_0_ps_clk   ),
        .FIXED_IO_0_ps_porb  ( FIXED_IO_0_ps_porb  ),
        .FIXED_IO_0_ps_srstb ( FIXED_IO_0_ps_srstb ),
        // Clock and Reset
        .FCLK_CLK0           ( fclk_clk0           ),
        .peripheral_aresetn  ( peripheral_aresetn   ),
        // AXI-Lite Master
        .M_AXI_LITE_awaddr   ( m_axi_lite_awaddr   ),
        .M_AXI_LITE_awprot   ( m_axi_lite_awprot   ),
        .M_AXI_LITE_awvalid  ( m_axi_lite_awvalid  ),
        .M_AXI_LITE_awready  ( m_axi_lite_awready  ),
        .M_AXI_LITE_wdata    ( m_axi_lite_wdata    ),
        .M_AXI_LITE_wstrb    ( m_axi_lite_wstrb    ),
        .M_AXI_LITE_wvalid   ( m_axi_lite_wvalid   ),
        .M_AXI_LITE_wready   ( m_axi_lite_wready   ),
        .M_AXI_LITE_bresp    ( m_axi_lite_bresp    ),
        .M_AXI_LITE_bvalid   ( m_axi_lite_bvalid   ),
        .M_AXI_LITE_bready   ( m_axi_lite_bready   ),
        .M_AXI_LITE_araddr   ( m_axi_lite_araddr   ),
        .M_AXI_LITE_arprot   ( m_axi_lite_arprot   ),
        .M_AXI_LITE_arvalid  ( m_axi_lite_arvalid  ),
        .M_AXI_LITE_arready  ( m_axi_lite_arready  ),
        .M_AXI_LITE_rdata    ( m_axi_lite_rdata    ),
        .M_AXI_LITE_rresp    ( m_axi_lite_rresp    ),
        .M_AXI_LITE_rvalid   ( m_axi_lite_rvalid   ),
        .M_AXI_LITE_rready   ( m_axi_lite_rready   )
    );

    // PAU/FPU Harness with AXI-Lite Slave
    pau_fpu_harness_axi i_pau_axi (
        .clk_i     ( fclk_clk0              ),
        .rst_ni    ( peripheral_aresetn[0]   ),
        .awaddr_i  ( m_axi_lite_awaddr      ),
        .awprot_i  ( m_axi_lite_awprot      ),
        .awvalid_i ( m_axi_lite_awvalid     ),
        .awready_o ( m_axi_lite_awready     ),
        .wdata_i   ( m_axi_lite_wdata       ),
        .wstrb_i   ( m_axi_lite_wstrb       ),
        .wvalid_i  ( m_axi_lite_wvalid      ),
        .wready_o  ( m_axi_lite_wready      ),
        .bresp_o   ( m_axi_lite_bresp       ),
        .bvalid_o  ( m_axi_lite_bvalid      ),
        .bready_i  ( m_axi_lite_bready      ),
        .araddr_i  ( m_axi_lite_araddr      ),
        .arprot_i  ( m_axi_lite_arprot      ),
        .arvalid_i ( m_axi_lite_arvalid     ),
        .arready_o ( m_axi_lite_arready     ),
        .rdata_o   ( m_axi_lite_rdata       ),
        .rresp_o   ( m_axi_lite_rresp       ),
        .rvalid_o  ( m_axi_lite_rvalid      ),
        .rready_i  ( m_axi_lite_rready      )
    );

endmodule
