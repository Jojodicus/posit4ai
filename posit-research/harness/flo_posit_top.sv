// FloPoCo-based Posit Arithmetic Unit top for posit(8,2) and posit(16,2).
// Presents the same port interface as pau_top.sv so arith_unit.sv requires
// only a minimal routing change.
//
// All FloPoCo arithmetic blocks are combinatorial; outputs are registered by
// a single flip-flop stage inside this module → 1-cycle latency for all ops.
//
// Supported operations (via ariane_pkg fu_op):
//   PADD, PSUB, PMUL, PDIV   — arithmetic
//   QMADD, QMSUB, QCLR, QNEG — quire accumulation
//   QROUND                    — quire → posit readout (via quire2posit_sm)
//   PSQRT                     — returns NaR (unsupported in FloPoCo)
//
// APPROX_MUL (POS_LOG_MULT=1): uses PositLAM (log-domain approximate multiplier)
// APPROX_DIV / APPROX_SQRT:    no effect — PositDiv is always used; SQRT → NaR

module flo_posit_top import ariane_pkg::*; (
    input  logic                     clk_i,
    input  logic                     rst_ni,
    input  fu_data_t                 fu_data_i,
    input  logic                     pau_valid_i,
    output logic                     pau_ready_o,
    output logic [TRANS_ID_BITS-1:0] pau_trans_id_o,
    output logic                     pau_valid_o,
    output riscv::xlen_t             result_o
);

  // ── Sanity check ─────────────────────────────────────────────────────────────
  if (POSLEN != 8 && POSLEN != 16)
    $fatal("flo_posit_top: only POSLEN=8 or POSLEN=16 is supported");

  // ── Local constants ───────────────────────────────────────────────────────────
  localparam logic [POSLEN-1:0] NAR = {1'b1, {(POSLEN-1){1'b0}}};

  // ── Input decoding ────────────────────────────────────────────────────────────
  enum logic {READY, STALL} state_q, state_d;

  logic [TRANS_ID_BITS-1:0] trans_id_d, trans_id_q;
  logic                     pau_valid_d;
  logic [3:0]               latency_d, latency_q;
  logic [3:0]               count;
  logic                     hold_inputs, use_hold;

  riscv::xlen_t operand_a_d, operand_a_q, operand_a;
  riscv::xlen_t operand_b_d, operand_b_q, operand_b;
  fu_op         operator_d,  operator_q,  operator, operator_delay;

  assign operand_a_d = fu_data_i.operand_a;
  assign operand_b_d = fu_data_i.operand_b;
  assign operator_d  = fu_data_i.operator;
  assign pau_trans_id_o = trans_id_q;

  assign operand_a = use_hold ? operand_a_q : operand_a_d;
  assign operand_b = use_hold ? operand_b_q : operand_b_d;
  assign operator  = use_hold ? operator_q  : operator_d;

  // ── Arithmetic input routing ──────────────────────────────────────────────────
  logic [POSLEN-1:0] add_a, add_b, mul_a, mul_b, div_a, div_b;
  logic [POSLEN-1:0] mac_a, mac_b;

  always_comb begin
    add_a = '0; add_b = '0;
    mul_a = '0; mul_b = '0;
    div_a = '0; div_b = '0;
    mac_a = '0; mac_b = '0;

    unique case (operator)
      PADD: begin
        add_a = operand_a[POSLEN-1:0];
        add_b = operand_b[POSLEN-1:0];
      end
      PSUB: begin
        add_a = operand_a[POSLEN-1:0];
        add_b = ~operand_b[POSLEN-1:0] + {{(POSLEN-1){1'b0}}, 1'b1}; // 2's complement negation
      end
      PMUL: begin
        mul_a = operand_a[POSLEN-1:0];
        mul_b = operand_b[POSLEN-1:0];
      end
      PDIV: begin
        div_a = operand_a[POSLEN-1:0];
        div_b = operand_b[POSLEN-1:0];
      end
      QMADD: begin
        mac_a = operand_a[POSLEN-1:0];
        mac_b = operand_b[POSLEN-1:0];
      end
      QMSUB: begin
        // Negate operand_a to compute quire - a*b = quire + (-a)*b
        mac_a = ~operand_a[POSLEN-1:0] + {{(POSLEN-1){1'b0}}, 1'b1};
        mac_b = operand_b[POSLEN-1:0];
      end
      default: ;
    endcase
  end

  // ── Quire register ────────────────────────────────────────────────────────────
  logic [QUIRELEN-1:0] quire_q, quire_d, curr_quire;
  logic [QUIRELEN-1:0] mac_c, mac_r;

  if (QUIRE_PRESENT) begin : g_quire
    // quire_q is registered each cycle from quire_d, so it already holds the
    // result of the previous operation — no combinatorial forwarding needed.
    // (Forwarding quire_d into mac_c would create a combinatorial loop through
    // the purely-combinatorial PositMAC block.)
    assign curr_quire = quire_q;

    always_comb begin
      quire_d = quire_q;
      unique case (operator_delay)
        QCLR:        quire_d = '0;
        QNEG:        quire_d = ~quire_q + {{(QUIRELEN-1){1'b0}}, 1'b1};
        QMADD, QMSUB: quire_d = pau_ready_o ? mac_r : quire_q;
        default: ;
      endcase
    end

    assign mac_c = curr_quire;
  end else begin : g_noquire
    assign curr_quire = '0;
    assign mac_c      = '0;
    assign quire_d    = '0;
  end

  // ── FloPoCo arithmetic unit instantiation ─────────────────────────────────────
  logic [POSLEN-1:0] add_o, mul_o, div_o;

  if (POSLEN == 8) begin : g_fp8

    PositAdd2_8_2_F0_uid2 pau8_add_i (
      .X ( add_a ),
      .Y ( add_b ),
      .R ( add_o )
    );

    if (!POS_LOG_MULT) begin : g_mul_exact
      PositMult_8_2_F0_uid2 pau8_mul_i (
        .X ( mul_a ),
        .Y ( mul_b ),
        .R ( mul_o )
      );
    end else begin : g_mul_approx
      PositLAM_8_2_F0_uid2 pau8_lam_i (
        .X ( mul_a ),
        .Y ( mul_b ),
        .R ( mul_o )
      );
    end

    PositDiv8 pau8_div_i (
      .X ( div_a ),
      .Y ( div_b ),
      .R ( div_o )
    );

    if (QUIRE_PRESENT) begin : g_mac8
      PositMAC8 pau8_mac_i (
        .A ( mac_a ),
        .B ( mac_b ),
        .C ( mac_c ),
        .R ( mac_r )
      );
    end else begin : g_nomac8
      assign mac_r = '0;
    end

  end else begin : g_fp16  // POSLEN == 16

    PositAdd2_16_2_F0_uid2 pau16_add_i (
      .X ( add_a ),
      .Y ( add_b ),
      .R ( add_o )
    );

    if (!POS_LOG_MULT) begin : g_mul_exact
      PositMult_16_2_F0_uid2 pau16_mul_i (
        .X ( mul_a ),
        .Y ( mul_b ),
        .R ( mul_o )
      );
    end else begin : g_mul_approx
      PositLAM_16_2_F0_uid2 pau16_lam_i (
        .X ( mul_a ),
        .Y ( mul_b ),
        .R ( mul_o )
      );
    end

    PositDiv16 pau16_div_i (
      .X ( div_a ),
      .Y ( div_b ),
      .R ( div_o )
    );

    if (QUIRE_PRESENT) begin : g_mac16
      PositMAC16 pau16_mac_i (
        .A ( mac_a ),
        .B ( mac_b ),
        .C ( mac_c ),
        .R ( mac_r )
      );
    end else begin : g_nomac16
      assign mac_r = '0;
    end

  end

  // ── Quire-to-Posit readout ────────────────────────────────────────────────────
  // Declared at module scope so result_mux can reference it regardless of QUIRE_PRESENT.
  logic [POSLEN-1:0]  q2p_in_posit;
  logic [QUIRELEN-1:0] q2p_quire;

  always_comb begin
    q2p_quire = '0;
    if (QUIRE_PRESENT) begin
      unique case (operator_delay)
        QROUND: q2p_quire = quire_q;
        default: ;
      endcase
    end
  end

  if (QUIRE_PRESENT) begin : g_q2p
    quire2posit_sm #(.POSLEN(POSLEN)) q2p_inst (
      .quire_i  ( q2p_quire   ),
      .posit_o  ( q2p_in_posit )
    );
  end else begin : g_noq2p
    assign q2p_in_posit = NAR;
  end

  // ── Result mux ───────────────────────────────────────────────────────────────
  always_comb begin
    result_o = '0;
    unique case (operator_delay)
      PADD, PSUB: result_o = {{(riscv::XLEN-POSLEN){1'b0}}, add_o};
      PMUL:       result_o = {{(riscv::XLEN-POSLEN){1'b0}}, mul_o};
      PDIV:       result_o = {{(riscv::XLEN-POSLEN){1'b0}}, div_o};
      PSQRT:      result_o = {{(riscv::XLEN-POSLEN){1'b0}}, NAR};
      QROUND:     result_o = {{(riscv::XLEN-POSLEN){1'b0}}, q2p_in_posit};
      // QMADD/QMSUB/QCLR/QNEG: quire-only, no scalar result
      default: ;
    endcase
  end

  // ── Latency FSM (all ops = 1 cycle, same structure as pau_top.sv) ─────────────
  always_comb begin
    pau_ready_o  = 1'b0;
    hold_inputs  = 1'b0;
    use_hold     = 1'b0;
    pau_valid_d  = 1'b0;
    state_d      = state_q;
    trans_id_d   = trans_id_q;

    unique case (state_q)
      READY: begin
        pau_ready_o = 1'b1;
        trans_id_d  = fu_data_i.trans_id;
        if (pau_valid_i) begin
          // All ops take exactly 1 cycle
          if (latency_d > 0) begin
            pau_ready_o = 1'b0;
            hold_inputs = 1'b1;
            state_d     = STALL;
          end else begin
            pau_valid_d = 1'b1;
          end
        end
      end
      STALL: begin
        use_hold = 1'b1;
        if (count == latency_q) begin
          pau_ready_o = 1'b1;
          pau_valid_d = 1'b1;
          state_d     = READY;
        end
      end
      default: ;
    endcase
  end

  // All ops complete in 1 cycle
  always_comb begin
    unique case (operator)
      PADD, PSUB, PMUL, PDIV, PSQRT,
      QMADD, QMSUB, QCLR, QNEG, QROUND: latency_d = 4'b0001;
      default:                            latency_d = 4'b0000;
    endcase
  end

  // ── Registers ─────────────────────────────────────────────────────────────────
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q        <= READY;
      operand_a_q    <= '0;
      operand_b_q    <= '0;
      latency_q      <= '0;
      trans_id_q     <= '0;
      pau_valid_o    <= '0;
      operator_delay <= PADD;
      if (QUIRE_PRESENT)
        quire_q      <= '0;
    end else begin
      state_q        <= state_d;
      latency_q      <= latency_d;
      trans_id_q     <= trans_id_d;
      pau_valid_o    <= pau_valid_d;
      operator_delay <= operator;
      if (QUIRE_PRESENT)
        quire_q      <= quire_d;
      if (hold_inputs) begin
        operand_a_q  <= operand_a_d;
        operand_b_q  <= operand_b_d;
        operator_q   <= operator_d;
      end
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni || state_d == READY)
      count <= '0;
    else
      count <= count + 1;
  end

endmodule
