#ifdef __riscv_xposit
#if __riscv_xlen != 64
#error "libpawn only works for 64 bit Xposit"
#endif // __riscv_xlen

#else // __riscv_xposit

#endif // __riscv_xposit
