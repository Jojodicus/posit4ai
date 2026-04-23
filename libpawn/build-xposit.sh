#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

export RISCV="/opt/riscv64-gnu-toolchain-elf-bin"
export XPOSIT_INSTALL_DIR="/home/jojo/Desktop/Uni/M4.Sem/ma/posit4ai/xposit-tools"
export PATH="${XPOSIT_INSTALL_DIR}/bin:${PATH}"
export XPOSIT_GCC_DIR="${RISCV}/riscv64-unknown-elf"
export XPOSIT_TARGET="riscv64-unknown-elf"

XPOSIT_CLANG="${XPOSIT_INSTALL_DIR}/bin/clang"
XPOSIT_CLANGXX="${XPOSIT_INSTALL_DIR}/bin/clang++"
RISCV_GCC="${RISCV}/bin/riscv64-unknown-elf-gcc"
RISCV_GXX="${RISCV}/bin/riscv64-unknown-elf-g++"
RISCV_AR="${RISCV}/bin/riscv64-unknown-elf-ar"
RISCV_SYSROOT="${RISCV}/riscv64-unknown-elf"
RISCV_LIB="${RISCV_SYSROOT}/lib"
SPIKE="${XPOSIT_INSTALL_DIR}/bin/spike"
PK="${REPO_ROOT}/pk"

CXXFLAGS="-march=rv64gc -mabi=lp64d -Wall -DCATCH_CONFIG_NO_POSIX_SIGNALS"
XPOSIT_CFLAGS="-march=rv64gcxposit -mabi=lp64d -Wall"

BUILD_DIR="${SCRIPT_DIR}/build_xposit"
rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}"

UNIVERSAL_INCLUDE="${REPO_ROOT}/spike-xposit/universal/include"
CATCH2_DIR="${BUILD_DIR}/catch2"

if [ ! -f "${CATCH2_DIR}/catch_amalgamated.hpp" ]; then
    echo "=== Fetching Catch2 amalgamated ==="
    mkdir -p "${CATCH2_DIR}"
    curl -sL https://raw.githubusercontent.com/catchorg/Catch2/v3.8.1/extras/catch_amalgamated.cpp -o "${CATCH2_DIR}/catch_amalgamated.cpp"
    curl -sL https://raw.githubusercontent.com/catchorg/Catch2/v3.8.1/extras/catch_amalgamated.hpp -o "${CATCH2_DIR}/catch_amalgamated.hpp"
fi

echo "=== Building xposit asm wrapper (with xposit LLVM) ==="
${XPOSIT_CLANG} ${XPOSIT_CFLAGS} \
    -target riscv64-unknown-elf \
    --sysroot="${XPOSIT_GCC_DIR}" \
    -c "${SCRIPT_DIR}/src/xposit_asm.c" \
    -o "${BUILD_DIR}/xposit_asm.o"

echo "=== Building pawn library ==="

for src in "${SCRIPT_DIR}"/src/targets/*.cpp \
          "${SCRIPT_DIR}"/src/targets/float/*.cpp \
          "${SCRIPT_DIR}"/src/targets/takum/*.cpp \
          "${SCRIPT_DIR}"/src/arith/*.cpp; do
    if [ -f "$src" ]; then
        echo "Compiling: $(basename "$src")"
        ${RISCV_GXX} ${CXXFLAGS} \
            -I"${SCRIPT_DIR}/include" \
            -I"${UNIVERSAL_INCLUDE}" \
            -std=c++20 \
            -c "$src" \
            -o "${BUILD_DIR}/$(basename "$src" .cpp).o"
    fi
done

echo "=== Creating static library ==="
${RISCV_AR} rcs "${BUILD_DIR}/libpawn.a" "${BUILD_DIR}"/*.o

echo "=== Building Catch2 ==="
${RISCV_GXX} ${CXXFLAGS} \
    -I"${CATCH2_DIR}" \
    -std=c++20 \
    -c "${CATCH2_DIR}/catch_amalgamated.cpp" \
    -o "${BUILD_DIR}/catch_amalgamated.o"

echo "=== Building test ==="
${RISCV_GXX} ${CXXFLAGS} \
    -I"${SCRIPT_DIR}/include" \
    -I"${UNIVERSAL_INCLUDE}" \
    -I"${CATCH2_DIR}" \
    -std=c++20 \
    -c "${SCRIPT_DIR}/test/test_pawn.cpp" \
    -o "${BUILD_DIR}/test_pawn.o"

echo "=== Linking test ==="
${RISCV_GCC} \
    "${BUILD_DIR}"/test_pawn.o \
    "${BUILD_DIR}"/catch_amalgamated.o \
    "${BUILD_DIR}"/libpawn.a \
    "${RISCV_LIB}/libstdc++.a" \
    "${RISCV_LIB}/libsupc++.a" \
    "${RISCV_LIB}/libc.a" \
    "${RISCV_LIB}/libm.a" \
    -o "${BUILD_DIR}/test_pawn.elf"

echo "=== Running tests on Spike ==="
${SPIKE} "${PK}" "${BUILD_DIR}/test_pawn.elf"