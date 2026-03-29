// PERCIVAL Accelerator — AXI-Lite slave wrapping accel_core.
//
// AXI-Lite register map (base: 0x43C00000):
//   0x00  CTRL       [0]=START, [1]=RESET  (write 1; self-clearing)
//   0x04  STATUS     [0]=DONE,  [1]=RUNNING, [2]=ERROR  (read-only)
//   0x08  IBRAM_ADDR instruction BRAM word index (0 .. INSTR_DEPTH-1)
//   0x0C  IBRAM_DATA_LO  instruction bits [31:0]
//   0x10  IBRAM_DATA_HI  instruction bits [63:32]; write triggers BRAM write
//   0x14  DBRAM_ADDR data BRAM word index (0 .. DATA_DEPTH-1)
//   0x18  DBRAM_DATA data BRAM low word (DATA_WIDTH bits, zero-padded to 32)
//   0x1C  DBRAM_DATA_HI data BRAM high word (only meaningful for DATA_WIDTH=64)
//
// AXI safety: while RUNNING=1, AXI writes to BRAM registers are ACK'd but dropped.
// AXI reads return the last values written to the shadow registers.

module accel_axi
  import config_pkg::*;
  import opcodes_pkg::*;
#(
  parameter int AXI_ADDR_WIDTH = 32,
  parameter int AXI_DATA_WIDTH = 32
) (
  input  logic clk_i,
  input  logic rst_ni,

  // ── AXI-Lite slave interface ────────────────────────────────────────────────
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI AWADDR"  *) input  logic [AXI_ADDR_WIDTH-1:0] s_axi_awaddr,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI AWVALID" *) input  logic                      s_axi_awvalid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI AWREADY" *) output logic                      s_axi_awready,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI WDATA"   *) input  logic [AXI_DATA_WIDTH-1:0]  s_axi_wdata,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI WSTRB"   *) input  logic [AXI_DATA_WIDTH/8-1:0] s_axi_wstrb,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI WVALID"  *) input  logic                      s_axi_wvalid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI WREADY"  *) output logic                      s_axi_wready,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI BRESP"   *) output logic [1:0]                s_axi_bresp,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI BVALID"  *) output logic                      s_axi_bvalid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI BREADY"  *) input  logic                      s_axi_bready,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI ARADDR"  *) input  logic [AXI_ADDR_WIDTH-1:0] s_axi_araddr,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI ARVALID" *) input  logic                      s_axi_arvalid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI ARREADY" *) output logic                      s_axi_arready,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI RDATA"   *) output logic [AXI_DATA_WIDTH-1:0]  s_axi_rdata,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI RRESP"   *) output logic [1:0]                s_axi_rresp,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI RVALID"  *) output logic                      s_axi_rvalid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI RREADY"  *) input  logic                      s_axi_rready
);

  // ── Internal registers (AXI shadow) ──────────────────────────────────────────
  logic [31:0]                     reg_ibram_addr;
  logic [31:0]                     reg_ibram_data_lo;
  logic [31:0]                     reg_ibram_data_hi;
  logic [31:0]                     reg_dbram_addr;
  logic [31:0]                     reg_dbram_data;
  logic [31:0]                     reg_dbram_data_hi;

  // Control / status
  logic                            core_start;
  logic                            core_reset;
  logic                            core_done;
  logic                            core_running;

  // BRAM host interface
  logic [$clog2(INSTR_DEPTH)-1:0]  ibram_addr;
  logic [63:0]                     ibram_wdata;
  logic                            ibram_we;
  logic [63:0]                     ibram_rdata;

  logic [$clog2(DATA_DEPTH)-1:0]   dbram_addr;
  logic [DATA_WIDTH-1:0]           dbram_wdata;
  logic                            dbram_we;
  logic [DATA_WIDTH-1:0]           dbram_rdata;

  // ── accel_core instantiation ─────────────────────────────────────────────────
  accel_core u_core (
    .clk_i,
    .rst_ni     ( rst_ni && !core_reset ),
    .start_i    ( core_start   ),
    .done_o     ( core_done    ),
    .running_o  ( core_running ),
    .ibram_addr_i  ( ibram_addr  ),
    .ibram_wdata_i ( ibram_wdata ),
    .ibram_we_i    ( ibram_we    ),
    .ibram_rdata_o ( ibram_rdata ),
    .dbram_addr_i  ( dbram_addr  ),
    .dbram_wdata_i ( dbram_wdata ),
    .dbram_we_i    ( dbram_we    ),
    .dbram_rdata_o ( dbram_rdata )
  );

  // Wire host BRAM access (dropped when running)
  assign ibram_addr  = reg_ibram_addr[$clog2(INSTR_DEPTH)-1:0];
  assign dbram_addr  = reg_dbram_addr[$clog2(DATA_DEPTH)-1:0];

  // BRAM write data: bypass the shadow register for the triggering word,
  // since the shadow register update is sequential (same clock edge as WE)
  // and would otherwise supply the stale value.
  //   IBRAM trigger = write to 0x10 (DATA_HI) → high word from wr_data_q
  //   DBRAM trigger = write to 0x18 (32-bit) or 0x1C (64-bit) → from wr_data_q
  assign ibram_wdata = ibram_we ? {wr_data_q[31:0], reg_ibram_data_lo}
                                : {reg_ibram_data_hi, reg_ibram_data_lo};
  assign dbram_wdata = dbram_we
      ? ((DATA_WIDTH == 64) ? {wr_data_q[DATA_WIDTH-33:0], reg_dbram_data}
                            : wr_data_q[DATA_WIDTH-1:0])
      : ((DATA_WIDTH == 64) ? {reg_dbram_data_hi[DATA_WIDTH-33:0], reg_dbram_data}
                            : reg_dbram_data[DATA_WIDTH-1:0]);

  // ── AXI write channel ─────────────────────────────────────────────────────────
  typedef enum logic [1:0] { WR_IDLE, WR_ADDR, WR_DATA, WR_RESP } wr_state_t;
  wr_state_t wr_state_q, wr_state_d;

  logic [AXI_ADDR_WIDTH-1:0] wr_addr_q;
  logic [AXI_DATA_WIDTH-1:0] wr_data_q;

  always_comb begin
    wr_state_d  = wr_state_q;
    s_axi_awready = 1'b0;
    s_axi_wready  = 1'b0;
    s_axi_bvalid  = 1'b0;
    s_axi_bresp   = 2'b00;
    core_start    = 1'b0;
    core_reset    = 1'b0;
    ibram_we      = 1'b0;
    dbram_we      = 1'b0;

    unique case (wr_state_q)
      WR_IDLE: begin
        s_axi_awready = 1'b1;
        s_axi_wready  = 1'b1;
        if (s_axi_awvalid && s_axi_wvalid) wr_state_d = WR_RESP;
        else if (s_axi_awvalid)            wr_state_d = WR_DATA;
        else if (s_axi_wvalid)             wr_state_d = WR_ADDR;
      end
      WR_ADDR: begin
        s_axi_wready = 1'b1;
        if (s_axi_wvalid) wr_state_d = WR_RESP;
      end
      WR_DATA: begin
        s_axi_awready = 1'b1;
        if (s_axi_awvalid) wr_state_d = WR_RESP;
      end
      WR_RESP: begin
        s_axi_bvalid = 1'b1;
        if (s_axi_bready) begin
          // Decode and dispatch the write
          case (wr_addr_q[4:0])
            5'h00: begin  // CTRL
              if (wr_data_q[0]) core_start = !core_running;
              if (wr_data_q[1]) core_reset = 1'b1;
            end
            5'h10: begin  // IBRAM_DATA_HI — triggers BRAM write
              if (!core_running) ibram_we = 1'b1;
            end
            5'h18: begin  // DBRAM_DATA — triggers data BRAM write (32-bit wide)
              if (!core_running && DATA_WIDTH <= 32) dbram_we = 1'b1;
            end
            5'h1C: begin  // DBRAM_DATA_HI — triggers data BRAM write (64-bit wide)
              if (!core_running && DATA_WIDTH == 64) dbram_we = 1'b1;
            end
            default: ;
          endcase
          wr_state_d = WR_IDLE;
        end
      end
      default: wr_state_d = WR_IDLE;
    endcase
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      wr_state_q        <= WR_IDLE;
      wr_addr_q         <= '0;
      wr_data_q         <= '0;
      reg_ibram_addr    <= '0;
      reg_ibram_data_lo <= '0;
      reg_ibram_data_hi <= '0;
      reg_dbram_addr    <= '0;
      reg_dbram_data    <= '0;
      reg_dbram_data_hi <= '0;
    end else begin
      wr_state_q <= wr_state_d;

      // Capture AW address
      if (wr_state_q == WR_IDLE && s_axi_awvalid)
        wr_addr_q <= s_axi_awaddr;
      if (wr_state_q == WR_DATA && s_axi_awvalid)
        wr_addr_q <= s_axi_awaddr;

      // Capture W data
      if (wr_state_q == WR_IDLE && s_axi_wvalid)
        wr_data_q <= s_axi_wdata;
      if (wr_state_q == WR_ADDR && s_axi_wvalid)
        wr_data_q <= s_axi_wdata;

      // Write to shadow registers (always; BRAM write only when !running, handled above)
      if (wr_state_q == WR_RESP && s_axi_bready) begin
        case (wr_addr_q[4:0])
          5'h08: reg_ibram_addr    <= wr_data_q;
          5'h0C: reg_ibram_data_lo <= wr_data_q;
          5'h10: reg_ibram_data_hi <= wr_data_q;
          5'h14: reg_dbram_addr    <= wr_data_q;
          5'h18: reg_dbram_data    <= wr_data_q;
          5'h1C: reg_dbram_data_hi <= wr_data_q;
          default: ;
        endcase
      end
    end
  end

  // ── AXI read channel ──────────────────────────────────────────────────────────
  typedef enum logic { RD_IDLE, RD_DATA } rd_state_t;
  rd_state_t rd_state_q, rd_state_d;
  logic [AXI_ADDR_WIDTH-1:0] rd_addr_q;

  always_comb begin
    rd_state_d    = rd_state_q;
    s_axi_arready = 1'b0;
    s_axi_rvalid  = 1'b0;
    s_axi_rresp   = 2'b00;
    s_axi_rdata   = '0;

    unique case (rd_state_q)
      RD_IDLE: begin
        s_axi_arready = 1'b1;
        if (s_axi_arvalid) rd_state_d = RD_DATA;
      end
      RD_DATA: begin
        s_axi_rvalid = 1'b1;
        case (rd_addr_q[4:0])
          5'h04: s_axi_rdata = {29'b0, core_running, 1'b0, core_done};  // STATUS
          5'h08: s_axi_rdata = reg_ibram_addr;
          5'h0C: s_axi_rdata = reg_ibram_data_lo;
          5'h10: s_axi_rdata = reg_ibram_data_hi;
          5'h14: s_axi_rdata = reg_dbram_addr;
          5'h18: s_axi_rdata = dbram_rdata[31:0];  // low 32 bits (full word for 32-bit, low half for 64-bit)
          5'h1C: s_axi_rdata = (DATA_WIDTH == 64) ? dbram_rdata[63:32] : 32'b0;
          default: s_axi_rdata = '0;
        endcase
        if (s_axi_rready) rd_state_d = RD_IDLE;
      end
      default: rd_state_d = RD_IDLE;
    endcase
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      rd_state_q <= RD_IDLE;
      rd_addr_q  <= '0;
    end else begin
      rd_state_q <= rd_state_d;
      if (rd_state_q == RD_IDLE && s_axi_arvalid)
        rd_addr_q <= s_axi_araddr;
    end
  end

endmodule
