// PERCIVAL Accelerator -- full implementation top (PS7 + accel_axi + accel_core).
// Used by ./impl.sh for full synthesis, place-and-route, and bitstream generation.
// Connects the Zynq PS7 block design wrapper to the AXI-Lite accelerator slave.

module zynq_accel_top (
  // Zedboard DDR and fixed I/O (passed through to PS7 block design)
  // Port names use standard Zynq XDC names; mapped to zynq_ps_wrapper's _0_ variants below.
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

  // -- Block design: PS7 + proc_sys_reset + axi_protocol_converter ---
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

  // arprot / awprot are outputs from the PS master; accel_axi ignores them
  logic [2:0] M_AXI_LITE_arprot_unused;
  logic [2:0] M_AXI_LITE_awprot_unused;

  // -- AXI4 burst master (GP1 -> axi_pc_gp1, 32-bit data, 12-bit IDs) ------
  // GP1 is the second PS7 AXI3 master (PS CPU -> PL fabric); converted to AXI4 in BD.
  // Data width: 32-bit from GP1; accel_axi_burst's 64-bit bus carries it in [31:0].
  // ID width: GP1 uses 12-bit IDs; accel_axi_burst AXI_ID_WIDTH=4, so [3:0] suffix used.
  logic [11:0] M_AXI_BURST_awid;
  logic [31:0] M_AXI_BURST_awaddr;
  logic [7:0]  M_AXI_BURST_awlen;    // AXI4 8-bit encoding after protocol converter
  logic [2:0]  M_AXI_BURST_awsize;
  logic [1:0]  M_AXI_BURST_awburst;
  logic        M_AXI_BURST_awlock;
  logic [3:0]  M_AXI_BURST_awcache;
  logic [2:0]  M_AXI_BURST_awprot;
  logic [3:0]  M_AXI_BURST_awqos;
  logic        M_AXI_BURST_awvalid;
  logic        M_AXI_BURST_awready;
  logic [31:0] M_AXI_BURST_wdata;
  logic [3:0]  M_AXI_BURST_wstrb;
  logic        M_AXI_BURST_wlast;
  logic        M_AXI_BURST_wvalid;
  logic        M_AXI_BURST_wready;
  logic [11:0] M_AXI_BURST_bid;
  logic [1:0]  M_AXI_BURST_bresp;
  logic        M_AXI_BURST_bvalid;
  logic        M_AXI_BURST_bready;
  logic [11:0] M_AXI_BURST_arid;
  logic [31:0] M_AXI_BURST_araddr;
  logic [7:0]  M_AXI_BURST_arlen;
  logic [2:0]  M_AXI_BURST_arsize;
  logic [1:0]  M_AXI_BURST_arburst;
  logic        M_AXI_BURST_arlock;
  logic [3:0]  M_AXI_BURST_arcache;
  logic [2:0]  M_AXI_BURST_arprot;
  logic [3:0]  M_AXI_BURST_arqos;
  logic        M_AXI_BURST_arvalid;
  logic        M_AXI_BURST_arready;
  logic [11:0] M_AXI_BURST_rid;
  logic [31:0] M_AXI_BURST_rdata;
  logic [1:0]  M_AXI_BURST_rresp;
  logic        M_AXI_BURST_rlast;
  logic        M_AXI_BURST_rvalid;
  logic        M_AXI_BURST_rready;
  // Unused outputs from the AXI4 protocol converter (region, user)
  logic [3:0]  M_AXI_BURST_awregion_unused;
  logic [3:0]  M_AXI_BURST_arregion_unused;

  zynq_ps_wrapper u_zynq_ps (
    // DDR -- wrapper uses _0_ suffix (created via make_bd_intf_pins_external)
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
    // FIXED_IO -- wrapper uses _0_ suffix
    .FIXED_IO_0_mio       ( FIXED_IO_mio         ),
    .FIXED_IO_0_ddr_vrn   ( FIXED_IO_ddr_vrn     ),
    .FIXED_IO_0_ddr_vrp   ( FIXED_IO_ddr_vrp     ),
    .FIXED_IO_0_ps_clk    ( FIXED_IO_ps_clk      ),
    .FIXED_IO_0_ps_porb   ( FIXED_IO_ps_porb     ),
    .FIXED_IO_0_ps_srstb  ( FIXED_IO_ps_srstb    ),
    .FCLK_CLK0            ( FCLK_CLK0            ),
    .peripheral_aresetn   ( peripheral_aresetn   ),
    // AXI-Lite master -- prot signals unused by accel_axi
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
    // GP1 burst master (AXI4, 32-bit data, connected to accel_axi_burst)
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

  // -- Internal wires -----------------------------------------------
  // accel_axi -> accel_core control
  logic                             accel_start;
  logic                             accel_rst_n;
  logic                             accel_done;
  logic                             accel_running;

  // accel_axi -> arbiter (AXI-Lite DBRAM host, port A)
  logic [$clog2(DATA_DEPTH)-1:0]    axi_dbram_addr;
  logic [DATA_WIDTH-1:0]            axi_dbram_wdata;
  logic                             axi_dbram_we;
  logic [DATA_WIDTH-1:0]            axi_dbram_rdata;

  // accel_axi -> accel_core IBRAM host
  logic [$clog2(INSTR_DEPTH)-1:0]   ibram_addr;
  logic [63:0]                      ibram_wdata;
  logic                             ibram_we;
  logic [63:0]                      ibram_rdata;

  // arbiter -> accel_core DBRAM host
  logic [$clog2(DATA_DEPTH)-1:0]    core_dbram_addr;
  logic [DATA_WIDTH-1:0]            core_dbram_wdata;
  logic                             core_dbram_we;
  logic [DATA_WIDTH-1:0]            core_dbram_rdata;

  // burst slave -> arbiter (port B)
  logic                             burst_b_req;
  logic [$clog2(DATA_DEPTH)-1:0]    burst_b_addr;
  logic [DATA_WIDTH-1:0]            burst_b_wdata;
  logic                             burst_b_we;
  logic [DATA_WIDTH-1:0]            burst_b_rdata;

  // Width-adapter wires: accel_axi_burst (4-bit IDs, 64-bit rdata) -> M_AXI_BURST (12-bit IDs, 32-bit rdata)
  logic [3:0]  burst_bid_4,  burst_rid_4;
  logic [63:0] burst_rdata_64;
  assign M_AXI_BURST_bid  = {8'b0, burst_bid_4};   // zero-extend 4->12 bit
  assign M_AXI_BURST_rid  = {8'b0, burst_rid_4};   // zero-extend 4->12 bit
  assign M_AXI_BURST_rdata = burst_rdata_64[31:0];  // lower 32 bits of 64-bit read data

  // -- AXI-Lite accelerator slave ---------------------------------------
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
    .s_axi_rready      ( M_AXI_LITE_rready    ),
    // control
    .start_o           ( accel_start          ),
    .rst_no            ( accel_rst_n          ),
    .done_i            ( accel_done           ),
    .running_i         ( accel_running        ),
    // IBRAM host
    .ibram_addr_o      ( ibram_addr           ),
    .ibram_wdata_o     ( ibram_wdata          ),
    .ibram_we_o        ( ibram_we             ),
    .ibram_rdata_i     ( ibram_rdata          ),
    // DBRAM host -> arbiter port A
    .dbram_addr_o      ( axi_dbram_addr       ),
    .dbram_wdata_o     ( axi_dbram_wdata      ),
    .dbram_we_o        ( axi_dbram_we         ),
    .dbram_rdata_i     ( axi_dbram_rdata      )
  );

  // -- GP1 burst slave (AXI4, 32-bit data bus from PS7 M_AXI_GP1 via axi_pc_gp1) -
  // GP1 is a 32-bit AXI bus; accel_axi_burst has a 64-bit data port.
  // For DATA_WIDTH=32 builds: wdata[31:0] carries the BRAM word; wstrb[7:4]=0 masks upper half.
  // For DATA_WIDTH=64 builds: only lower 32 bits of each BRAM word are filled per AXI beat;
  //   a SmartConnect width-upsizer would be needed for full 64-bit throughput (future work).
  // IDs: GP1 uses 12-bit IDs; accel_axi_burst AXI_ID_WIDTH=4 -> lower 4 bits used.
  accel_axi_burst u_burst (
    .clk_i             ( FCLK_CLK0                    ),
    .rst_ni            ( peripheral_aresetn            ),
    .running_i         ( accel_running                 ),
    // AW channel
    .s_axi_awid        ( M_AXI_BURST_awid[3:0]        ),
    .s_axi_awaddr      ( M_AXI_BURST_awaddr            ),
    .s_axi_awlen       ( M_AXI_BURST_awlen             ),
    .s_axi_awsize      ( M_AXI_BURST_awsize            ),
    .s_axi_awburst     ( M_AXI_BURST_awburst           ),
    .s_axi_awvalid     ( M_AXI_BURST_awvalid           ),
    .s_axi_awready     ( M_AXI_BURST_awready           ),
    // W channel -- 32-bit GP1 data zero-extended to 64-bit burst port
    .s_axi_wdata       ( {32'b0, M_AXI_BURST_wdata}   ),
    .s_axi_wstrb       ( {4'b0,  M_AXI_BURST_wstrb}   ),
    .s_axi_wlast       ( M_AXI_BURST_wlast             ),
    .s_axi_wvalid      ( M_AXI_BURST_wvalid            ),
    .s_axi_wready      ( M_AXI_BURST_wready            ),
    // B channel
    .s_axi_bid         ( burst_bid_4                   ),  // 4-bit -> assigned to M_AXI_BURST_bid
    .s_axi_bresp       ( M_AXI_BURST_bresp             ),
    .s_axi_bvalid      ( M_AXI_BURST_bvalid            ),
    .s_axi_bready      ( M_AXI_BURST_bready            ),
    // AR channel
    .s_axi_arid        ( M_AXI_BURST_arid[3:0]        ),
    .s_axi_araddr      ( M_AXI_BURST_araddr            ),
    .s_axi_arlen       ( M_AXI_BURST_arlen             ),
    .s_axi_arsize      ( M_AXI_BURST_arsize            ),
    .s_axi_arburst     ( M_AXI_BURST_arburst           ),
    .s_axi_arvalid     ( M_AXI_BURST_arvalid           ),
    .s_axi_arready     ( M_AXI_BURST_arready           ),
    // R channel -- 64-bit burst data; lower 32 bits assigned to M_AXI_BURST_rdata
    .s_axi_rid         ( burst_rid_4                   ),  // 4-bit -> assigned to M_AXI_BURST_rid
    .s_axi_rdata       ( burst_rdata_64                ),  // 64-bit; [31:0] -> M_AXI_BURST_rdata
    .s_axi_rresp       ( M_AXI_BURST_rresp             ),
    .s_axi_rlast       ( M_AXI_BURST_rlast             ),
    .s_axi_rvalid      ( M_AXI_BURST_rvalid            ),
    .s_axi_rready      ( M_AXI_BURST_rready            ),
    // Port B -> arbiter
    .b_req             ( burst_b_req                   ),
    .b_addr            ( burst_b_addr                  ),
    .b_wdata           ( burst_b_wdata                 ),
    .b_we              ( burst_b_we                    ),
    .b_rdata           ( burst_b_rdata                 )
  );

  // -- DBRAM host-port arbiter --------------------------------------
  accel_dbram_arb u_arb (
    // Port A: AXI-Lite host
    .a_addr            ( axi_dbram_addr       ),
    .a_wdata           ( axi_dbram_wdata      ),
    .a_we              ( axi_dbram_we         ),
    .a_rdata           ( axi_dbram_rdata      ),
    // Port B: HP0 burst slave
    .b_req             ( burst_b_req          ),
    .b_addr            ( burst_b_addr         ),
    .b_wdata           ( burst_b_wdata        ),
    .b_we              ( burst_b_we           ),
    .b_rdata           ( burst_b_rdata        ),
    // accel_core DBRAM host port
    .dbram_addr_o      ( core_dbram_addr      ),
    .dbram_wdata_o     ( core_dbram_wdata     ),
    .dbram_we_o        ( core_dbram_we        ),
    .dbram_rdata_i     ( core_dbram_rdata     )
  );

  // -- Accelerator core --------------------------------------------
  // TODO: clk_bram_i should be 2x FCLK_CLK0 (add second clk_wiz for full Step B speed).
  // Tied to FCLK_CLK0 for now -- design still functionally correct, throughput at 1/2 rate.
  accel_core u_core (
    .clk_i         ( FCLK_CLK0        ),
    .clk_bram_i    ( FCLK_CLK0        ),
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

endmodule
