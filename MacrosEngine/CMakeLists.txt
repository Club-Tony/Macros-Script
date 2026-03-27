cmake_minimum_required(VERSION 3.10)
project(MacrosEngine VERSION 1.0 LANGUAGES C)

set(CMAKE_C_STANDARD 11)

# Strict compiler warnings
add_compile_options(-Wall -Wextra -Wpedantic -Wno-unused-parameter)

add_library(MacrosEngine SHARED
    src/engine.c
    src/xinput_poller.c
    src/event_recorder.c
    src/event_player.c
    src/event_format.c
    src/timing.c
)

target_include_directories(MacrosEngine PUBLIC include)
target_link_libraries(MacrosEngine PRIVATE winmm)
target_compile_definitions(MacrosEngine PRIVATE MACROS_ENGINE_EXPORTS)

# Static link the C runtime so the DLL is self-contained
target_link_options(MacrosEngine PRIVATE -static -static-libgcc)

# Test executable
add_executable(test_engine test/test_engine.c)
target_link_libraries(test_engine PRIVATE MacrosEngine kernel32)
