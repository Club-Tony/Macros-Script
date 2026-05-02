cmake_minimum_required(VERSION 3.10)
project(MacrosEngine VERSION 1.0 LANGUAGES C)

set(CMAKE_C_STANDARD 11)

# Strict compiler warnings
add_compile_options(-Wall -Wextra -Wpedantic -Wno-unused-parameter -Wno-cast-function-type)

add_library(MacrosEngine SHARED
    src/engine.c
    src/xinput_poller.c
    src/event_recorder.c
    src/event_player.c
    src/event_format.c
    src/vjoy_output.c
    src/timing.c
)

if(WIN32)
    set_target_properties(MacrosEngine PROPERTIES
        PREFIX ""
        OUTPUT_NAME "MacrosEngine"
    )
endif()

target_include_directories(MacrosEngine PUBLIC include)
target_link_libraries(MacrosEngine PRIVATE winmm)
target_compile_definitions(MacrosEngine PRIVATE MACROS_ENGINE_EXPORTS)

# Static link the C runtime so the DLL is self-contained
target_link_options(MacrosEngine PRIVATE -static -static-libgcc)

# Test executable
add_executable(test_engine test/test_engine.c)
target_link_libraries(test_engine PRIVATE MacrosEngine kernel32)
target_compile_definitions(test_engine PRIVATE
    MACROS_TEST_FIXTURE_DIR="${CMAKE_CURRENT_SOURCE_DIR}/test/fixtures"
)

# XInput diff helper unit tests (uses #include "../src/xinput_poller.c"
# directly so the static helpers are reachable). Linked against MacrosEngine
# only for the Engine_*/CRITICAL_SECTION extern declarations.
add_executable(test_xinput_diff test/test_xinput_diff.c)
target_link_libraries(test_xinput_diff PRIVATE MacrosEngine kernel32)
target_compile_definitions(test_xinput_diff PRIVATE MACROS_XINPUT_DIFF_TEST)
