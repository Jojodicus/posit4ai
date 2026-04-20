# LibPawn

usage idea:

`Target` class, subclasses:
- `Pawn` - FPGA accelerator - give config during object creation
- `Xposit` - For Spike simulator
- `Soft` - Universal, native floats - give type and bit width

`Target` defines some arithmetic:
- add, sub, mul, div
- fma?
- neg, abs
- sqrt
- relu

for Pawn: option to queue up operations, build a kernel, save to disk
