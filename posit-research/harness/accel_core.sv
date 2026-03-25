// PERCIVAL Accelerator — core: instruction BRAM + data BRAM + sequencer + arith_unit.
//
// Instruction format (64-bit fixed-width):
//   [63:56] opcode       8 bits
//   [55:44] addr_a      12 bits
//   [43:32] addr_b      12 bits
//   [31:20] addr_result 12 bits
//   [19: 8] (reserved)  12 bits
//   [ 7: 0] flags        8 bits
//
// Sequencer pipeline:
//   FETCH   → DECODE   → EXEC   → WAIT_ARITH   → WRITEBACK → FETCH ...
//   (1 cy)    (1 cy)    (1 cy)    (N cy, stall)   (1 cy)

module accel_core
  import config_pkg::*;
  import opcodes_pkg::*;
(
  input  logic clk_i,
  input  logic rst_ni,

  // ── Control ──────────────────────────────────────────────────────────────────
  input  logic start_i,
  output logic done_o,
  output logic running_o,

  // ── Instruction BRAM host port (port A, only accessible when stopped) ────────
  input  logic [$clog2(INSTR_DEPTH)-1:0] ibram_addr_i,
  input  logic [63:0]                    ibram_wdata_i,
  input  logic                           ibram_we_i,
  output logic [63:0]                    ibram_rdata_o,

  // ── Data BRAM host port (port A, only accessible when stopped) ───────────────
  input  logic [$clog2(DATA_DEPTH)-1:0]  dbram_addr_i,
  input  logic [DATA_WIDTH-1:0]          dbram_wdata_i,
  input  logic                           dbram_we_i,
  output logic [DATA_WIDTH-1:0]          dbram_rdata_o
);

  // ── BRAMs (Vivado inferred from synchronous array + registered read) ──────────
  logic [63:0]         instr_mem [0:INSTR_DEPTH-1];
  logic [DATA_WIDTH-1:0] data_mem [0:DATA_DEPTH-1];

  // BRAM address and control signals
  logic [$clog2(INSTR_DEPTH)-1:0] ibram_portb_addr;   // sequencer fetch port
  logic [63:0]                    ibram_portb_rdata;   // registered output

  logic [$clog2(DATA_DEPTH)-1:0]  dbram_porta_addr;   // sequencer operand_a / host
  logic [DATA_WIDTH-1:0]          dbram_porta_wdata;
  logic                           dbram_porta_we;
  logic [DATA_WIDTH-1:0]          dbram_porta_rdata;

  logic [$clog2(DATA_DEPTH)-1:0]  dbram_portb_addr;   // sequencer operand_b
  logic [DATA_WIDTH-1:0]          dbram_portb_rdata;

  // Instruction BRAM — port A (host write), port B (sequencer read)
  always_ff @(posedge clk_i) begin
    if (ibram_we_i && !running_o)
      instr_mem[ibram_addr_i] <= ibram_wdata_i;
    ibram_rdata_o    <= instr_mem[ibram_addr_i];    // host read
    ibram_portb_rdata <= instr_mem[ibram_portb_addr]; // sequencer fetch (registered)
  end

  // Data BRAM — true dual-port
  // Port A: host r/w (when stopped) OR sequencer addr_a read + result write (when running)
  always_ff @(posedge clk_i) begin
    if (dbram_porta_we)
      data_mem[dbram_porta_addr] <= dbram_porta_wdata;
    dbram_porta_rdata <= data_mem[dbram_porta_addr];
  end

  // Port B: sequencer operand_b read (when running) OR host read (when stopped)
  always_ff @(posedge clk_i) begin
    dbram_portb_rdata <= data_mem[dbram_portb_addr];
  end

  // Host data BRAM read: returned from port A when stopped
  assign dbram_rdata_o = dbram_porta_rdata;

  // ── Sequencer state machine ───────────────────────────────────────────────────
  typedef enum logic [2:0] {
    IDLE_S, FETCH, DECODE, EXEC, WAIT_ARITH, WRITEBACK, HALT_S
  } seq_state_t;

  seq_state_t seq_state_q, seq_state_d;

  logic [$clog2(INSTR_DEPTH)-1:0] pc_q, pc_d;

  // Decoded instruction fields (latched at DECODE→EXEC)
  opcode_t                       exec_opcode_q;
  logic [11:0]                   exec_addr_a_q, exec_addr_b_q, exec_addr_result_q;

  // Arith unit interface
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

  // Registered operands captured from data BRAM in EXEC state
  logic [DATA_WIDTH-1:0] op_a_reg, op_b_reg;

  // ── Needs-writeback helper ────────────────────────────────────────────────────
  function automatic logic needs_wb(opcode_t op);
    case (op)
      OP_ADD, OP_SUB, OP_MUL, OP_DIV, OP_SQRT,
      OP_NEG, OP_ABS, OP_MOV, OP_QACC_READ: return 1'b1;
      default: return 1'b0;
    endcase
  endfunction

  // ── Sequencer combinatorial logic ─────────────────────────────────────────────
  always_comb begin
    seq_state_d    = seq_state_q;
    pc_d           = pc_q;
    arith_valid_i  = 1'b0;
    arith_opcode   = exec_opcode_q;
    arith_op_a     = op_a_reg;
    arith_op_b     = op_b_reg;

    // BRAM port defaults (host access when not running)
    ibram_portb_addr = '0;
    dbram_porta_addr  = dbram_addr_i;
    dbram_porta_wdata = dbram_wdata_i;
    dbram_porta_we    = dbram_we_i && !running_o;
    dbram_portb_addr  = '0;  // unused by host (reads use port A)

    unique case (seq_state_q)

      IDLE_S: begin
        if (start_i) begin
          pc_d       = '0;
          seq_state_d = FETCH;
        end
      end

      FETCH: begin
        ibram_portb_addr = pc_q;
        pc_d             = pc_q + 1;
        seq_state_d       = DECODE;
      end

      DECODE: begin
        // ibram_portb_rdata now has the instruction (registered from FETCH)
        // Present operand addresses to data BRAM; they'll be registered in EXEC
        dbram_porta_addr = ibram_portb_rdata[55:44];   // addr_a
        dbram_portb_addr = ibram_portb_rdata[43:32];   // addr_b

        if (ibram_portb_rdata[63:56] == OP_HALT)
          seq_state_d = HALT_S;
        else
          seq_state_d = EXEC;
      end

      EXEC: begin
        // Operands are now available in dbram_porta_rdata / dbram_portb_rdata
        // (latched into op_a_reg, op_b_reg by always_ff below)
        // Submit to arith_unit
        arith_valid_i = 1'b1;
        arith_op_a    = dbram_porta_rdata;
        arith_op_b    = dbram_portb_rdata;
        arith_opcode  = exec_opcode_q;
        seq_state_d    = WAIT_ARITH;
      end

      WAIT_ARITH: begin
        if (arith_valid_o)
          seq_state_d = WRITEBACK;
      end

      WRITEBACK: begin
        if (needs_wb(exec_opcode_q)) begin
          dbram_porta_addr  = exec_addr_result_q;
          dbram_porta_wdata = arith_result;
          dbram_porta_we    = 1'b1;
        end
        seq_state_d = FETCH;
      end

      HALT_S: begin
        // Stay here until reset or next start_i
        if (start_i) begin
          pc_d       = '0;
          seq_state_d = FETCH;
        end
      end

      default: seq_state_d = IDLE_S;
    endcase
  end

  assign running_o = (seq_state_q != IDLE_S) && (seq_state_q != HALT_S);
  assign done_o    = (seq_state_q == HALT_S);

  // ── Sequencer registers ───────────────────────────────────────────────────────
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      seq_state_q      <= IDLE_S;
      pc_q             <= '0;
      exec_opcode_q    <= OP_HALT;
      exec_addr_a_q    <= '0;
      exec_addr_b_q    <= '0;
      exec_addr_result_q <= '0;
      op_a_reg         <= '0;
      op_b_reg         <= '0;
    end else begin
      seq_state_q <= seq_state_d;
      pc_q        <= pc_d;

      // Latch decoded fields at end of DECODE (registered BRAM output is ready)
      if (seq_state_q == DECODE && ibram_portb_rdata[63:56] != OP_HALT) begin
        exec_opcode_q     <= ibram_portb_rdata[63:56];
        exec_addr_a_q     <= ibram_portb_rdata[55:44];
        exec_addr_b_q     <= ibram_portb_rdata[43:32];
        exec_addr_result_q <= ibram_portb_rdata[31:20];
      end

      // Latch operands from data BRAM at end of EXEC
      if (seq_state_q == EXEC) begin
        op_a_reg <= dbram_porta_rdata;
        op_b_reg <= dbram_portb_rdata;
      end
    end
  end

endmodule
