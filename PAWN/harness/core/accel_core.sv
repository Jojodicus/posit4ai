// core: instruction BRAM + data BRAM + 3-stage pipeline + arith_unit.
//
// Instruction format (64-bit fixed-width):
//   [63:60] opcode       4 bits  (16 opcodes)
//   [59:40] addr_a      20 bits  (up to 1M data words)
//   [39:20] addr_b      20 bits
//   [19: 0] addr_result 20 bits
//
// 3-stage pipeline with 2x BRAM clock (XAPP706 alpha-blending) and result forwarding:
//
//   IF  : Present PC to IBRAM port B; registered output -> ibram_fetch_rdata.
//   ID  : Decode ibram_fetch_rdata; present addr_a/addr_b to DBRAM at clk_bram phase 0;
//         capture operands into op_a_q/op_b_q at phase 1.
//   EX/WB: Forward-mux op_a_q/op_b_q against fwd_q (last EX result); submit to
//         arith_unit; write result to DBRAM at phase 1 when arith_valid_o fires.
//
// clk_bram = 2x clk_i, phase-aligned:
//   phase 0: DBRAM reads addr_a (port A) and addr_b (port B)
//   phase 1: capture dbram output -> op_a_q/op_b_q; write result (port A)
//
// Forwarding:
//   When arith_valid_o fires for a writes_dbram op, the result is latched into
//   fwd_q tagged with id_ex_q.addr_result. The next instruction in EX gets its
//   operands muxed: arith_op_a = (id_ex_q.addr_a == fwd_addr_q && fwd_valid_q)
//   ? fwd_q : op_a_q (same for b). The DBRAM write of the same result happens
//   in parallel at phase 1, so the cycle after-next reads from DBRAM directly.
//
// Stall: id_ex_valid_q && !arith_valid_o (i.e. only while arith is mid-flight).
//   1-cycle ops reach steady-state 1 op/cycle; multi-cycle ops stall L-1 cycles.
//   capture_ops is gated identically so op_a_q/op_b_q are preserved during stall.
//
// arith_valid_i is only asserted when arith_ready_o, preventing double-submission.
//
// Top-level FSM (IDLE_S -> RUNNING_S -> HALT_S; stages run in parallel inside RUNNING_S):
//   IDLE_S   : waiting for start_i; pipeline empty
//   RUNNING_S: pipeline active; stall/advance based on hazards
//   HALT_S   : OP_HALT reached; done_o asserted

module accel_core
  import config_pkg::*;
  import opcodes_pkg::*;
(
  input  logic clk_i,
  input  logic clk_bram_i,   // 2x clk_i, phase-aligned (first edge after clk_i ^ is phase 0)
  input  logic rst_ni,

  // -- Control -----------------------------------------------------------
  input  logic start_i,
  input  logic soft_reset_i,
  output logic done_o,
  output logic running_o,

  // -- Instruction BRAM host port (only accessible when stopped) -------------
  input  logic [$clog2(INSTR_DEPTH)-1:0] ibram_addr_i,
  input  logic [63:0]                    ibram_wdata_i,
  input  logic                           ibram_we_i,
  output logic [63:0]                    ibram_rdata_o,

  // -- Data BRAM host port (only accessible when stopped) -----------------
  input  logic [$clog2(DATA_DEPTH)-1:0]  dbram_addr_i,
  input  logic [DATA_WIDTH-1:0]          dbram_wdata_i,
  input  logic                           dbram_we_i,
  output logic [DATA_WIDTH-1:0]          dbram_rdata_o
);

  // -- BRAMs --------------------------------------------------------------
  // ram_style hint: force block RAM inference. Combined with the registered
  // output paths (dbram_*_rdata, ibram_fetch_rdata) this lets Vivado pack the
  // output FFs into the BRAM tile's DOA_REG/DOB_REG (OREG), shortening the
  // read-to-arith-unit routing without adding a pipeline cycle.
  (* ram_style = "block" *) logic [63:0]           instr_mem [0:INSTR_DEPTH-1];
  (* ram_style = "block" *) logic [DATA_WIDTH-1:0] data_mem  [0:DATA_DEPTH-1];

  // Simulation: zero-initialise so unwritten slots decode as OP_HALT (opcode 0).
  // synthesis translate_off
  initial begin
    for (int i = 0; i < INSTR_DEPTH; i++) instr_mem[i] = '0;
    for (int i = 0; i < DATA_DEPTH;  i++) data_mem[i]  = '0;
  end
  // synthesis translate_on

  // -- Phase counter (at clk_bram) ------------------------------------------
  // phase_q=0: read sub-cycle; phase_q=1: write sub-cycle.
  // Resets to 0 so the first clk_bram edge after reset is a read sub-cycle.
  logic phase_q;
  always_ff @(posedge clk_bram_i or negedge rst_ni) begin
    if (!rst_ni) phase_q <= 1'b0;
    else         phase_q <= ~phase_q;
  end

  // -- BRAM port signals --------------------------------------------------
  logic [$clog2(DATA_DEPTH)-1:0]  dbram_porta_addr;
  logic [DATA_WIDTH-1:0]          dbram_porta_wdata;
  logic                           dbram_porta_we;
  logic [DATA_WIDTH-1:0]          dbram_porta_rdata;  // registered at clk_bram

  logic [$clog2(DATA_DEPTH)-1:0]  dbram_portb_addr;
  logic [DATA_WIDTH-1:0]          dbram_portb_rdata;  // registered at clk_bram

  // Operand capture registers: populated at phase 1 of the ID cycle.
  // These are sampled by arith_unit at clk_i ^ of the EX cycle (after phase 1 of ID).
  logic [DATA_WIDTH-1:0] op_a_q, op_b_q;

  // -- IBRAM -- true dual-port BRAM, clocked at clk_bram (2x) ---------------
  // Matches the DBRAM double-pump pattern (XAPP706 alpha-blending):
  //   phase 0 (read sub-cycle): sample instr_mem for both ports
  //   phase 1 (write sub-cycle): commit host write; advance IF/ID register
  //
  // Port A -- host read/write (ibram_addr_i / ibram_we_i)
  //   A phase-0 WE arrival is latched into ibram_host_*_q and executed at
  //   phase 1. A phase-1 arrival writes directly. Both paths produce one write
  //   per clk_i cycle regardless of AXI-burst clock phase.
  // Port B -- IF-stage fetch (pc_q, read-only)
  //   ibram_fetch_rdata is the IF/ID pipeline register. It advances at phase 1
  //   when !stall so that it is stable (clk_bram phase-1 FF -> clk_i FF) with
  //   T/2 setup window to the downstream clk_i decode FFs. No extra clk_i
  //   re-sync stage is added -- that would cost one IF cycle of latency.

  logic [63:0]                    ibram_porta_rdata_q;
  logic [$clog2(INSTR_DEPTH)-1:0] ibram_porta_addr;
  logic [63:0]                    ibram_porta_wdata;
  logic                           ibram_porta_we;

  logic [$clog2(INSTR_DEPTH)-1:0] ibram_host_addr_q;
  logic [63:0]                    ibram_host_wdata_q;
  logic                           ibram_host_we_q;

  logic [63:0] ibram_fetch_rdata;
  logic [63:0] ibram_portb_rdata_q;
  logic        running_bram_sync1_q, running_bram_sync2_q;

  always_ff @(posedge clk_bram_i or negedge rst_ni) begin
    if (!rst_ni) begin
      running_bram_sync1_q <= 1'b0;
      running_bram_sync2_q <= 1'b0;
    end else begin
      running_bram_sync1_q <= running_o;
      running_bram_sync2_q <= running_bram_sync1_q;
    end
  end

  // Port A address/data/we mux: unified signal so the BRAM block sees one address
  // (required for Vivado to infer block RAM -- split address per sub-cycle breaks inference).
  //   phase 0: read  -> ibram_addr_i
  //   phase 1: write -> latched addr (if pending) or direct addr (if direct phase-1 WE)
  always_comb begin
    if (phase_q) begin
      if (ibram_host_we_q) begin
        ibram_porta_addr  = ibram_host_addr_q;
        ibram_porta_wdata = ibram_host_wdata_q;
        ibram_porta_we    = 1'b1;
      end else begin
        ibram_porta_addr  = ibram_addr_i;
        ibram_porta_wdata = ibram_wdata_i;
        ibram_porta_we    = ibram_we_i && !running_bram_sync2_q;
      end
    end else begin
      ibram_porta_addr  = ibram_addr_i;
      ibram_porta_wdata = ibram_wdata_i;
      ibram_porta_we    = 1'b0;
    end
  end

  // Port A: host read + write (BRAM-friendly: single address, no async reset on array)
  always_ff @(posedge clk_bram_i) begin
    if (!phase_q)
      ibram_porta_rdata_q <= instr_mem[ibram_porta_addr];
    else if (ibram_porta_we)
      instr_mem[ibram_porta_addr] <= ibram_porta_wdata;
  end

  // Port A write latch: capture phase-0 WE arrivals for execution at phase 1
  always_ff @(posedge clk_bram_i or negedge rst_ni) begin
    if (!rst_ni) begin
      ibram_host_addr_q  <= '0;
      ibram_host_wdata_q <= '0;
      ibram_host_we_q    <= 1'b0;
    end else if (!phase_q) begin
      ibram_host_addr_q  <= ibram_addr_i;
      ibram_host_wdata_q <= ibram_wdata_i;
      ibram_host_we_q    <= ibram_we_i && !running_bram_sync2_q;
    end else begin
      ibram_host_we_q <= 1'b0;
    end
  end

  assign ibram_rdata_o = ibram_porta_rdata_q;

  // Port B: IF fetch (BRAM-friendly block -- no async reset on array)
  // Read at phase 1 (T/4 BEFORE clk_i): pc_q still holds pre-increment value,
  // matching the old clk_i sync-read behavior. Phase 0 fires AFTER clk_i, where
  // pc_q already has the new value -- reading there would fetch one instruction
  // ahead and shift all EX result addresses by one slot.
  always_ff @(posedge clk_i) begin
    ibram_portb_rdata_q <= instr_mem[pc_q];
  end

  // IF/ID pipeline register -- clk_i domain (same edge semantics as old clk_i BRAM read).
  // portb_rdata_q is captured at phase 1 (T/4 BEFORE clk_i), so it is stable with T/4
  // setup margin at the clk_i edge. Using clk_i here is critical: at the edge where
  // id_ex_valid_q first becomes 1 (stall about to assert), stall is still 0 in the
  // sequencer's NBA-sampled view (pre-edge id_ex_valid_q = 0), so ibram_fetch_rdata
  // captures the correct next instruction before the stall gate closes.
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni)
      ibram_fetch_rdata <= '0;
    else if (!stall)
      ibram_fetch_rdata <= ibram_portb_rdata_q;
  end

  // Operand capture gate: phase 0 (first in each cycle) reads at ibram_fetch_rdata addr
  // into dbram_*_rdata; phase 1 (second in each cycle) captures rdata into
  // op_a_q so that at the next clk_i edge (when ibram_fetch_rdata advances to id_ex_q)
  // the operands are already valid for arith_unit.
  logic capture_ops;
  assign capture_ops = if_id_valid_q && (!id_ex_valid_q || !stall);

  // -- DBRAM port A -- clocked at clk_bram ------------------------------
  // phase 0: latch data at dbram_porta_addr into dbram_porta_rdata
  // phase 1: capture dbram_porta_rdata into op_a_q (gated); write if dbram_porta_we
  // Memory array: sync only (no async reset) so Vivado infers BRAM
  always_ff @(posedge clk_bram_i) begin
    if (!phase_q) begin
      dbram_porta_rdata <= data_mem[dbram_porta_addr];
    end else begin
      if (dbram_porta_we)
        data_mem[dbram_porta_addr] <= dbram_porta_wdata;
    end
  end
  // Output registers: async reset allowed
  always_ff @(posedge clk_bram_i or negedge rst_ni) begin
    if (!rst_ni) begin
      op_a_q <= '0;
    end else if (phase_q && capture_ops) begin
      op_a_q <= dbram_porta_rdata;
    end
  end

  // fwd_q latched at clk_bram phase 1, the same edge as the data_mem write.
  // Critical: arith_result for comb ops (NEG/ABS/MOV/RELU) is purely
  // combinational on op_a_q, and op_a_q gets clobbered by the phase-1 capture
  // of the next instr's operands in the SAME edge. NB semantics evaluate the
  // RHS pre-edge so this latch sees the correct value; a clk_i latch would
  // re-evaluate the comb arith_result post-clobber and capture garbage.
  always_ff @(posedge clk_bram_i or negedge rst_ni) begin
    if (!rst_ni) begin
      fwd_q <= '0;
    end else if (phase_q && arith_valid_o && id_ex_valid_q && id_ex_q.writes_dbram) begin
      fwd_q <= arith_result;
    end
  end

  // -- DBRAM port B -- clocked at clk_bram ------------------------------
  // Memory array: sync only (no async reset) so Vivado infers BRAM
  always_ff @(posedge clk_bram_i) begin
    if (!phase_q) begin
      dbram_portb_rdata <= data_mem[dbram_portb_addr];
    end
  end
  // Output registers: async reset allowed
  always_ff @(posedge clk_bram_i or negedge rst_ni) begin
    if (!rst_ni) begin
      op_b_q <= '0;
    end else if (phase_q && capture_ops) begin
      op_b_q <= dbram_portb_rdata;
    end
  end

  // Host data BRAM read via port A registered output
  assign dbram_rdata_o = dbram_porta_rdata;

  // -- DBRAM host write latch -----------------------------------------------
  // When host port signals come from a clk_bram-domain AXI slave the WE pulse
  // is 1 clk_bram cycle wide and may land at phase 0 (before the write sub-cycle).
  // Latch at phase 0; execute at phase 1 via the always_comb default: branch.
  logic [$clog2(DATA_DEPTH)-1:0] dbram_host_addr_q;
  logic [DATA_WIDTH-1:0]         dbram_host_wdata_q;
  logic                          dbram_host_we_q;

  always_ff @(posedge clk_bram_i or negedge rst_ni) begin
    if (!rst_ni) begin
      dbram_host_addr_q  <= '0;
      dbram_host_wdata_q <= '0;
      dbram_host_we_q    <= 1'b0;
    end else if (!phase_q) begin
      dbram_host_addr_q  <= dbram_addr_i;
      dbram_host_wdata_q <= dbram_wdata_i;
      dbram_host_we_q    <= dbram_we_i && !running_bram_sync2_q;
    end else begin
      dbram_host_we_q <= 1'b0;
    end
  end

  // -- Pipeline registers ------------------------------------------------
  logic        if_id_valid_q;  // ibram_fetch_rdata holds a valid instruction

  // id_ex_q: decoded fields from ID stage. addr_a/addr_b are carried so the
  // forwarding mux can compare them against fwd_addr_q in EX.
  typedef struct packed {
    opcode_t     opcode;
    logic [19:0] addr_a;
    logic [19:0] addr_b;
    logic [19:0] addr_result;
    logic        writes_dbram;  // 1 if this instruction writes a result back to DBRAM
  } id_ex_t;

  id_ex_t id_ex_q;
  logic   id_ex_valid_q;  // id_ex_q holds a valid instruction

  // Forwarding: fwd_q holds the most recent EX result. fwd_hit_a_q/b_q are
  // pre-computed at the producer's clk_i edge (comparing the about-to-advance
  // ibram_fetch_rdata addr against the current EX addr_result), so the EX-cycle
  // critical path is just `fwd_hit_q ? fwd_q : op_q -> arith` with no compare.
  // Two-cycle-distant reads come from DBRAM directly (write committed at phase 1).
  logic [DATA_WIDTH-1:0] fwd_q;
  logic                  fwd_hit_a_q, fwd_hit_b_q;

  // Sync registers: re-sample clk_bram-domain FFs into clk_i domain.
  // op_a_q/op_b_q/fwd_q are launched by clk_bram phase 1 (T/2 before the next
  // clk_i edge). That T/2 window is smaller than the 29 ns PAU combinational path
  // at 30 MHz (T/2 = 16.7 ns). Capturing into clk_i FFs gives a full T window:
  // launched at edge N, captured at edge N+1. op_a_q already holds the current
  // instruction's operand before edge N (BRAM read completes at phase 1 of the
  // preceding ID cycle), so op_a_wr_q.Q at cycle N = correct operand with no
  // additional pipeline latency.
  logic [DATA_WIDTH-1:0] op_a_wr_q, op_b_wr_q, fwd_wr_q;
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      op_a_wr_q <= '0;
      op_b_wr_q <= '0;
      fwd_wr_q  <= '0;
    end else if (soft_reset_i) begin
      op_a_wr_q <= '0;
      op_b_wr_q <= '0;
      fwd_wr_q  <= '0;
    end else begin
      op_a_wr_q <= op_a_q;
      op_b_wr_q <= op_b_q;
      fwd_wr_q  <= fwd_q;
    end
  end

  // -- PC ----------------------------------------------------------------
  logic [$clog2(INSTR_DEPTH)-1:0] pc_q;

  // -- Top-level FSM ----------------------------------------------------
  typedef enum logic [1:0] { IDLE_S, RUNNING_S, HALT_S } seq_state_t;
  seq_state_t seq_state_q;

  // -- Arith unit interface ----------------------------------------------
  logic [DATA_WIDTH-1:0]  arith_op_a, arith_op_b;
  opcode_t                arith_opcode;
  logic                   arith_valid_i;
  logic [DATA_WIDTH-1:0]  arith_result;
  logic                   arith_valid_o;
  logic                   arith_ready_o;

  arith_unit u_arith (
    .clk_i,
    .rst_ni,
    .operand_a_i ( arith_op_a   ),
    .operand_b_i ( arith_op_b   ),
    .opcode_i    ( arith_opcode ),
    .valid_i     ( arith_valid_i ),
    .result_o    ( arith_result  ),
    .valid_o     ( arith_valid_o ),
    .ready_o     ( arith_ready_o )
  );

  // -- Needs-writeback helper ---------------------------------------------
  function automatic logic needs_wb(opcode_t op);
    case (op)
      OP_ADD, OP_SUB, OP_MUL, OP_DIV, OP_SQRT,
      OP_NEG, OP_ABS, OP_MOV, OP_RELU, OP_QACC_READ: return 1'b1;
      default: return 1'b0;
    endcase
  endfunction

  // -- Status outputs ----------------------------------------------------
  assign running_o = (seq_state_q == RUNNING_S);
  assign done_o    = (seq_state_q == HALT_S);

  // -- Stall detection --------------------------------------------------
  // Stall while the in-flight EX instruction has not yet produced a result.
  // Cleared in the same cycle arith_valid_o fires, so the pipeline advances
  // at the next edge. RAW hazards are resolved by the forwarding mux (below),
  // not by stalling.
  logic stall;
  always_comb begin
    stall = (seq_state_q == RUNNING_S) && id_ex_valid_q && !arith_valid_o;
  end


  // -- BRAM port address/control combinatorial ----------------------------
  always_comb begin
    dbram_porta_addr  = '0;
    dbram_porta_wdata = '0;
    dbram_porta_we    = 1'b0;
    dbram_portb_addr  = '0;
    arith_valid_i     = 1'b0;
    arith_op_a        = op_a_wr_q;
    arith_op_b        = op_b_wr_q;
    arith_opcode      = id_ex_q.opcode;

    unique case (seq_state_q)

      RUNNING_S: begin
        // -- IF: IBRAM port B output (ibram_fetch_rdata) updated by BRAM block

        // -- DBRAM: phase 0 = read operands for ID instruction;
        //           phase 1 = write result for EX instruction
        if (!phase_q) begin
          // Read sub-cycle: addr_a and addr_b for instruction currently in ID
          dbram_porta_addr = if_id_valid_q ? ibram_fetch_rdata[59:40] : '0;
          dbram_portb_addr = if_id_valid_q ? ibram_fetch_rdata[39:20] : '0;
        end else begin
          // Write sub-cycle: commit EX instruction's result when arith_valid_o
          if (id_ex_valid_q && arith_valid_o && id_ex_q.writes_dbram) begin
            dbram_porta_addr  = id_ex_q.addr_result;
            dbram_porta_wdata = arith_result;
            dbram_porta_we    = 1'b1;
          end
        end

        // -- EX: submit to arith_unit whenever it is ready. arith_unit raises
        //       ready_o=0 while busy, so this never double-issues. Operands
        //       come from the forwarding mux: if id_ex_q.addr_{a,b} matches
        //       fwd_addr_q, take fwd_q (last cycle's result) instead of the
        //       DBRAM read (which would be stale by exactly one cycle).
        if (id_ex_valid_q && arith_ready_o) begin
          arith_valid_i = 1'b1;
          arith_op_a    = fwd_hit_a_q ? fwd_wr_q : op_a_wr_q;
          arith_op_b    = fwd_hit_b_q ? fwd_wr_q : op_b_wr_q;
          arith_opcode  = id_ex_q.opcode;
        end
      end

      // Host access when stopped (IDLE_S or HALT_S).
      // Use write latch: phase-0 WE arrivals are in dbram_host_*_q by phase 1.
      // Direct phase-1 WE arrivals fall through to the else branch.
      default: begin
        dbram_porta_addr  = dbram_addr_i;
        dbram_porta_wdata = dbram_wdata_i;
        dbram_porta_we    = 1'b0;
        if (phase_q) begin
          if (dbram_host_we_q) begin
            dbram_porta_addr  = dbram_host_addr_q;
            dbram_porta_wdata = dbram_host_wdata_q;
            dbram_porta_we    = 1'b1;
          end else begin
            dbram_porta_we = dbram_we_i && !running_bram_sync2_q;
          end
        end
      end

    endcase
  end

  // -- Sequencer registers ----------------------------------------------
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      seq_state_q   <= IDLE_S;
      pc_q          <= '0;
      if_id_valid_q <= 1'b0;
      id_ex_q       <= '0;
      id_ex_valid_q <= 1'b0;
      fwd_hit_a_q   <= 1'b0;
      fwd_hit_b_q   <= 1'b0;
    end else if (soft_reset_i) begin
      seq_state_q   <= IDLE_S;
      pc_q          <= '0;
      if_id_valid_q <= 1'b0;
      id_ex_q       <= '0;
      id_ex_valid_q <= 1'b0;
      fwd_hit_a_q   <= 1'b0;
      fwd_hit_b_q   <= 1'b0;
    end else begin

      unique case (seq_state_q)

        IDLE_S: begin
          if (start_i) begin
            seq_state_q   <= RUNNING_S;
            pc_q          <= '0;
            if_id_valid_q <= 1'b0;
            id_ex_q       <= '0;
            id_ex_valid_q <= 1'b0;
            fwd_hit_a_q   <= 1'b0;
            fwd_hit_b_q   <= 1'b0;
          end
        end

        RUNNING_S: begin

          if (!stall) begin
            // Pre-compute forwarding hits for the EX cycle starting next edge.
            // Compares the next-EX's addr_a/b (from ibram_fetch_rdata) against
            // the producer's addr_result. Gated on producer actually writing.
            fwd_hit_a_q <= arith_valid_o && id_ex_valid_q && id_ex_q.writes_dbram
                        && (ibram_fetch_rdata[59:40] == id_ex_q.addr_result);
            fwd_hit_b_q <= arith_valid_o && id_ex_valid_q && id_ex_q.writes_dbram
                        && (ibram_fetch_rdata[39:20] == id_ex_q.addr_result);

            // -- ID -> EX: decode ibram_fetch_rdata into EX stage
            if (if_id_valid_q) begin
              if (opcode_t'(ibram_fetch_rdata[63:60]) == OP_HALT) begin
                // HALT: flush EX; transition to HALT_S
                seq_state_q   <= HALT_S;
                id_ex_valid_q <= 1'b0;
              end else begin
                id_ex_q.opcode       <= opcode_t'(ibram_fetch_rdata[63:60]);
                id_ex_q.addr_a       <= ibram_fetch_rdata[59:40];
                id_ex_q.addr_b       <= ibram_fetch_rdata[39:20];
                id_ex_q.addr_result  <= ibram_fetch_rdata[19:0];
                id_ex_q.writes_dbram <= needs_wb(opcode_t'(ibram_fetch_rdata[63:60]));
                id_ex_valid_q        <= 1'b1;
              end
            end else begin
              // Bubble propagating through pipeline (fill cycles at startup)
              id_ex_valid_q <= 1'b0;
            end

            // -- IF: BRAM port B output (ibram_fetch_rdata) already holds
            //    instr_mem[pc_q] -- mark valid for next cycle's decode.
            if_id_valid_q <= 1'b1;

            // -- PC advance ------------------------------------------------
            pc_q <= pc_q + 1;
          end
          // else: stall -- id_ex_q, ibram_fetch_rdata, pc_q all frozen
        end

        HALT_S: begin
          if (start_i) begin
            seq_state_q   <= RUNNING_S;
            pc_q          <= '0;
            if_id_valid_q <= 1'b0;
            id_ex_q       <= '0;
            id_ex_valid_q <= 1'b0;
            fwd_hit_a_q   <= 1'b0;
            fwd_hit_b_q   <= 1'b0;
          end
        end

        default: seq_state_q <= IDLE_S;

      endcase
    end
  end

  // -- Assertions ------------------------------------------------------
  // synthesis translate_off

  // 1. done_o and running_o are mutually exclusive.
  ap_done_not_running: assert property (
    @(posedge clk_i) disable iff (!rst_ni)
    done_o |-> !running_o
  ) else $error("ASSERT ap_done_not_running: done_o high while running_o high");

  // 2. arith_valid_o must only fire while the sequencer is active.
  ap_arith_valid_gated: assert property (
    @(posedge clk_i) disable iff (!rst_ni)
    arith_valid_o |-> running_o
  ) else $error("ASSERT ap_arith_valid_gated: arith_valid_o fired while not running");

  // 3. arith_valid_i must not fire when arith is not ready.
  ap_no_double_submit: assert property (
    @(posedge clk_i) disable iff (!rst_ni)
    arith_valid_i |-> arith_ready_o
  ) else $error("ASSERT ap_no_double_submit: arith_valid_i fired when not ready");

  // synthesis translate_on

endmodule
