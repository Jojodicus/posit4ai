// PERCIVAL Accelerator -- core: instruction BRAM + data BRAM + 3-stage pipeline + arith_unit.
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

  // -- IBRAM -- true dual-port BRAM -------------------------------------
  // Memory array: sync only (no async reset) so Vivado infers BRAM.
  //
  // Port A -- host read/write (ibram_addr_i), clk_i
  // Port B -- IF-stage fetch  (pc_q, read-only), clk_i

  logic [63:0] ibram_fetch_rdata;  // port B registered output (serves as IF/ID reg)

  // Port A -- host access
  always_ff @(posedge clk_i) begin
    if (ibram_we_i && !running_o)
      instr_mem[ibram_addr_i] <= ibram_wdata_i;
    ibram_rdata_o <= instr_mem[ibram_addr_i];
  end

  // Port B -- sequencer instruction fetch (read-only, sync, with read-enable)
  // Gate on !stall so ibram_fetch_rdata holds its value while the pipeline is
  // frozen (pc_q was already advanced past the IF-stage instruction).
  // When not in RUNNING_S, stall=0 so reads proceed freely (don't-care data).
  always_ff @(posedge clk_i) begin
    if (!stall)
      ibram_fetch_rdata <= instr_mem[pc_q];
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
    arith_op_a        = op_a_q;
    arith_op_b        = op_b_q;
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
          arith_op_a    = fwd_hit_a_q ? fwd_q : op_a_q;
          arith_op_b    = fwd_hit_b_q ? fwd_q : op_b_q;
          arith_opcode  = id_ex_q.opcode;
        end
      end

      // Host access when stopped (IDLE_S or HALT_S)
      default: begin
        dbram_porta_addr  = dbram_addr_i;
        dbram_porta_wdata = dbram_wdata_i;
        // Gate host writes to phase 1 so they land correctly in the 2x clock domain
        dbram_porta_we    = dbram_we_i && !running_o && phase_q;
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
