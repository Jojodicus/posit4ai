#define CATCH_CONFIG_MAIN
#include <catch_amalgamated.hpp>

#include "targets/float32_target_test.hpp"
#include "targets/float64_target_test.hpp"
#include "targets/float32_accumulator_test.hpp"
#include "targets/float64_accumulator_test.hpp"
#include "targets/bfloat16_target_test.hpp"
#include "targets/bfloat16_accumulator_test.hpp"
#include "targets/tfloat32_target_test.hpp"
#include "targets/tfloat32_accumulator_test.hpp"
#include "targets/takum12_target_test.hpp"
#include "targets/takum12_accumulator_test.hpp"
#include "targets/takum16_target_test.hpp"
#include "targets/takum16_accumulator_test.hpp"
#include "targets/takum32_target_test.hpp"
#include "targets/takum32_accumulator_test.hpp"
#include "targets/takum48_target_test.hpp"
#include "targets/takum48_accumulator_test.hpp"

#ifdef __riscv_xposit
#include "targets/xposit_target_test.hpp"
#include "targets/xposit_accumulator_test.hpp"
#endif