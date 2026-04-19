// Identical opcodes used for both PAU and FPU modes.
// arith_unit.sv translates these to the underlying arithmetic unit's native ops.

package opcodes_pkg;

  typedef logic [3:0] opcode_t;

  // Basic arithmetic (two operands, write to addr_result)
  localparam opcode_t OP_HALT  = 4'h0;  // stop execution
  localparam opcode_t OP_ADD   = 4'h1;  // result = a + b
  localparam opcode_t OP_SUB   = 4'h2;  // result = a - b
  localparam opcode_t OP_MUL   = 4'h3;  // result = a * b
  localparam opcode_t OP_DIV   = 4'h4;  // result = a / b
  localparam opcode_t OP_SQRT  = 4'h5;  // result = sqrt(a)  (addr_b unused)
  localparam opcode_t OP_NEG   = 4'h6;  // result = -a       (addr_b unused)
  localparam opcode_t OP_ABS   = 4'h7;  // result = |a|      (addr_b unused)
  localparam opcode_t OP_MOV   = 4'h8;  // result = a        (addr_b unused)
  localparam opcode_t OP_RELU  = 4'h9;  // result = max(0,a) (addr_b unused)

  // Quire / accumulator operations (no writeback to data BRAM except QACC_READ)
  localparam opcode_t OP_QACC_CLEAR = 4'hA;  // quire/acc = 0           (all addrs unused)
  localparam opcode_t OP_QACC_ADD   = 4'hB;  // quire/acc += a          (addr_b unused)
  localparam opcode_t OP_QACC_MADD  = 4'hC;  // quire/acc += a * b
  localparam opcode_t OP_QACC_MSUB  = 4'hD;  // quire/acc -= a * b
  localparam opcode_t OP_QACC_NEG   = 4'hE;  // quire/acc = -quire/acc  (all addrs unused)
  localparam opcode_t OP_QACC_READ  = 4'hF;  // result = round(quire/acc) -> addr_result

endpackage
