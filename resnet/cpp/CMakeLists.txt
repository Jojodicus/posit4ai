cmake_minimum_required(VERSION 3.14)
project(posit-resnet-inference)

# Threads & optimization flags ------------------------------------------------
cmake_host_system_information(RESULT N QUERY NUMBER_OF_LOGICAL_CORES)
add_definitions(-D LL_THREADS=${N} -D HL_THREADS=1)
# Quire mode (0 = disabled, 1 = old standard, 2 = new standard)
add_definitions(-D QUIRE_MODE=2)
# Underflow mode (0 = disabled, -1 = round, 1 = underflows <minpos/2^1, 2 = underflow <minpos/2^2, ...)
add_definitions(-D UNDERFLOW_MODE=0)
add_definitions(-D USING_PYTORCH)

if(NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE Release)
endif()

include(CheckCXXCompilerFlag)
foreach(flag -msse3 -mavx -mavx2)
    string(REPLACE "-" "" flag_name ${flag})
    check_cxx_compiler_flag(${flag} HAS_${flag_name})
    if(HAS_${flag_name})
        add_compile_options(${flag})
    endif()
endforeach()

# LibTorch --------------------------------------------------------------------
# Override with -DCMAKE_PREFIX_PATH=/path/to/libtorch if needed
if(NOT DEFINED CMAKE_PREFIX_PATH)
    set(CMAKE_PREFIX_PATH
        "${CMAKE_CURRENT_SOURCE_DIR}/../posit-neuralnet/include/libtorch/share/cmake/Torch")
endif()
set(CMAKE_CUDA_ARCHITECTURES "all")
find_package(Torch REQUIRED)
set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} ${TORCH_CXX_FLAGS}")

# Include paths ---------------------------------------------------------------
include_directories(
    "${CMAKE_CURRENT_SOURCE_DIR}/include"
    "${CMAKE_CURRENT_SOURCE_DIR}/../posit-neuralnet/include/universal/include"
    "${CMAKE_CURRENT_SOURCE_DIR}/../posit-neuralnet/include"
)

find_package(Threads REQUIRED)

# Targets ---------------------------------------------------------------------
add_executable(inference_posit src/inference_posit.cpp)
target_compile_features(inference_posit PRIVATE cxx_std_17)
target_link_libraries(inference_posit
    PRIVATE ${TORCH_LIBRARIES} Threads::Threads)

add_executable(train_posit src/train_posit.cpp)
target_compile_features(train_posit PRIVATE cxx_std_17)
target_link_libraries(train_posit
    PRIVATE ${TORCH_LIBRARIES} Threads::Threads)

add_executable(finetune_posit src/finetune_posit.cpp)
target_compile_features(finetune_posit PRIVATE cxx_std_17)
target_link_libraries(finetune_posit
    PRIVATE ${TORCH_LIBRARIES} Threads::Threads)
