// PERCIVAL Accelerator -- core: instruction BRAM + data BRAM + 3-stage pipeline + arith_unit.
//
// Instruction format (64-bit fixed-width):
//   [63:60] opcode       4 bits  (16 opcodes)
//   [59:40] addr_a      20 bits  (up to 1M data words)
//   [39:20] addr_b      20 bits
//   [19: 0] addr_result 20 bits
//
// Step B -- 3-stage pipeline with 2x BRAM clock (XAPP706 alpha-blending technique):
//
//   All three stages run in parallel each clk_i cycle:
//   IF  : Present PC to IBRAM port B; registered output -> ibram_fetch_rdata.
//   ID  : Decode ibram_fetch_rdata; present addr_a/addr_b to DBRAM at clk_bram phase 0;
//         capture operands into op_a_q/op_b_q at phase 1.
//   EX  : Submit op_a_q/op_b_q to arith_unit (when ready); write result to DBRAM
//         at phase 1 when arith_valid_o fires.
//
// clk_bram = 2x clk_i, phase-aligned:
//   phase 0 (1st clk_bram edge after clk_i ^): DBRAM reads addr_a (port A) and addr_b (port B)
//   phase 1 (2nd clk_bram edge): capture dbram output -> op_a_q/op_b_q; write result (port A)
//
// Stall (pipeline freeze):
//   RAW hazard: EX instruction will write to an address read by ID instruction and
//               the write has not yet been committed (tracked by ex_wrote_q).
//   Arith busy: EX instruction is in-flight (arith_ready_o=0).
//   When stall=1: id_ex_q, ibram_fetch_rdata, pc_q all frozen; no pipeline advance.
//   Stall costs: zero-lat RAW +1 cy; 1-cycle arith baseline ~3 cy (WAIT+DONE+resume).
//
// arith_valid_i is only asserted when arith_ready_o, preventing double-submission.
//
// Top-level FSM (4 states -- stages run in parallel inside RUNNING_S):
//   IDLE_S  : waiting for start_i; pipeline empty
//   RUNNING_S: pipeline active; stall/advance based on hazards
//   HALT_S  : OP_HALT reached; done_o asserted

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
  logic [63:0]           instr_mem [0:INSTR_DEPTH-1];
  logic [DATA_WIDTH-1:0] data_mem  [0:DATA_DEPTH-1];

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

  // id_ex_q: decoded fields from ID stage
  typedef struct packed {
    opcode_t     opcode;
    logic [19:0] addr_a;
    logic [19:0] addr_b;
    logic [19:0] addr_result;
    logic        writes_dbram;  // 1 if this instruction writes a result back to DBRAM
  } id_ex_t;

  id_ex_t id_ex_q;
  logic   id_ex_valid_q;  // id_ex_q holds a valid instruction

  // ex_complete_q: set when arith_valid_o fires for the current EX instruction.
  // Stays 1 for one extra cycle after the arith result is produced/committed,
  // so phase 0 of that cycle re-reads the just-written DBRAM data into
  // op_a_q/op_b_q at phase 1. Cleared on pipeline advance.
  logic ex_complete_q;

  // -- PC ----------------------------------------------------------------
  logic [$clog2(INSTR_DEPTH)-1:0] pc_q;

  // -- Top-level FSM ----------------------------------------------------
  typedef enum logic [1:0] { IDLE_S, RUNNING_S, HALT_S, UNUSED_S } seq_state_t;
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
  // Simple rule: while an instruction is in EX, stall until its arith result has
  // been observed (ex_complete_q=1). During that final "complete" cycle, phase 0
  // re-reads the next instruction's operands from DBRAM (now including this
  // instruction's just-written result), phase 1 captures them into op_a_q/op_b_q,
  // and at the next clk_i edge the pipeline advances with fresh operands. This
  // subsumes both RAW hazards and arith-busy stalls and keeps id_ex_q stable
  // while arith_unit is in-flight so the write-back targets the correct address.
  logic stall;
  always_comb begin
    stall = (seq_state_q == RUNNING_S) && id_ex_valid_q && !ex_complete_q;
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

        // -- EX: submit to arith_unit only when it is ready AND we haven't
        //       already observed completion for the current EX instruction.
        //       The !ex_complete_q gate prevents re-issue on the trailing
        //       "re-read" cycle (when arith_unit has returned to IDLE but
        //       id_ex_q is still holding the just-completed instruction).
        if (id_ex_valid_q && arith_ready_o && !ex_complete_q) begin
          arith_valid_i = 1'b1;
          arith_op_a    = op_a_q;
          arith_op_b    = op_b_q;
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
      ex_complete_q <= 1'b0;
    end else begin

      unique case (seq_state_q)

        IDLE_S: begin
          if (start_i) begin
            seq_state_q   <= RUNNING_S;
            pc_q          <= '0;
            if_id_valid_q <= 1'b0;
            id_ex_q       <= '0;
            id_ex_valid_q <= 1'b0;
            ex_complete_q <= 1'b0;
          end
        end

        RUNNING_S: begin
          // Track arith completion for the current EX instruction.
          // Priority: !stall (pipeline about to advance) clears the flag so the
          // next instruction starts with ex_complete_q=0; otherwise, latch 1
          // when arith_valid_o fires while id_ex_q is valid.
          if (!stall) begin
            ex_complete_q <= 1'b0;
          end else if (arith_valid_o && id_ex_valid_q) begin
            ex_complete_q <= 1'b1;
          end

          if (!stall) begin
            // -- ID -> EX: decode ibram_fetch_rdata into EX stage
            if (if_id_valid_q) begin
              if (opcode_t'(ibram_fetch_rdata[63:60]) == OP_HALT) begin
                // HALT: flush EX; transition to HALT_S
                seq_state_q   <= HALT_S;
                id_ex_valid_q <= 1'b0;
              end else begin
                id_ex_q.opcode      <= opcode_t'(ibram_fetch_rdata[63:60]);
                id_ex_q.addr_a      <= ibram_fetch_rdata[59:40];
                id_ex_q.addr_b      <= ibram_fetch_rdata[39:20];
                id_ex_q.addr_result <= ibram_fetch_rdata[19:0];
                id_ex_q.writes_dbram <= needs_wb(opcode_t'(ibram_fetch_rdata[63:60]));
                id_ex_valid_q       <= 1'b1;
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
            ex_complete_q <= 1'b0;
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
