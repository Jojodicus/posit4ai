// PERCIVAL Accelerator -- arithmetic unit wrapper.
// Instantiates either pau_top (PAU) or fpu_wrap (FPU) based on config_pkg::ACCEL_TYPE.
// Presents a uniform (operand_a, operand_b, opcode, valid_i) -> (result, valid_o, ready_o)
// interface to accel_core.
//
// Pipelined issue model:
//   S_IDLE  : ready_o=1; can accept comb op (zero-latency) or issue to PAU/FPU.
//   S_BUSY  : op in-flight in PAU/FPU. When arith_valid_o fires:
//             - For non-2-pass ops: assert valid_o + result_o same cycle, return to
//               S_IDLE, and accept a new op THIS SAME CYCLE if valid_i is high.
//             - For 2-pass MAC (PAU-32/64 no-quire QMADD/QMSUB): capture mul result
//               and transition to S_MAC_STEP.
//   S_MAC_STEP : issue PADD/PSUB second pass.
//   S_MAC_BUSY : wait for second pass; on arith_valid_o, fire valid_o and accept
//                a new op same cycle.
//
// Eliminates the DONE-state delay of the previous FSM (saves 1 cycle per op) and
// allows true back-to-back issue once PAU/FPU is ready again.

module arith_unit
  import config_pkg::*;
  import opcodes_pkg::*;
  import ariane_pkg::*;
(
  input  logic                    clk_i,
  input  logic                    rst_ni,
  input  logic [DATA_WIDTH-1:0]   operand_a_i,
  input  logic [DATA_WIDTH-1:0]   operand_b_i,
  input  opcode_t                 opcode_i,
  input  logic                    valid_i,
  output logic [DATA_WIDTH-1:0]   result_o,
  output logic                    valid_o,
  output logic                    ready_o,
  // 1 cycle before valid_o for PAU (delayed-fire) path; same cycle as valid_o
  // for comb/FPU paths. Signals the upstream pipeline that it can advance.
  output logic                    about_to_fire_o,
  // 1 when valid_o this cycle corresponds to a PAU op issued in a PRIOR
  // cycle (i.e. the writeback address lives in accel_core's wb_q shadow,
  // not in id_ex_q). 0 for same-cycle comb/FPU fires.
  output logic                    fire_delayed_o
);

  localparam logic [DATA_WIDTH-1:0] POSIT_ONE = DATA_WIDTH'(1) << (DATA_WIDTH-2);

  localparam bit IS_FLO_PAU     = (ACCEL_TYPE == "FLO_PAU");
  localparam bit IS_PAU         = (ACCEL_TYPE == "PAU") || IS_FLO_PAU;
  localparam bit USE_FLOPOCO    = IS_FLO_PAU || (IS_PAU && bit'(DATA_WIDTH < 32));
  localparam bit QUIRE_ENABLE   = (QUIRE_MODE == "QUIRE");
  localparam bit QUIRE_DISABLED = (QUIRE_MODE == "DISABLED");
  localparam bit DIV_DISABLED   = (DIV_MODE   == "DISABLE");
  localparam bit SQRT_DISABLED  = (SQRT_MODE  == "DISABLE");
  localparam bit PAU_NO_QUIRE     = IS_PAU      & (QUIRE_MODE == "ACCUMULATOR");
  localparam bit FLO_PAU_NO_QUIRE = USE_FLOPOCO & (QUIRE_MODE == "ACCUMULATOR");

  localparam logic [DATA_WIDTH-1:0] POSIT_NAR      = DATA_WIDTH'(1) << (DATA_WIDTH-1);
  localparam logic [DATA_WIDTH-1:0] DISABLED_RESULT =
    IS_PAU      ? POSIT_NAR :
    DATA_WIDTH == 32 ? DATA_WIDTH'(32'h7FC0_0000) :
                       DATA_WIDTH'(64'h7FF8_0000_0000_0000);

  // 2-pass MAC = PAU-32/64 no-quire QMADD/QMSUB (PMUL then PADD/PSUB).
  // FLO_PAU_NO_QUIRE handles QMADD/QMSUB in flopau (single op).
  localparam bit USE_2PASS_MAC = PAU_NO_QUIRE && !FLO_PAU_NO_QUIRE;

  typedef enum logic [1:0] { S_IDLE, S_BUSY, S_MAC_STEP, S_MAC_BUSY } state_t;
  state_t state_q, state_d;

  opcode_t                opcode_q, opcode_d;

  logic [DATA_WIDTH-1:0]  result_q,    result_d;
  logic [DATA_WIDTH-1:0]  acc_q,       acc_d;
  logic [DATA_WIDTH-1:0]  mul_result_q, mul_result_d;

  // -- PAU / FPU interfaces -----------------------------------------------
  fu_data_t         pau_fu_data;
  logic             pau_valid_i_sig;
  logic             pau_ready_o_sig;
  logic             pau_valid_o_sig;
  logic             pau_about_to_fire_sig;
  riscv::xlen_t     pau_result_sig;

  fu_data_t         fpu_fu_data;
  logic             fpu_valid_i_sig;
  logic             fpu_ready_o_sig;
  logic             fpu_valid_o_sig;
  logic [FLEN-1:0]  fpu_result_sig;

  if (USE_FLOPOCO) begin : g_flopau
    flo_posit_top flopau_inst (
      .clk_i, .rst_ni,
      .fu_data_i          ( pau_fu_data    ),
      .pau_valid_i        ( pau_valid_i_sig ),
      .pau_ready_o        ( pau_ready_o_sig ),
      .pau_trans_id_o     (                ),
      .pau_valid_o        ( pau_valid_o_sig ),
      .pau_about_to_fire_o( pau_about_to_fire_sig ),
      .result_o           ( pau_result_sig  )
    );
    assign fpu_ready_o_sig = 1'b0;
    assign fpu_valid_o_sig = 1'b0;
    assign fpu_result_sig  = '0;
  end else if (ACCEL_TYPE == "PAU") begin : g_pau
    pau_top pau_inst (
      .clk_i, .rst_ni,
      .fu_data_i          ( pau_fu_data    ),
      .pau_valid_i        ( pau_valid_i_sig ),
      .pau_ready_o        ( pau_ready_o_sig ),
      .pau_trans_id_o     (                ),
      .pau_valid_o        ( pau_valid_o_sig ),
      .pau_about_to_fire_o( pau_about_to_fire_sig ),
      .result_o           ( pau_result_sig  )
    );
    assign fpu_ready_o_sig = 1'b0;
    assign fpu_valid_o_sig = 1'b0;
    assign fpu_result_sig  = '0;
  end else begin : g_fpu
    fpu_wrap fpu_inst (
      .clk_i, .rst_ni,
      .flush_i          ( 1'b0             ),
      .fpu_valid_i      ( fpu_valid_i_sig   ),
      .fpu_ready_o      ( fpu_ready_o_sig   ),
      .fu_data_i        ( fpu_fu_data       ),
      .fpu_fmt_i        ( DATA_WIDTH == 64 ? 2'b01 : 2'b00 ),
      .fpu_rm_i         ( 3'b000            ),
      .fpu_frm_i        ( 3'b000            ),
      .fpu_prec_i       ( 7'b0              ),
      .fpu_trans_id_o   (                   ),
      .result_o         ( fpu_result_sig    ),
      .fpu_valid_o      ( fpu_valid_o_sig   ),
      .fpu_exception_o  (                   )
    );
    assign pau_ready_o_sig        = 1'b0;
    assign pau_valid_o_sig        = 1'b0;
    assign pau_about_to_fire_sig  = 1'b0;
    assign pau_result_sig         = '0;
  end

  logic                  arith_valid_o_int;
  logic [DATA_WIDTH-1:0] arith_result;
  assign arith_valid_o_int = IS_PAU ? pau_valid_o_sig : fpu_valid_o_sig;
  assign arith_result      = IS_PAU
                             ? pau_result_sig[DATA_WIDTH-1:0]
                             : fpu_result_sig[DATA_WIDTH-1:0];

  // -- Combinatorial opcode classification ---------------------------
  logic is_comb_op;
  always_comb begin
    is_comb_op = 1'b0;
    case (opcode_i)
      OP_NEG, OP_ABS, OP_MOV, OP_RELU: is_comb_op = 1'b1;
      OP_DIV:  if (DIV_DISABLED)  is_comb_op = 1'b1;
      OP_SQRT: if (SQRT_DISABLED) is_comb_op = 1'b1;
      OP_QACC_CLEAR, OP_QACC_NEG, OP_QACC_READ:
        if (QUIRE_DISABLED || !IS_PAU || (PAU_NO_QUIRE && !FLO_PAU_NO_QUIRE))
          is_comb_op = 1'b1;
      OP_QACC_ADD, OP_QACC_MADD, OP_QACC_MSUB:
        if (QUIRE_DISABLED) is_comb_op = 1'b1;
      default: ;
    endcase
  end

  logic [DATA_WIDTH-1:0] comb_result;
  always_comb begin
    comb_result = '0;
    if (IS_PAU) begin
      case (opcode_i)
        OP_NEG:       comb_result = ~operand_a_i + DATA_WIDTH'(1);
        OP_ABS:       comb_result = operand_a_i[DATA_WIDTH-1]
                                    ? (~operand_a_i + DATA_WIDTH'(1))
                                    : operand_a_i;
        OP_MOV:       comb_result = operand_a_i;
        OP_RELU:      comb_result = operand_a_i[DATA_WIDTH-1] ? '0 : operand_a_i;
        OP_DIV:       if (DIV_DISABLED)  comb_result = DISABLED_RESULT;
        OP_SQRT:      if (SQRT_DISABLED) comb_result = DISABLED_RESULT;
        OP_QACC_READ: if (!QUIRE_ENABLE)
                        comb_result = QUIRE_DISABLED ? DISABLED_RESULT : acc_q;
        OP_QACC_CLEAR, OP_QACC_NEG,
        OP_QACC_ADD, OP_QACC_MADD, OP_QACC_MSUB:
          if (QUIRE_DISABLED) comb_result = DISABLED_RESULT;
        default: ;
      endcase
    end else begin
      case (opcode_i)
        OP_NEG:        comb_result = (operand_a_i == '0)
                                   ? '0
                                   : {~operand_a_i[DATA_WIDTH-1], operand_a_i[DATA_WIDTH-2:0]};
        OP_ABS:        comb_result = {1'b0, operand_a_i[DATA_WIDTH-2:0]};
        OP_MOV:        comb_result = operand_a_i;
        OP_RELU:       comb_result = operand_a_i[DATA_WIDTH-1] ? '0 : operand_a_i;
        OP_DIV:        if (DIV_DISABLED)  comb_result = DISABLED_RESULT;
        OP_SQRT:       if (SQRT_DISABLED) comb_result = DISABLED_RESULT;
        OP_QACC_CLEAR: comb_result = QUIRE_DISABLED ? DISABLED_RESULT : '0;
        OP_QACC_NEG:   comb_result = QUIRE_DISABLED ? DISABLED_RESULT : '0;
        OP_QACC_READ:  comb_result = QUIRE_DISABLED ? DISABLED_RESULT : acc_q;
        OP_QACC_ADD, OP_QACC_MADD, OP_QACC_MSUB:
          if (QUIRE_DISABLED) comb_result = DISABLED_RESULT;
        default: ;
      endcase
    end
  end

  // -- PAU operand/op mux ----------------------------------------------
  logic [DATA_WIDTH-1:0] pau_op_a, pau_op_b;
  fu_op                  pau_fu_op;

  always_comb begin
    pau_op_a  = operand_a_i;
    pau_op_b  = operand_b_i;
    pau_fu_op = PADD;

    if (state_q == S_MAC_STEP) begin
      // Second pass of QMADD/QMSUB (no-quire PAU-32/64). Operands come from
      // the registered acc and the just-captured mul result.
      if (opcode_q == OP_QACC_MSUB) begin
        pau_fu_op = PSUB;
        pau_op_a  = acc_q;
        pau_op_b  = mul_result_q;
      end else begin
        pau_fu_op = PADD;
        pau_op_a  = mul_result_q;
        pau_op_b  = acc_q;
      end
    end else begin
      case (opcode_i)
        OP_ADD:        pau_fu_op = PADD;
        OP_SUB:        pau_fu_op = PSUB;
        OP_MUL:        pau_fu_op = PMUL;
        OP_DIV:        pau_fu_op = PDIV;
        OP_SQRT:       pau_fu_op = PSQRT;
        OP_QACC_ADD: begin
          if (USE_2PASS_MAC) begin
            pau_fu_op = PADD;
            pau_op_a  = operand_a_i;
            pau_op_b  = acc_q;
          end else begin
            pau_fu_op = QMADD;
            pau_op_b  = POSIT_ONE;
          end
        end
        OP_QACC_MADD:  pau_fu_op = USE_2PASS_MAC ? PMUL : QMADD;
        OP_QACC_MSUB:  pau_fu_op = USE_2PASS_MAC ? PMUL : QMSUB;
        OP_QACC_CLEAR: pau_fu_op = QCLR;
        OP_QACC_NEG:   pau_fu_op = QNEG;
        OP_QACC_READ:  pau_fu_op = QROUND;
        default: ;
      endcase
    end
  end

  always_comb begin
    pau_fu_data           = '0;
    pau_fu_data.fu        = PAU;
    pau_fu_data.operator  = pau_valid_i_sig ? pau_fu_op : PADD;
    if (DATA_WIDTH == riscv::XLEN) begin
      pau_fu_data.operand_a = pau_op_a;
      pau_fu_data.operand_b = pau_op_b;
    end else begin
      pau_fu_data.operand_a = {{riscv::XLEN-DATA_WIDTH{1'b0}}, pau_op_a};
      pau_fu_data.operand_b = {{riscv::XLEN-DATA_WIDTH{1'b0}}, pau_op_b};
    end
  end

  // -- FPU operand/op mux ----------------------------------------------
  logic [FLEN-1:0] fpu_box_a, fpu_box_b, fpu_box_acc;
  if (DATA_WIDTH == 32) begin : g_nanbox
    assign fpu_box_a   = {{32{1'b1}}, operand_a_i};
    assign fpu_box_b   = {{32{1'b1}}, operand_b_i};
    assign fpu_box_acc = {{32{1'b1}}, acc_q};
  end else begin : g_nonanbox
    assign fpu_box_a   = operand_a_i;
    assign fpu_box_b   = operand_b_i;
    assign fpu_box_acc = acc_q;
  end

  fu_op fpu_fu_op;
  always_comb begin
    fpu_fu_op             = FADD;
    fpu_fu_data           = '0;
    fpu_fu_data.fu        = FPU;
    fpu_fu_data.operand_a = fpu_box_a;
    fpu_fu_data.operand_b = fpu_box_b;
    fpu_fu_data.imm       = fpu_box_b;

    case (opcode_i)
      OP_ADD: begin
        fpu_fu_op             = FADD;
        fpu_fu_data.operand_b = fpu_box_a;
        fpu_fu_data.imm       = fpu_box_b;
      end
      OP_SUB: begin
        fpu_fu_op             = FSUB;
        fpu_fu_data.operand_b = fpu_box_a;
        fpu_fu_data.imm       = fpu_box_b;
      end
      OP_MUL:  fpu_fu_op = FMUL;
      OP_DIV:  fpu_fu_op = FDIV;
      OP_SQRT: fpu_fu_op = FSQRT;
      OP_QACC_ADD: begin
        fpu_fu_op             = FADD;
        fpu_fu_data.operand_b = fpu_box_acc;
        fpu_fu_data.imm       = fpu_box_a;
      end
      OP_QACC_MADD: begin
        fpu_fu_op       = FMADD;
        fpu_fu_data.imm = fpu_box_acc;
      end
      OP_QACC_MSUB: begin
        fpu_fu_op       = FNMSUB;
        fpu_fu_data.imm = fpu_box_acc;
      end
      default: ;
    endcase
    fpu_fu_data.operator = fpu_fu_op;
  end

  // -- Acc update for QACC_CLEAR/NEG comb path -----------------------
  function automatic logic [DATA_WIDTH-1:0] negate_acc(logic [DATA_WIDTH-1:0] v);
    if (IS_PAU) negate_acc = ~v + DATA_WIDTH'(1);
    else        negate_acc = (v == '0) ? '0 : {~v[DATA_WIDTH-1], v[DATA_WIDTH-2:0]};
  endfunction

  // -- Control --------------------------------------------------------
  // accept_new: ready to consume a fresh op this cycle.
  //   - S_IDLE: always.
  //   - S_BUSY: when arith_valid_o fires AND the result is final (not 2-pass first half).
  //   - S_MAC_BUSY: when arith_valid_o fires (second pass complete).
  // valid_o: pulse when the current op finishes this cycle (comb path or arith path).
  logic accept_new;
  logic firing_arith_result;

  always_comb begin
    state_d         = state_q;
    opcode_d        = opcode_q;
    result_d        = result_q;
    acc_d           = acc_q;
    mul_result_d    = mul_result_q;
    pau_valid_i_sig = 1'b0;
    fpu_valid_i_sig = 1'b0;
    valid_o         = 1'b0;
    accept_new      = 1'b0;
    firing_arith_result = 1'b0;

    unique case (state_q)
      S_IDLE: begin
        accept_new = 1'b1;
      end

      S_BUSY: begin
        if (arith_valid_o_int) begin
          if (USE_2PASS_MAC && opcode_q inside {OP_QACC_MADD, OP_QACC_MSUB}) begin
            mul_result_d = arith_result;
            state_d      = S_MAC_STEP;
          end else begin
            if (!FLO_PAU_NO_QUIRE && opcode_q inside {OP_QACC_ADD, OP_QACC_MADD, OP_QACC_MSUB})
              acc_d = arith_result;
            result_d = arith_result;
            valid_o  = 1'b1;
            firing_arith_result = 1'b1;
            state_d  = S_IDLE;
            // Back-to-back issue for non-comb ops: advance pipeline now, issue
            // next PAU/FPU op same cycle. Comb next-ops fall through to S_IDLE
            // and issue next cycle (avoids result-bus collision).
            // Gating on is_comb_op only (not valid_i) avoids a comb loop
            // through ready_o -> arith_valid_i -> accept_new.
            if (!is_comb_op) accept_new = 1'b1;
          end
        end
      end

      S_MAC_STEP: begin
        // Issue second PAU op (PADD/PSUB). pau_op_a/b/op already overridden above.
        pau_valid_i_sig = 1'b1;
        state_d         = S_MAC_BUSY;
      end

      S_MAC_BUSY: begin
        if (arith_valid_o_int) begin
          acc_d    = arith_result;
          result_d = arith_result;
          valid_o  = 1'b1;
          firing_arith_result = 1'b1;
          state_d  = S_IDLE;
          if (!is_comb_op) accept_new = 1'b1;
        end
      end

      default: state_d = S_IDLE;
    endcase

    // Issue path: when accepting a new op this cycle. Overrides state_d/result_d
    // assignments above (intended).
    if (accept_new && valid_i) begin
      if (is_comb_op) begin
        result_d = comb_result;
        valid_o  = 1'b1;
        if (opcode_i == OP_QACC_CLEAR && !QUIRE_DISABLED)
          acc_d = '0;
        if (opcode_i == OP_QACC_NEG && !QUIRE_DISABLED)
          acc_d = negate_acc(acc_q);
        // state stays S_IDLE
        state_d = S_IDLE;
      end else begin
        if (IS_PAU) pau_valid_i_sig = 1'b1;
        else        fpu_valid_i_sig = 1'b1;
        opcode_d = opcode_i;
        state_d  = S_BUSY;
      end
    end
  end

  assign ready_o = accept_new;

  // about_to_fire_o: tells accel_core its pipeline can advance this cycle.
  //   - Comb op fires this cycle    -> same cycle as valid_o.
  //   - PAU (non-MAC) delayed fire  -> 1 cycle before valid_o (pau_about_to_fire_sig).
  //   - PAU 2-pass MAC or FPU       -> same cycle as valid_o (no early signal).
  // fire_delayed_o: high only for the PAU delayed-fire case; lets accel_core
  // route the writeback address through its wb_q shadow (because id_ex_q has
  // already advanced by the time valid_o fires).
  logic comb_fire_now;
  assign comb_fire_now = accept_new && valid_i && is_comb_op;
  always_comb begin
    about_to_fire_o = 1'b0;
    // about_to_fire_o: 1 cycle before valid_o for PAU delayed path; same
    // cycle for comb / FPU / PAU-MAC-2nd-pass.
    if (comb_fire_now)
      about_to_fire_o = 1'b1;
    if (IS_PAU && (state_q == S_BUSY) && pau_about_to_fire_sig
        && !(USE_2PASS_MAC && opcode_q inside {OP_QACC_MADD, OP_QACC_MSUB}))
      about_to_fire_o = 1'b1;
    if ((state_q == S_MAC_BUSY) && arith_valid_o_int)
      about_to_fire_o = 1'b1;
    if (!IS_PAU && (state_q == S_BUSY) && arith_valid_o_int)
      about_to_fire_o = 1'b1;
  end

  // fire_delayed_o: fires at the valid_o cycle for PAU (non-MAC, non-FPU)
  // paths, where id_ex_q has already advanced. accel_core reads from wb_q.
  // Not set for comb / FPU / MAC-2nd-pass (same-cycle fire; id_ex_q still
  // holds the producer at phase-1 writeback).
  assign fire_delayed_o = IS_PAU && firing_arith_result && (state_q == S_BUSY);

  // result_o priority:
  //   1. firing_arith_result this cycle -> arith_result
  //   2. accepting a comb op this cycle -> comb_result
  //   3. otherwise -> registered result_q (stable from previous valid_o)
  always_comb begin
    if (firing_arith_result)
      result_o = arith_result;
    else if (accept_new && valid_i && is_comb_op)
      result_o = comb_result;
    else
      result_o = result_q;
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q      <= S_IDLE;
      opcode_q     <= OP_HALT;
      result_q     <= '0;
      acc_q        <= '0;
      mul_result_q <= '0;
    end else begin
      state_q      <= state_d;
      opcode_q     <= opcode_d;
      result_q     <= result_d;
      acc_q        <= acc_d;
      mul_result_q <= mul_result_d;
    end
  end

endmodule
