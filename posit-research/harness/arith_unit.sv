// PERCIVAL Accelerator — arithmetic unit wrapper.
// Instantiates either pau_top (PAU) or fpu_wrap (FPU) based on config_pkg::ACCEL_TYPE.
// Presents a uniform (operand_a, operand_b, opcode, valid_i) → (result, valid_o, ready_o)
// interface to accel_core. Translates accelerator opcodes to the native arithmetic unit ops.
//
// QACC state for FPU mode:                acc_q register here; uses FMA unit.
// QACC state for PAU mode, QUIRE_ENABLE=1: inside pau_top (internal quire register).
// QACC state for PAU mode, QUIRE_ENABLE=0: acc_q register here; uses PMUL + PADD/PSUB.
//   QACC_MADD / QACC_MSUB are two-pass: first PMUL, then PADD/PSUB via MAC_STEP → WAIT2.

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
  input  logic                    valid_i,    // 1-cycle pulse: sequencer submits operation
  output logic [DATA_WIDTH-1:0]   result_o,
  output logic                    valid_o,    // 1-cycle pulse: result ready
  output logic                    ready_o     // high when idle and accepting new operations
);

  // Posit 1.0 encoding: 0_1_00...0 = 1 << (DATA_WIDTH-2)
  // Used for QACC_ADD (PAU mode, QUIRE_ENABLE=1): QACC_ADD(a) = QMADD(a, 1.0)
  localparam logic [DATA_WIDTH-1:0] POSIT_ONE = DATA_WIDTH'(1) << (DATA_WIDTH-2);

  // ── State machine ────────────────────────────────────────────────────────────
  // MAC_STEP: issues the second PAU op (PADD/PSUB) for no-quire QACC_MADD/MSUB
  // WAIT2:    waits for the second PAU op result
  typedef enum logic [2:0] { IDLE, WAIT, MAC_STEP, WAIT2, DONE } state_t;
  state_t state_q, state_d;

  // ── Registered operands and opcode (latched when accepted in IDLE) ───────────
  opcode_t                opcode_q;
  logic [DATA_WIDTH-1:0]  op_a_q, op_b_q;

  // ── Result and accumulator registers ─────────────────────────────────────────
  logic [DATA_WIDTH-1:0]  result_q,    result_d;
  logic [DATA_WIDTH-1:0]  acc_q,       acc_d;       // unified accumulator (FPU or PAU no-quire)
  logic [DATA_WIDTH-1:0]  mul_result_q, mul_result_d; // temp: PMUL result in 2-pass MAC

  // ── PAU interface ─────────────────────────────────────────────────────────────
  fu_data_t         pau_fu_data;
  logic             pau_valid_i_sig;
  logic             pau_ready_o_sig;
  logic             pau_valid_o_sig;
  riscv::xlen_t     pau_result_sig;

  // ── FPU interface ─────────────────────────────────────────────────────────────
  fu_data_t         fpu_fu_data;
  logic             fpu_valid_i_sig;
  logic             fpu_ready_o_sig;
  logic             fpu_valid_o_sig;
  logic [FLEN-1:0]  fpu_result_sig;

  // ── Arithmetic unit instantiation (only one branch synthesised) ──────────────
  // posit(8,2) and posit(16,2) use FloPoCo Flo-Posit cores (flo_posit_top).
  // posit(32,2) and posit(64,2) use PERCIVAL cores (pau_top).
  if (ACCEL_TYPE == "PAU" && (DATA_WIDTH == 8 || DATA_WIDTH == 16)) begin : g_flopau

    flo_posit_top flopau_inst (
      .clk_i,
      .rst_ni,
      .fu_data_i      ( pau_fu_data    ),
      .pau_valid_i    ( pau_valid_i_sig ),
      .pau_ready_o    ( pau_ready_o_sig ),
      .pau_trans_id_o (                ),
      .pau_valid_o    ( pau_valid_o_sig ),
      .result_o       ( pau_result_sig  )
    );

    assign fpu_ready_o_sig = 1'b0;
    assign fpu_valid_o_sig = 1'b0;
    assign fpu_result_sig  = '0;

  end else if (ACCEL_TYPE == "PAU") begin : g_pau

    pau_top pau_inst (
      .clk_i,
      .rst_ni,
      .fu_data_i      ( pau_fu_data    ),
      .pau_valid_i    ( pau_valid_i_sig ),
      .pau_ready_o    ( pau_ready_o_sig ),
      .pau_trans_id_o (                ),
      .pau_valid_o    ( pau_valid_o_sig ),
      .result_o       ( pau_result_sig  )
    );

    assign fpu_ready_o_sig = 1'b0;
    assign fpu_valid_o_sig = 1'b0;
    assign fpu_result_sig  = '0;

  end else begin : g_fpu

    fpu_wrap fpu_inst (
      .clk_i,
      .rst_ni,
      .flush_i          ( 1'b0             ),
      .fpu_valid_i      ( fpu_valid_i_sig   ),
      .fpu_ready_o      ( fpu_ready_o_sig   ),
      .fu_data_i        ( fpu_fu_data       ),
      .fpu_fmt_i        ( DATA_WIDTH == 64 ? 2'b01 : 2'b00 ),  // FP64 or FP32
      .fpu_rm_i         ( 3'b000            ),  // round-nearest-even
      .fpu_frm_i        ( 3'b000            ),
      .fpu_prec_i       ( 7'b0              ),
      .fpu_trans_id_o   (                   ),
      .result_o         ( fpu_result_sig    ),
      .fpu_valid_o      ( fpu_valid_o_sig   ),
      .fpu_exception_o  (                   )
    );

    assign pau_ready_o_sig = 1'b0;
    assign pau_valid_o_sig = 1'b0;
    assign pau_result_sig  = '0;

  end

  // ── Active arithmetic unit signals ───────────────────────────────────────────
  logic             arith_valid_o;
  logic [DATA_WIDTH-1:0] arith_result;

  assign arith_valid_o = (ACCEL_TYPE == "PAU") ? pau_valid_o_sig : fpu_valid_o_sig;
  assign arith_result  = (ACCEL_TYPE == "PAU")
                         ? pau_result_sig[DATA_WIDTH-1:0]
                         : fpu_result_sig[DATA_WIDTH-1:0];

  // ── Combinatorial opcode classification ──────────────────────────────────────
  // is_comb_op: result available without calling the arithmetic unit
  logic is_comb_op;
  always_comb begin
    is_comb_op = 1'b0;
    case (opcode_i)
      OP_NEG, OP_ABS, OP_MOV, OP_RELU: is_comb_op = 1'b1;
      // QACC state updates without arithmetic:
      //   FPU: always handled here (no hw needed for clear/negate/read)
      //   PAU + QUIRE_ENABLE=0: handled here (posit neg = 2's complement, read acc directly)
      //   PAU + QUIRE_ENABLE=1: routed to quire in pau_top (QCLR/QNEG/QROUND), not here
      OP_QACC_CLEAR, OP_QACC_NEG, OP_QACC_READ:
        if (ACCEL_TYPE == "FPU" || (ACCEL_TYPE == "PAU" && !QUIRE_ENABLE))
          is_comb_op = 1'b1;
      default: ;
    endcase
  end

  // Combinatorial result (valid in IDLE when valid_i and is_comb_op are asserted)
  logic [DATA_WIDTH-1:0] comb_result;
  always_comb begin
    comb_result = '0;
    if (ACCEL_TYPE == "PAU") begin
      case (opcode_i)
        OP_NEG:       comb_result = ~operand_a_i + DATA_WIDTH'(1);  // 2's complement
        OP_ABS:       comb_result = operand_a_i[DATA_WIDTH-1]
                                    ? (~operand_a_i + DATA_WIDTH'(1))
                                    : operand_a_i;
        OP_MOV:       comb_result = operand_a_i;
        OP_RELU:      comb_result = operand_a_i[DATA_WIDTH-1] ? '0 : operand_a_i;
        // No-quire accumulator read (QUIRE_ENABLE=0; is_comb_op guard prevents reaching here otherwise)
        OP_QACC_READ: if (!QUIRE_ENABLE) comb_result = acc_q;
        default: ;
      endcase
    end else begin  // FPU
      case (opcode_i)
        OP_NEG:        comb_result = (operand_a_i == '0)
                                   ? '0
                                   : {~operand_a_i[DATA_WIDTH-1], operand_a_i[DATA_WIDTH-2:0]};
        OP_ABS:        comb_result = {1'b0, operand_a_i[DATA_WIDTH-2:0]};
        OP_MOV:        comb_result = operand_a_i;
        OP_RELU:       comb_result = operand_a_i[DATA_WIDTH-1] ? '0 : operand_a_i;
        OP_QACC_CLEAR: comb_result = '0;    // not written back
        OP_QACC_NEG:   comb_result = '0;    // not written back
        OP_QACC_READ:  comb_result = acc_q;
        default: ;
      endcase
    end
  end

  // ── PAU fu_data_t construction ────────────────────────────────────────────────
  // When state_q == MAC_STEP: override operands/op for the second pass of 2-pass MAC.
  // Otherwise use un-registered inputs: pau_top samples fu_data in the same cycle
  // pau_valid_i is asserted (first cycle of IDLE→WAIT transition).
  logic [DATA_WIDTH-1:0] pau_op_a, pau_op_b;
  fu_op                  pau_fu_op;

  always_comb begin
    pau_op_a  = operand_a_i;  // un-registered current inputs (default)
    pau_op_b  = operand_b_i;
    pau_fu_op = PADD;         // safe default

    if (state_q == MAC_STEP) begin
      // Second pass of QACC_MADD or QACC_MSUB (QUIRE_ENABLE=0).
      // mul_result_q holds the product from the first pass.
      if (opcode_q == OP_QACC_MSUB) begin
        pau_fu_op = PSUB;          // acc - product
        pau_op_a  = acc_q;
        pau_op_b  = mul_result_q;
      end else begin               // OP_QACC_MADD
        pau_fu_op = PADD;          // acc + product
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
          if (!QUIRE_ENABLE) begin
            // No-quire: PADD(a, acc) → result = a + acc
            pau_fu_op = PADD;
            pau_op_a  = operand_a_i;
            pau_op_b  = acc_q;
          end else begin
            // Exact quire: QMADD(a, 1.0) → quire += a × 1.0 = a
            pau_fu_op = QMADD;
            pau_op_b  = POSIT_ONE;
          end
        end
        OP_QACC_MADD:  pau_fu_op = QUIRE_ENABLE ? QMADD  : PMUL;  // no-quire: 1st pass = multiply
        OP_QACC_MSUB:  pau_fu_op = QUIRE_ENABLE ? QMSUB  : PMUL;  // no-quire: 1st pass = multiply
        OP_QACC_CLEAR: pau_fu_op = QCLR;    // only reached when QUIRE_ENABLE=1
        OP_QACC_NEG:   pau_fu_op = QNEG;    // only reached when QUIRE_ENABLE=1
        OP_QACC_READ:  pau_fu_op = QROUND;  // only reached when QUIRE_ENABLE=1
        default: ;
      endcase
    end
  end

  always_comb begin
    pau_fu_data           = '0;
    pau_fu_data.fu        = PAU;
    // Drive PADD (neutral) when not actively issuing to PAU.
    // This ensures operator_delay returns to a quire-neutral value between
    // operations, preventing stale PositMAC output from corrupting the quire.
    pau_fu_data.operator  = pau_valid_i_sig ? pau_fu_op : PADD;
    pau_fu_data.operand_a = {{riscv::XLEN-DATA_WIDTH{1'b0}}, pau_op_a};
    pau_fu_data.operand_b = {{riscv::XLEN-DATA_WIDTH{1'b0}}, pau_op_b};
  end

  // ── FPU fu_data_t construction ────────────────────────────────────────────────
  // Use un-registered inputs: fpu_wrap samples in the same cycle fpu_valid_i is asserted.
  // NaN-boxing: 32-bit floats stored in 64-bit containers need upper 32 bits = 0xFFFFFFFF.
  logic [FLEN-1:0] fpu_box_a, fpu_box_b, fpu_box_acc;
  if (DATA_WIDTH == 32) begin : g_nanbox
    assign fpu_box_a   = {{32{1'b1}}, operand_a_i};  // un-registered
    assign fpu_box_b   = {{32{1'b1}}, operand_b_i};
    assign fpu_box_acc = {{32{1'b1}}, acc_q};         // accumulator is always registered
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
    fpu_fu_data.imm       = fpu_box_b;  // default: second operand in C

    case (opcode_i)  // un-registered opcode
      OP_ADD: begin
        // fpnew FADD computes B + C (A is forced to 1.0 internally by the FMA unit).
        // Set B=a, C=b so the result is a + b.
        fpu_fu_op             = FADD;
        fpu_fu_data.operand_b = fpu_box_a;
        fpu_fu_data.imm       = fpu_box_b;
      end
      OP_SUB: begin
        // fpnew FSUB computes B - C.  Set B=a, C=b so the result is a - b.
        fpu_fu_op             = FSUB;
        fpu_fu_data.operand_b = fpu_box_a;
        fpu_fu_data.imm       = fpu_box_b;
      end
      OP_MUL:  fpu_fu_op = FMUL;
      OP_DIV:  fpu_fu_op = FDIV;
      OP_SQRT: fpu_fu_op = FSQRT;
      OP_QACC_ADD: begin                // acc + a = FADD(acc, a)
        fpu_fu_op             = FADD;
        fpu_fu_data.operand_b = fpu_box_acc;  // fpnew FADD: B+C → acc+a
        fpu_fu_data.imm       = fpu_box_a;
      end
      OP_QACC_MADD: begin               // acc + a*b = FMADD(a, b, acc)
        fpu_fu_op       = FMADD;
        fpu_fu_data.imm = fpu_box_acc;
      end
      OP_QACC_MSUB: begin               // acc - a*b = -(a*b) + acc = FNMSUB(a,b,acc)
        fpu_fu_op       = FNMSUB;
        fpu_fu_data.imm = fpu_box_acc;
      end
      default: ;
    endcase
    fpu_fu_data.operator = fpu_fu_op;
  end

  // ── State machine logic ───────────────────────────────────────────────────────
  always_comb begin
    state_d         = state_q;
    result_d        = result_q;
    acc_d           = acc_q;
    mul_result_d    = mul_result_q;
    ready_o         = 1'b0;
    valid_o         = 1'b0;
    pau_valid_i_sig = 1'b0;
    fpu_valid_i_sig = 1'b0;

    unique case (state_q)

      IDLE: begin
        ready_o = 1'b1;
        if (valid_i) begin
          if (is_comb_op) begin
            // Zero-latency: result and valid_o available combinatorially this cycle.
            // Stay in IDLE (no DONE detour). Accumulator updated at clock edge.
            result_d = comb_result;
            valid_o  = 1'b1;
            if (opcode_i == OP_QACC_CLEAR)
              acc_d = '0;
            if (opcode_i == OP_QACC_NEG)
              acc_d = (ACCEL_TYPE == "PAU")
                      ? (~acc_q + DATA_WIDTH'(1))
                      : (acc_q == '0 ? '0
                                     : {~acc_q[DATA_WIDTH-1], acc_q[DATA_WIDTH-2:0]});
            // state stays IDLE
          end else begin
            // Submit to arithmetic unit (1-cycle pulse)
            if (ACCEL_TYPE == "PAU") pau_valid_i_sig = 1'b1;
            else                     fpu_valid_i_sig = 1'b1;
            state_d = WAIT;
          end
        end
      end

      WAIT: begin
        if (arith_valid_o) begin
          result_d = arith_result;
          // No-quire PAU 2-pass MAC: first pass (PMUL) done → issue PADD/PSUB
          if (ACCEL_TYPE == "PAU" && !QUIRE_ENABLE &&
              opcode_q inside {OP_QACC_MADD, OP_QACC_MSUB}) begin
            mul_result_d = arith_result;
            state_d = MAC_STEP;
          end else begin
            // Update accumulator for QACC arithmetic ops (FPU or PAU no-quire)
            if (opcode_q inside {OP_QACC_ADD, OP_QACC_MADD, OP_QACC_MSUB})
              acc_d = arith_result;
            state_d = DONE;
          end
        end
      end

      MAC_STEP: begin
        // Issue second PAU operation: PADD(product, acc) or PSUB(acc, product).
        // PAU just completed the PMUL and is ready to accept a new operation.
        // pau_fu_data is driven from state_q == MAC_STEP branch above.
        pau_valid_i_sig = 1'b1;
        state_d = WAIT2;
      end

      WAIT2: begin
        // Waiting for the second PAU op (PADD/PSUB) result.
        if (arith_valid_o) begin
          acc_d = arith_result;
          result_d  = arith_result;
          state_d   = DONE;
        end
      end

      DONE: begin
        valid_o = 1'b1;
        state_d = IDLE;
      end

      default: state_d = IDLE;
    endcase
  end

  // Bypass: comb_ops produce result_o combinatorially (zero-latency);
  // registered result_q used for all other ops.
  assign result_o = (state_q == IDLE && valid_i && is_comb_op)
                    ? comb_result : result_q;

  // ── Registers ─────────────────────────────────────────────────────────────────
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q      <= IDLE;
      opcode_q     <= OP_HALT;
      op_a_q       <= '0;
      op_b_q       <= '0;
      result_q     <= '0;
      acc_q        <= '0;
      mul_result_q <= '0;
    end else begin
      state_q      <= state_d;
      result_q     <= result_d;
      acc_q        <= acc_d;
      mul_result_q <= mul_result_d;
      // Latch operands when accepted
      if (state_q == IDLE && valid_i) begin
        opcode_q <= opcode_i;
        op_a_q   <= operand_a_i;
        op_b_q   <= operand_b_i;
      end
    end
  end

endmodule
