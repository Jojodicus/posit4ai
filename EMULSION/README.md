# EMULSION

EMULSION (**EMUL**ator for **S**anity-checking **I**f it works **O**n **N**eural-nets) is a host-side software emulator for the PAWN userspace driver API.
It exposes the same C interface as `PAWN/sw/pawn.h`, but executes PAWN programs
with stillwater/universal posit arithmetic instead of FPGA hardware.

This build provides fixed-width libraries:

- `libemulsion8.a`
- `libemulsion16.a`
- `libemulsion32.a`

64-bit posit/DBRAM API calls are unsupported for now and hard-fail.

## Build

```bash
make
```

## Example outputs

- `*.emu8.elf`
- `*.emu16.elf`
- `*.emu32.elf`

## Linking your own program

Compile your C program that includes `PAWN/sw/pawn.h` and link with one of:

- `EMULSION/libemulsion8.a`
- `EMULSION/libemulsion16.a`
- `EMULSION/libemulsion32.a`

plus `-lstdc++ -lm`.
