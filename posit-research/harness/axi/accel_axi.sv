// AXI-Lite slave.
//
// AXI-Lite register map (base: 0x43C00000):
//   0x00  CTRL       [0]=START, [1]=RESET  (write 1; self-clearing)
//   0x04  STATUS     [0]=DONE,  [1]=RUNNING  (read-only)
//   0x08  IBRAM_ADDR instruction BRAM word index (0 .. INSTR_DEPTH-1)
//   0x0C  IBRAM_DATA_LO  instruction bits [31:0]  (addr_result[19:0], addr_b[11:0] low)
//   0x10  IBRAM_DATA_HI  instruction bits [63:32]; write triggers BRAM write
//   0x14  DBRAM_ADDR data BRAM word index (0 .. DATA_DEPTH-1)
//   0x18  DBRAM_DATA data BRAM low word (DATA_WIDTH bits, zero-padded to 32)
//   0x1C  DBRAM_DATA_HI data BRAM high word (only meaningful for DATA_WIDTH=64)
//
// DBRAM address auto-increment: after every write to DBRAM_DATA (0x18, 32-bit) or
// DBRAM_DATA_HI (0x1C, 64-bit) the DBRAM_ADDR register increments by one, allowing
// the host to stream consecutive data words without re-writing DBRAM_ADDR between
// each word.  Reads of 0x18 (32-bit) or 0x1C (64-bit) also auto-increment.
// An explicit write to 0x14 always overrides.
//
// AXI safety: while RUNNING=1, AXI writes to BRAM registers are ACK'd but dropped.
// AXI reads return the last values written to the shadow registers.
//
// accel_core is NOT instantiated here; it lives in the parent (zynq_accel_top or
// tb_accel_axi).  This module exposes the IBRAM/DBRAM host ports and control
// signals so an arbiter can sit between this slave and the core.

module accel_axi
  import config_pkg::*;
  import opcodes_pkg::*;
#(
  parameter int AXI_ADDR_WIDTH = 32,
  parameter int AXI_DATA_WIDTH = 32
) (
  input  logic clk_i,
  input  logic rst_ni,

  // -- AXI-Lite slave interface -------------------------------------
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
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI RREADY"  *) input  logic                      s_axi_rready,

  // -- accel_core control interface ---------------------------------
  output logic start_o,    // one-cycle start pulse
  output logic rst_no,     // combined reset (rst_ni gated with CTRL.RESET)
  input  logic done_i,     // from accel_core.done_o
  input  logic running_i,  // from accel_core.running_o

  // -- Instruction BRAM host port -----------------------------------
  output logic [$clog2(INSTR_DEPTH)-1:0] ibram_addr_o,
  output logic [63:0]                    ibram_wdata_o,
  output logic                           ibram_we_o,
  input  logic [63:0]                    ibram_rdata_i,

  // -- Data BRAM host port (routed via arbiter) --------------------
  output logic [$clog2(DATA_DEPTH)-1:0]  dbram_addr_o,
  output logic [DATA_WIDTH-1:0]          dbram_wdata_o,
  output logic                           dbram_we_o,
  input  logic [DATA_WIDTH-1:0]          dbram_rdata_i
);

  // -- Internal registers (AXI shadow) ----------------------------
  logic [31:0]                     reg_ibram_addr;
  logic [31:0]                     reg_ibram_data_lo;
  logic [31:0]                     reg_ibram_data_hi;
  logic [31:0]                     reg_dbram_addr;
  logic [31:0]                     reg_dbram_data;
  logic [31:0]                     reg_dbram_data_hi;

  // Control / status
  logic                            core_reset;      // combinatorial request
  logic                            core_reset_q;    // registered (1-cycle synchronous pulse)

  // Combined reset output
  assign rst_no = rst_ni && !core_reset_q;

  // BRAM address and write-data assignments (combinatorial)
  assign ibram_addr_o = reg_ibram_addr[$clog2(INSTR_DEPTH)-1:0];
  assign dbram_addr_o = reg_dbram_addr[$clog2(DATA_DEPTH)-1:0];

  // AXI write channel state -- declared here so wr_data_q is in scope for the
  // ibram_wdata_o / dbram_wdata_o assigns below (forward-reference warning fix).
  typedef enum logic [1:0] { WR_IDLE, WR_ADDR, WR_DATA, WR_RESP } wr_state_t;
  wr_state_t wr_state_q, wr_state_d;

  logic [AXI_ADDR_WIDTH-1:0] wr_addr_q;
  logic [AXI_DATA_WIDTH-1:0] wr_data_q;

  // BRAM write data: bypass the shadow register for the triggering word,
  // since the shadow register update is sequential (same clock edge as WE)
  // and would otherwise supply the stale value.
  //   IBRAM trigger = write to 0x10 (DATA_HI) -> high word from wr_data_q
  //   DBRAM trigger = write to 0x18 (32-bit) or 0x1C (64-bit) -> from wr_data_q
  assign ibram_wdata_o = ibram_we_o ? {wr_data_q[31:0], reg_ibram_data_lo}
                                    : {reg_ibram_data_hi, reg_ibram_data_lo};
  assign dbram_wdata_o = dbram_we_o
      ? ((DATA_WIDTH == 64) ? {wr_data_q[DATA_WIDTH-33:0], reg_dbram_data}
                            : wr_data_q[DATA_WIDTH-1:0])
      : ((DATA_WIDTH == 64) ? {reg_dbram_data_hi[DATA_WIDTH-33:0], reg_dbram_data}
                            : reg_dbram_data[DATA_WIDTH-1:0]);

  // BRAM read data (64-bit zero-extended for read-path mux)
  logic [63:0] dbram_rdata_64;
  assign dbram_rdata_64 = 64'(dbram_rdata_i);

  // -- AXI write channel -------------------------------------------
  always_comb begin
    wr_state_d    = wr_state_q;
    s_axi_awready = 1'b0;
    s_axi_wready  = 1'b0;
    s_axi_bvalid  = 1'b0;
    s_axi_bresp   = 2'b00;
    start_o       = 1'b0;
    core_reset    = 1'b0;
    ibram_we_o    = 1'b0;
    dbram_we_o    = 1'b0;

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
              if (wr_data_q[0]) start_o    = !running_i;
              if (wr_data_q[1]) core_reset = 1'b1;
            end
            5'h10: begin  // IBRAM_DATA_HI -- triggers BRAM write
              if (!running_i) ibram_we_o = 1'b1;
            end
            5'h18: begin  // DBRAM_DATA -- triggers data BRAM write (32-bit wide)
              if (!running_i && DATA_WIDTH <= 32) dbram_we_o = 1'b1;
            end
            5'h1C: begin  // DBRAM_DATA_HI -- triggers data BRAM write (64-bit wide)
              if (!running_i && DATA_WIDTH == 64) dbram_we_o = 1'b1;
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
      core_reset_q      <= 1'b0;
      reg_ibram_addr    <= '0;
      reg_ibram_data_lo <= '0;
      reg_ibram_data_hi <= '0;
      reg_dbram_addr    <= '0;
      reg_dbram_data    <= '0;
      reg_dbram_data_hi <= '0;
    end else begin
      wr_state_q   <= wr_state_d;
      core_reset_q <= core_reset;

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

      // Write to shadow registers (always; BRAM write only when !running, handled above).
      // After each data-word write trigger (0x18 for 32-bit, 0x1C for 64-bit) the
      // DBRAM_ADDR register auto-increments so that the host can stream consecutive
      // words without re-writing the address register between beats.
      // After reading the last beat of a data word the address likewise auto-increments
      // to enable streaming reads.  An explicit write to 0x14 always overrides.
      if (wr_state_q == WR_RESP && s_axi_bready) begin
        case (wr_addr_q[4:0])
          5'h08: reg_ibram_addr    <= wr_data_q;
          5'h0C: reg_ibram_data_lo <= wr_data_q;
          5'h10: reg_ibram_data_hi <= wr_data_q;
          5'h14: reg_dbram_addr    <= wr_data_q;
          5'h18: begin
            reg_dbram_data <= wr_data_q;
            if (DATA_WIDTH <= 32) reg_dbram_addr <= reg_dbram_addr + 1;
          end
          5'h1C: begin
            reg_dbram_data_hi <= wr_data_q;
            if (DATA_WIDTH == 64) reg_dbram_addr <= reg_dbram_addr + 1;
          end
          default: ;
        endcase
      end else if (rd_state_q == RD_DATA && s_axi_rready) begin
        if ((DATA_WIDTH <= 32 && rd_addr_q[4:0] == 5'h18) ||
            (DATA_WIDTH == 64 && rd_addr_q[4:0] == 5'h1C))
          reg_dbram_addr <= reg_dbram_addr + 1;
      end
    end
  end

  // -- AXI read channel ----------------------------------------
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
          5'h04: s_axi_rdata = {30'b0, running_i, done_i};  // STATUS [0]=DONE [1]=RUNNING
          5'h08: s_axi_rdata = reg_ibram_addr;
          5'h0C: s_axi_rdata = reg_ibram_data_lo;
          5'h10: s_axi_rdata = reg_ibram_data_hi;
          5'h14: s_axi_rdata = reg_dbram_addr;
          5'h18: s_axi_rdata = dbram_rdata_64[31:0];   // low 32 bits (zero-extended for <32-bit)
          5'h1C: s_axi_rdata = dbram_rdata_64[63:32];  // high 32 bits (zero for <64-bit)
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
