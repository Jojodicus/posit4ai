cmake_minimum_required(VERSION 3.16)
project(libpawn VERSION 0.1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

set(UNIVERSAL_INCLUDE_DIR ../spike-xposit/universal/include/sw)

file(GLOB_RECURSE PAWN_SOURCES "src/*.cpp" "src/**/*.cpp")

add_library(pawn SHARED ${PAWN_SOURCES})
set_target_properties(pawn PROPERTIES
    OUTPUT_NAME "pawn"
    VERSION ${PROJECT_VERSION}
    SOVERSION 0
)

add_library(pawn_static STATIC ${PAWN_SOURCES})
set_target_properties(pawn_static PROPERTIES
    OUTPUT_NAME "pawn_static"
    VERSION ${PROJECT_VERSION}
    SOVERSION 0
)

target_include_directories(pawn_static PUBLIC include/)
target_include_directories(pawn_static PUBLIC ${UNIVERSAL_INCLUDE_DIR})

target_include_directories(pawn PUBLIC include/)
target_include_directories(pawn PUBLIC ${UNIVERSAL_INCLUDE_DIR})

add_library(pawn_alias INTERFACE)
target_link_libraries(pawn_alias INTERFACE pawn)

enable_testing()
add_subdirectory(test)