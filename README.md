# Posit4AI

Master's thesis "Hardware-Level Comparison of Posit and Float Arithmetic for AI Applications" at [i3@FAU](https://www.cs3.tf.fau.de/).

## Project overview

A lot of sub-parts depend on each other, consult the `README` files in the respective folders

- **PAWN**: the FPGA accelerator, including example programs
- **libpawn**: a software emulation framework for posits, has support for XPosit and Takums
- **resnet**: posit implementations of ResNet (and CifarNet) in posit, together with accuracy evaluation

## Usage and Development - Spike XPosit

This was tested on [CachyOS](https://cachyos.org/).
The steps should work with minimal (if any) adjustments on other Arch-based systems as well.
When using other distros, refer to the documentation of the specific programs.

Before starting, always source the env var script (works on POSIX-compatible shells like Bash/Zsh, as well as Fish):
```sh
. preparepath.sh
```

### Compiling ELFs

1. Install requirements (should already be installed on a typical installation):
```sh
paru -S base-devel cmake # or pacman, yay, pamac, ...
```
2. Install [RISC-V GNU Compiler Toolchain](https://github.com/riscv-collab/riscv-gnu-toolchain/) for raw ELFs from AUR (or do so manually, see toolchain docs):
```sh
paru -S riscv-gnu-toolchain-bin riscv64-elf-newlib
```
3. Clone this repo:
```sh
git clone --recursive https://github.com/Jojodicus/posit4ai
cd posit4ai
# if you did not clone recursively (by accident):
git submodule update --init --recursive
```
4. Build [forked LLVM Xposit](https://github.com/Jojodicus/llvm-xposit) (takes a long time):
```sh
cd llvm-xposit
mkdir -p $XPOSIT_INSTALL_DIR
mkdir build && cd build

cmake -G Ninja \
        -DCMAKE_BUILD_TYPE="Debug" \
        -DBUILD_SHARED_LIBS=True \
        -DLLVM_USE_SPLIT_DWARF=True \
        -DCMAKE_INSTALL_PREFIX=$XPOSIT_INSTALL_DIR \
        -DLLVM_OPTIMIZED_TABLEGEN=True \
        -DLLVM_BUILD_TESTS=True \
        -DDEFAULT_SYSROOT=$XPOSIT_GCC_DIR \
        -DLLVM_DEFAULT_TARGET_TRIPLE=$XPOSIT_TARGET \
        -DLLVM_TARGETS_TO_BUILD="RISCV" \
        -DLLVM_ENABLE_PROJECTS=clang \
        ../llvm
cmake --build . --target install -j$(nproc) # may have to lower nproc if memory-bound
cd ../..
```
5. Test compilation of [PERCIVAL](https://github.com/artecs-group/PERCIVAL) testsuite:
```sh
# compile
clang --target=riscv64-unknown-elf --sysroot=$XPOSIT_GCC_DIR -march=rv64gcxposit PERCIVAL/posit64_testsuite_llvm.c -c -o posit64_testsuite_llvm.o
# link
riscv64-unknown-elf-gcc posit64_testsuite_llvm.o -o posit64_testsuite_llvm.elf
```

you should now have a (portable) binary `posit64_testsuite_llvm.elf` with posit support. You can verify the asm with:

```sh
riscv64-unknown-elf-objdump -dCS --visualize-jumps=extended-color posit64_testsuite_llvm.elf | less -R
```

notice the `.insn 4, ...` in the test subroutines, these are our posit instructions
(we are using the stock RISC-V objdump, so it has no idea about the Xposit extension)

### Simulating with a Software Emulator (Spike)

Using a [forked version of the Spike ISA Simulator](https://github.com/jojodicus/spike-xposit),
you can run simple statically linked ELFs with Xposit support.

Don't forget to source `preparepath.sh` again (if not previously done in the shell session).

1. Build the Proxy Kernel
```sh
mkdir riscv-pk/build
cd riscv-pk/build
../configure --prefix=$RISCV --host=riscv64-unknown-elf
make -j4
cd ../..
ln -s riscv-pk/build/pk pk
```
2. Build Spike
```sh
mkdir spike-xposit/build
cd spike-xposit/build
../configure --prefix=$XPOSIT_INSTALL_DIR
make -j8 install
cd ../..
```
3. Compile a minimal C program without Posits
```sh
riscv64-unknown-elf-gcc csrc/hello-world.c -o hello-world.elf
```
4. Test with Spike and the Proxy Kernel
```sh
spike pk hello-world.elf
```
5. Test the PERCIVAL XPosit LLVM testsuite (compile steps shown in section above)
```sh
spike pk posit64_testsuite_llvm.elf
```

Division and square root might differ in their output from the PERCIVAL results.
This is expected, PERCIVAL (optionally) does approximate computation for these to save hardware and clock cycles.
The simulator on the other hand does exact arithmetic as emulated by [stillwater-sc/universal](https://github.com/stillwater-sc/universal).
