
package ariane_pkg;
    typedef struct packed {
         riscv::xlen_t       cause;
         riscv::xlen_t       tval;
         logic               valid;
    } exception_t;

    typedef enum logic [3:0] {
        NONE, LOAD, STORE, ALU, CTRL_FLOW, MULT, CSR, FPU, FPU_VEC, CVXIF, PAU
    } fu_t;

    typedef enum logic [7:0] {
        ADD, SUB, ADDW, SUBW, XORL, ORL, ANDL, SRA, SRL, SLL, SRLW, SLLW, SRAW,
        LTS, LTU, GES, GEU, EQ, NE, JALR, BRANCH, SLTS, SLTU,
        MRET, SRET, DRET, ECALL, WFI, FENCE, FENCE_I, SFENCE_VMA, CSR_WRITE, CSR_READ, CSR_SET, CSR_CLEAR,
        LD, SD, LW, LWU, SW, LH, LHU, SH, LB, SB, LBU,
        AMO_LRW, AMO_LRD, AMO_SCW, AMO_SCD, AMO_SWAPW, AMO_ADDW, AMO_ANDW, AMO_ORW, AMO_XORW, AMO_MAXW, AMO_MAXWU, AMO_MINW, AMO_MINWU,
        AMO_SWAPD, AMO_ADDD, AMO_ANDD, AMO_ORD, AMO_XORD, AMO_MAXD, AMO_MAXDU, AMO_MIND, AMO_MINDU,
        MUL, MULH, MULHU, MULHSU, MULW, DIV, DIVU, DIVW, DIVUW, REM, REMU, REMW, REMUW,
        FLD, FLW, FLH, FLB, FSD, FSW, FSH, FSB,
        FADD, FSUB, FMUL, FDIV, FMIN_MAX, FSQRT, FMADD, FMSUB, FNMSUB, FNMADD,
        FCVT_F2I, FCVT_I2F, FCVT_F2F, FSGNJ, FMV_F2X, FMV_X2F, FCMP, FCLASS,
        VFMIN, VFMAX, VFSGNJ, VFSGNJN, VFSGNJX, VFEQ, VFNE, VFLT, VFGE, VFLE, VFGT, VFCPKAB_S, VFCPKCD_S, VFCPKAB_D, VFCPKCD_D,
        OFFLOAD,
        PADD, PSUB, PMUL, PDIV, PSQRT, PMIN, PMAX,
        QMADD, QMSUB, QCLR, QNEG, QROUND,
        PCVT_P2I, PCVT_P2L, PCVT_P2U, PCVT_P2LU, PCVT_I2P, PCVT_L2P, PCVT_U2P, PCVT_LU2P, 
        PSGNJ, PSGNJN, PSGNJX, PMV_P2X, PMV_X2P, PEQ, PLT, PLE,
        PLD, PLW, QL, PSD, PSW, QS
    } fu_op;

    typedef struct packed {
        fu_t                      fu;
        fu_op                     operator;
        riscv::xlen_t             operand_a;
        riscv::xlen_t             operand_b;
        riscv::xlen_t             imm;
        logic [5:0]               trans_id; // Using 6 bits as a safe default for TRANS_ID_BITS
    } fu_data_t;

    localparam TRANS_ID_BITS = 6;
    localparam bit RVD = 1'b1;
    localparam bit RVF = 1'b1;
    localparam bit XF16 = 1'b0;
    localparam bit XF16ALT = 1'b0;
    localparam bit XF8 = 1'b0;
    localparam bit XFVEC = 1'b0;
    localparam int unsigned LAT_COMP_FP32 = 2;
    localparam int unsigned LAT_COMP_FP64 = 3;
    localparam int unsigned LAT_COMP_FP16 = 1;
    localparam int unsigned LAT_COMP_FP16ALT = 1;
    localparam int unsigned LAT_COMP_FP8 = 1;
    localparam int unsigned LAT_DIVSQRT = 2;
    localparam int unsigned LAT_NONCOMP = 1;
    localparam int unsigned LAT_CONV = 2;

    // Posit unit configuration via defines
    `ifdef POSLEN_64
        localparam int unsigned POSLEN = 64;
    `else
        localparam int unsigned POSLEN = 32;
    `endif

    localparam int unsigned QUIRELEN = 16 * POSLEN;

    `ifdef QUIRE_DISABLED
        localparam bit QUIRE_PRESENT = 1'b0;
    `else
        localparam bit QUIRE_PRESENT = 1'b1;
    `endif

    `ifdef POS_LOG_MULT
        localparam bit POS_LOG_MULT = 1'b1;
    `else
        localparam bit POS_LOG_MULT = 1'b0;
    `endif

    `ifdef POS_LOG_DIV
        localparam bit POS_LOG_DIV = 1'b1;
    `else
        localparam bit POS_LOG_DIV = 1'b0;
    `endif

    `ifdef POS_LOG_SQRT
        localparam bit POS_LOG_SQRT = 1'b1;
    `else
        localparam bit POS_LOG_SQRT = 1'b0;
    `endif

    localparam bit POS_PRESENT = 1'b1;
    localparam bit FP_PRESENT = 1'b1;
    localparam int unsigned FLEN = 64;

endpackage
