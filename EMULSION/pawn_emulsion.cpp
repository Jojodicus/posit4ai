#define _POSIX_C_SOURCE 199309L

#ifdef __cplusplus
extern "C" {
#endif
#include "../PAWN/sw/pawn.h"
#ifdef __cplusplus
}
#endif

#include <sw/universal/number/posit/posit.hpp>
#include <sw/universal/number/posit/fdp.hpp>
#include <sw/universal/number/quire/quire.hpp>

#include <cerrno>
#include <chrono>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <string>
#include <unordered_map>
#include <vector>

#ifndef EMULSION_POSIT_BITS
#error "EMULSION_POSIT_BITS must be defined as 8, 16, or 32"
#endif

#if EMULSION_POSIT_BITS != 8 && EMULSION_POSIT_BITS != 16 && EMULSION_POSIT_BITS != 32
#error "EMULSION_POSIT_BITS must be one of: 8, 16, 32"
#endif

namespace {

constexpr uint32_t kInstrDepth = 1u << 15;
constexpr uint32_t kDataDepth = 1u << 15;

using Posit = sw::universal::posit<EMULSION_POSIT_BITS, 2>;
using Quire = sw::universal::quire<Posit>;

struct EmuState {
    std::vector<uint64_t> ibram;
    std::vector<uint32_t> dbram;
    Quire quire;
    uint32_t status;

    EmuState() : ibram(kInstrDepth, 0), dbram(kDataDepth, 0), quire(), status(0) {}
};

static std::unordered_map<pawn_dev_t*, EmuState> g_states;

static void emu_error(const char* fn, const char* msg) {
    std::fprintf(stderr, "EMULSION %s: %s\n", fn, msg);
}

static EmuState* emu_get(pawn_dev_t* dev, const char* fn) {
    auto it = g_states.find(dev);
    if (it == g_states.end()) {
        emu_error(fn, "device not opened");
        return nullptr;
    }
    return &it->second;
}

static uint32_t raw_to_word(uint32_t raw) {
    if constexpr (EMULSION_POSIT_BITS == 8) {
        return static_cast<uint32_t>(static_cast<uint8_t>(raw)) << 24;
    }
    if constexpr (EMULSION_POSIT_BITS == 16) {
        return static_cast<uint32_t>(static_cast<uint16_t>(raw)) << 16;
    }
    return raw;
}

static uint32_t word_to_raw(uint32_t word) {
    if constexpr (EMULSION_POSIT_BITS == 8) {
        return static_cast<uint8_t>(word >> 24);
    }
    if constexpr (EMULSION_POSIT_BITS == 16) {
        return static_cast<uint16_t>(word >> 16);
    }
    return word;
}

static Posit bits_to_posit(uint32_t raw) {
    Posit p;
    p.setbits(raw);
    return p;
}

static uint32_t posit_to_bits(const Posit& p) {
    return static_cast<uint32_t>(p.bits().to_ull());
}

static uint32_t apply_binary(uint32_t a_word, uint32_t b_word, uint8_t opcode) {
    const Posit a = bits_to_posit(word_to_raw(a_word));
    const Posit b = bits_to_posit(word_to_raw(b_word));
    Posit out;

    switch (opcode) {
        case PAWN_OP_ADD: out = a + b; break;
        case PAWN_OP_SUB: out = a - b; break;
        case PAWN_OP_MUL: out = a * b; break;
        case PAWN_OP_DIV: out = a / b; break;
        default: out = Posit(0.0); break;
    }

    return raw_to_word(posit_to_bits(out));
}

static uint32_t apply_unary(uint32_t a_word, uint8_t opcode) {
    const Posit a = bits_to_posit(word_to_raw(a_word));
    Posit out;

    switch (opcode) {
        case PAWN_OP_SQRT:
            out = sw::universal::sqrt(a);
            break;
        case PAWN_OP_NEG:
            out = -a;
            break;
        case PAWN_OP_ABS: {
            double d = static_cast<double>(a);
            if (d < 0.0) {
                d = -d;
            }
            out = Posit(d);
            break;
        }
        case PAWN_OP_MOV:
            out = a;
            break;
        case PAWN_OP_RELU: {
            double d = static_cast<double>(a);
            out = (d < 0.0) ? Posit(0.0) : a;
            break;
        }
        default:
            out = Posit(0.0);
            break;
    }

    return raw_to_word(posit_to_bits(out));
}

static int run_program(EmuState& st, unsigned timeout_ms) {
    st.status = PAWN_STATUS_RUNNING;
    st.quire.clear();

    const auto t0 = std::chrono::steady_clock::now();
    for (uint32_t pc = 0; pc < kInstrDepth; ++pc) {
        const uint64_t instr = st.ibram[pc];
        const uint8_t op = static_cast<uint8_t>((instr >> 60) & 0xFu);
        const uint32_t a = static_cast<uint32_t>((instr >> 40) & 0xFFFFFu);
        const uint32_t b = static_cast<uint32_t>((instr >> 20) & 0xFFFFFu);
        const uint32_t r = static_cast<uint32_t>(instr & 0xFFFFFu);

        if (op == PAWN_OP_HALT) {
            st.status = PAWN_STATUS_DONE;
            return 0;
        }

        if (a >= kDataDepth || b >= kDataDepth || r >= kDataDepth) {
            emu_error("run_program", "DBRAM address out of range");
            st.status = PAWN_STATUS_DONE;
            return -1;
        }

        switch (op) {
            case PAWN_OP_ADD:
            case PAWN_OP_SUB:
            case PAWN_OP_MUL:
            case PAWN_OP_DIV:
                st.dbram[r] = apply_binary(st.dbram[a], st.dbram[b], op);
                break;

            case PAWN_OP_SQRT:
            case PAWN_OP_NEG:
            case PAWN_OP_ABS:
            case PAWN_OP_MOV:
            case PAWN_OP_RELU:
                st.dbram[r] = apply_unary(st.dbram[a], op);
                break;

            case PAWN_OP_QACC_CLEAR:
                st.quire.clear();
                break;

            case PAWN_OP_QACC_ADD: {
                const Posit pa = bits_to_posit(word_to_raw(st.dbram[a]));
                st.quire += sw::universal::quire_mul(pa, Posit(1.0));
                break;
            }

            case PAWN_OP_QACC_MADD: {
                const Posit pa = bits_to_posit(word_to_raw(st.dbram[a]));
                const Posit pb = bits_to_posit(word_to_raw(st.dbram[b]));
                st.quire += sw::universal::quire_mul(pa, pb);
                break;
            }

            case PAWN_OP_QACC_MSUB: {
                const Posit pa = bits_to_posit(word_to_raw(st.dbram[a]));
                const Posit pb = bits_to_posit(word_to_raw(st.dbram[b]));
                st.quire -= sw::universal::quire_mul(pa, pb);
                break;
            }

            case PAWN_OP_QACC_NEG:
                if (!st.quire.iszero()) {
                    st.quire.set_sign(!st.quire.sign());
                }
                break;

            case PAWN_OP_QACC_READ: {
                const Posit out = sw::universal::quire_resolve(st.quire);
                st.dbram[r] = raw_to_word(posit_to_bits(out));
                break;
            }

            default:
                emu_error("run_program", "unsupported opcode");
                st.status = PAWN_STATUS_DONE;
                return -1;
        }

        if (timeout_ms > 0) {
            const auto now = std::chrono::steady_clock::now();
            const auto elapsed = std::chrono::duration_cast<std::chrono::milliseconds>(now - t0).count();
            if (elapsed > static_cast<long long>(timeout_ms)) {
                emu_error("run_program", "timeout");
                st.status = PAWN_STATUS_DONE;
                return -1;
            }
        }
    }

    emu_error("run_program", "program reached max instruction depth without HALT");
    st.status = PAWN_STATUS_DONE;
    return -1;
}

}  // namespace

extern "C" {

int pawn_open(pawn_dev_t* dev) {
    if (dev == nullptr) {
        emu_error("pawn_open", "null device pointer");
        return -1;
    }
    std::memset(dev, 0, sizeof(*dev));
    dev->devmem_fd = -1;
    g_states[dev] = EmuState();
    return 0;
}

void pawn_close(pawn_dev_t* dev) {
    if (dev == nullptr) {
        return;
    }
    g_states.erase(dev);
    std::memset(dev, 0, sizeof(*dev));
    dev->devmem_fd = -1;
}

void pawn_reset(pawn_dev_t* dev) {
    EmuState* st = emu_get(dev, "pawn_reset");
    if (st == nullptr) {
        return;
    }
    st->status = 0;
    st->quire.clear();
}

int pawn_load_program(pawn_dev_t* dev, const uint64_t* instrs, size_t count) {
    EmuState* st = emu_get(dev, "pawn_load_program");
    if (st == nullptr) {
        return -1;
    }
    if (instrs == nullptr && count != 0) {
        emu_error("pawn_load_program", "null instruction pointer");
        return -1;
    }
    if (count > st->ibram.size()) {
        emu_error("pawn_load_program", "instruction count exceeds IBRAM depth");
        return -1;
    }
    std::fill(st->ibram.begin(), st->ibram.end(), 0);
    for (size_t i = 0; i < count; ++i) {
        st->ibram[i] = instrs[i];
    }
    return 0;
}

void pawn_dbram_write32(pawn_dev_t* dev, uint32_t base, const uint32_t* data, size_t count) {
    EmuState* st = emu_get(dev, "pawn_dbram_write32");
    if (st == nullptr) {
        return;
    }
    if (data == nullptr && count != 0) {
        emu_error("pawn_dbram_write32", "null data pointer");
        return;
    }
    if (base > st->dbram.size() || count > st->dbram.size() - base) {
        emu_error("pawn_dbram_write32", "write out of range");
        return;
    }
    for (size_t i = 0; i < count; ++i) {
        st->dbram[base + i] = data[i];
    }
}

void pawn_dbram_read32(pawn_dev_t* dev, uint32_t base, uint32_t* data, size_t count) {
    EmuState* st = emu_get(dev, "pawn_dbram_read32");
    if (st == nullptr) {
        return;
    }
    if (data == nullptr && count != 0) {
        emu_error("pawn_dbram_read32", "null data pointer");
        return;
    }
    if (base > st->dbram.size() || count > st->dbram.size() - base) {
        emu_error("pawn_dbram_read32", "read out of range");
        return;
    }
    for (size_t i = 0; i < count; ++i) {
        data[i] = st->dbram[base + i];
    }
}

void pawn_dbram_write64(pawn_dev_t*, uint32_t, const uint64_t*, size_t) {
    emu_error("pawn_dbram_write64", "64-bit mode is not supported in EMULSION");
}

void pawn_dbram_read64(pawn_dev_t*, uint32_t, uint64_t*, size_t) {
    emu_error("pawn_dbram_read64", "64-bit mode is not supported in EMULSION");
}

void pawn_dbram_poke32(pawn_dev_t* dev, uint32_t idx, uint32_t val) {
    pawn_dbram_write32(dev, idx, &val, 1);
}

uint32_t pawn_dbram_peek32(pawn_dev_t* dev, uint32_t idx) {
    uint32_t val = 0;
    pawn_dbram_read32(dev, idx, &val, 1);
    return val;
}

void pawn_dbram_poke64(pawn_dev_t*, uint32_t, uint64_t) {
    emu_error("pawn_dbram_poke64", "64-bit mode is not supported in EMULSION");
}

uint64_t pawn_dbram_peek64(pawn_dev_t*, uint32_t) {
    emu_error("pawn_dbram_peek64", "64-bit mode is not supported in EMULSION");
    return 0;
}

void pawn_start(pawn_dev_t* dev) {
    EmuState* st = emu_get(dev, "pawn_start");
    if (st == nullptr) {
        return;
    }
    (void)run_program(*st, 0);
}

int pawn_done(pawn_dev_t* dev) {
    EmuState* st = emu_get(dev, "pawn_done");
    if (st == nullptr) {
        return 0;
    }
    return (st->status & PAWN_STATUS_DONE) != 0;
}

uint32_t pawn_status(pawn_dev_t* dev) {
    EmuState* st = emu_get(dev, "pawn_status");
    if (st == nullptr) {
        return 0;
    }
    return st->status;
}

long long pawn_run_blocking(pawn_dev_t* dev, unsigned timeout_ms) {
    EmuState* st = emu_get(dev, "pawn_run_blocking");
    if (st == nullptr) {
        return -1;
    }

    const auto t0 = std::chrono::steady_clock::now();
    if (run_program(*st, timeout_ms) != 0) {
        return -1;
    }
    const auto t1 = std::chrono::steady_clock::now();
    return std::chrono::duration_cast<std::chrono::nanoseconds>(t1 - t0).count();
}

}  // extern "C"
