#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

if [ -z $RISCV ]
then
    echo Loading preparepath.sh environment...
    cd $REPO_ROOT
    . preparepath.sh
    cd $SCRIPT_DIR
fi

XPOSIT_CLANG="clang"
RISCV_GCC="riscv64-unknown-elf-gcc"
RISCV_GXX="riscv64-unknown-elf-g++"
RISCV_AR="riscv64-unknown-elf-ar"
RISCV_SYSROOT="${RISCV}/riscv64-unknown-elf"
RISCV_LIB="${RISCV_SYSROOT}/lib"
SPIKE="spike"
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
    --sysroot="${RISCV_SYSROOT}" \
    -I"${SCRIPT_DIR}/include" \
    -c "${SCRIPT_DIR}/src/xposit_asm.c" \
    -o "${BUILD_DIR}/xposit_asm.o"

echo "=== Building pawn library ==="

find "${SCRIPT_DIR}/src" -name '*.cpp' -type f | while read -r src; do
    echo "Compiling: $(basename "$src")"
    ${RISCV_GXX} ${CXXFLAGS} \
        -D__riscv_xposit \
        -I"${SCRIPT_DIR}/include" \
        -I"${UNIVERSAL_INCLUDE}" \
        -I"${UNIVERSAL_INCLUDE}/sw" \
        -I"${REPO_ROOT}/spike-xposit/universal/include/sw" \
        -std=c++20 \
        -c "$src" \
        -o "${BUILD_DIR}/$(basename "$src" .cpp).o"
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
    -D__riscv_xposit \
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
