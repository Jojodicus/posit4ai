
package riscv;
    localparam XLEN = cva6_config_pkg::CVA6ConfigXlen;
    localparam FPU_EN = cva6_config_pkg::CVA6ConfigFpuEn;
    localparam PAU_EN = cva6_config_pkg::CVA6ConfigPauEn;
    localparam VLEN = 64;
    localparam PLEN = 56;
    localparam bit IS_XLEN64 = (XLEN == 64);
    localparam bit IS_XLEN32 = (XLEN == 32);

    typedef logic [XLEN-1:0] xlen_t;
endpackage
