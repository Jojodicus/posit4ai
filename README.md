# Posit4AI

Master's thesis "Hardware-Level Comparison of Posit and Float Arithmetic for AI Applications" at [i3@FAU](https://www.cs3.tf.fau.de/).

## Usage and Development

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
paru -S riscv-gnu-toolchain-bin
```
3. Clone this repo:
```sh
git clone --recursive https://github.com/Jojodicus/posit4ai
cd posit4ai
# if you did not clone recursively (by accident):
git submodule update --init --recursive
```
4. Patch [LLVM Xposit](https://github.com/artecs-group/llvm-xposit):
```sh
cd llvm-xposit
git apply < ../0001-patch-for-modern-cpp.patch
cd ..
```
5. Build [LLVM Xposit](https://github.com/artecs-group/llvm-xposit) (takes a long time):
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
6. Test compilation of [PERCIVAL](https://github.com/artecs-group/PERCIVAL) testsuite:
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

### Simulating with a Software Emulator

Using a forked version of the [Spike](https://github.com/riscv-software-src/riscv-isa-sim) ISA Simulator,
you can run simple statically linked ELFs with Xposit support.

1. Build the Proxy Kernel
```sh
mkdir riscv-pk/build
cd riscv-pk/build
../configure --prefix=$RISCV --host=riscv64-unknown-elf
make -j4
cd ../..
```
2. Compile a minimal C program without Posits
```sh
riscv64-unknown-elf-gcc csrc/hello-world.c -o hello-world.elf
```
3. Test with Spike and the Proxy Kernel
```sh
spike riscv-pk/build/pk hello-world.elf
```

For now, only tested with spike from the CachyOS repos.

TODO:
- [ ] Integrate Spike into repo
- [ ] Give instructions on how to build and install spike + pk
- [ ] Fork and patch Spike for Xposit support
