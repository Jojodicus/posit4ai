export RISCV="/opt/riscv64-gnu-toolchain-elf-bin"

# installed
export XPOSIT_GCC_INSTALL_DIR="/opt/riscv64-gnu-toolchain-elf-bin"
export XPOSIT_INSTALL_DIR="$PWD/xposit-tools"
export PATH="$XPOSIT_GCC_INSTALL_DIR/bin:$PATH"
export PATH="$XPOSIT_INSTALL_DIR/bin:$PATH"

# llvm-xposit build
export XPOSIT_GCC_DIR=$XPOSIT_GCC_INSTALL_DIR/riscv64-unknown-elf
export XPOSIT_TARGET="riscv64-unknown-elf"

