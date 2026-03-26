// PERCIVAL Accelerator — unified opcode set.
// Identical opcodes used for both PAU and FPU modes.
// arith_unit.sv translates these to the underlying arithmetic unit's native ops.

package opcodes_pkg;

  typedef logic [7:0] opcode_t;

  // Basic arithmetic (two operands, write to addr_result)
  localparam opcode_t OP_HALT  = 8'h00;  // stop execution
  localparam opcode_t OP_ADD   = 8'h01;  // result = a + b
  localparam opcode_t OP_SUB   = 8'h02;  // result = a - b
  localparam opcode_t OP_MUL   = 8'h03;  // result = a * b
  localparam opcode_t OP_DIV   = 8'h04;  // result = a / b
  localparam opcode_t OP_SQRT  = 8'h05;  // result = sqrt(a)  (addr_b unused)
  localparam opcode_t OP_NEG   = 8'h06;  // result = -a       (addr_b unused)
  localparam opcode_t OP_ABS   = 8'h07;  // result = |a|      (addr_b unused)
  localparam opcode_t OP_MOV   = 8'h08;  // result = a        (addr_b unused)
  localparam opcode_t OP_RELU  = 8'h09;  // result = max(0,a) (addr_b unused)

  // Quire / accumulator operations (no writeback to data BRAM except QACC_READ)
  // PAU: exact quire accumulator (16*DATA_WIDTH bits)
  // FPU: single DATA_WIDTH-bit accumulator register (less precise)
  localparam opcode_t OP_QACC_CLEAR = 8'h10;  // quire/acc = 0           (all addrs unused)
  localparam opcode_t OP_QACC_ADD   = 8'h11;  // quire/acc += a          (addr_b unused)
  localparam opcode_t OP_QACC_MADD  = 8'h12;  // quire/acc += a * b
  localparam opcode_t OP_QACC_MSUB  = 8'h13;  // quire/acc -= a * b
  localparam opcode_t OP_QACC_NEG   = 8'h14;  // quire/acc = -quire/acc  (all addrs unused)
  localparam opcode_t OP_QACC_READ  = 8'h15;  // result = round(quire/acc) → addr_result

  // FMA equivalent (same program for both PAU and FPU):
  //   QACC_CLEAR
  //   QACC_ADD   addr_c        ; acc = c
  //   QACC_MADD  addr_a, addr_b ; acc = c + a*b
  //   QACC_READ  addr_result

endpackage
