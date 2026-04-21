include(FetchContent)
FetchContent_Declare(Catch2
    GIT_REPOSITORY https://github.com/catchorg/Catch2.git
    GIT_TAG v3.8.1)
FetchContent_MakeAvailable(Catch2)

add_executable(test_pawn test_pawn.cpp)
target_link_libraries(test_pawn PRIVATE pawn Catch2::Catch2WithMain)
target_include_directories(test_pawn PRIVATE ${Catch2_SOURCE_DIR}/extras)
add_test(NAME pawn COMMAND test_pawn)
