cmake_minimum_required(VERSION 3.16)

# Guard — only reached when BUILD_PTPD_TESTS=ON (enforced by parent CMakeLists)
find_package(GTest REQUIRED)

# Common include directories reused by every test target
set(PTPD_TEST_INCLUDES
    ${PROJECT_BINARY_DIR}                             # config.h
    ${CMAKE_SOURCE_DIR}/src                           # ptpd headers
    ${CMAKE_SOURCE_DIR}/src-app/macos                 # ptpd_app_utils.h
)

# Common compile definitions
set(PTPD_TEST_DEFS HAVE_CONFIG_H)

# -----------------------------------------------------------------------
# Helper function: define one test target with consistent flags/links
# -----------------------------------------------------------------------
function(ptpd_gtest target source)
    add_executable(${target} ${source})
    target_include_directories(${target} PRIVATE ${PTPD_TEST_INCLUDES})
    target_compile_definitions(${target} PRIVATE ${PTPD_TEST_DEFS})
    target_link_libraries(${target} PRIVATE GTest::gtest_main ptpd_app_utils)
    if(BUILD_WITH_SWCLOCK)
        target_link_libraries(${target} PRIVATE swclock)
        target_include_directories(${target} PRIVATE
            ${CMAKE_SOURCE_DIR}/libraries/swclock/src/sw_clock)
        target_compile_definitions(${target} PRIVATE PTPD_USE_SWCLOCK)
    endif()
    add_test(NAME ${target} COMMAND ${target})
endfunction()

# -----------------------------------------------------------------------
# Test targets (one executable per test file — fast, isolated)
# -----------------------------------------------------------------------

# Pure unit tests — no ptpd, no network, no threads
ptpd_gtest(test_strip_arg         test_strip_arg.cpp)
ptpd_gtest(test_monitor_csv       test_monitor_csv.cpp)

# Timer / concurrency tests
ptpd_gtest(test_monotonic_sleep   test_monotonic_sleep.cpp)

# Network pre-flight (SKIP when GM/en5 absent)
ptpd_gtest(test_network           test_network.cpp)

# Concurrency regression: swclock rdlock starvation
ptpd_gtest(test_swclock_rwlock    test_swclock_rwlock.cpp)

# swclock API integration (no full ptpd daemon)
ptpd_gtest(test_swclock_integration test_swclock_integration.cpp)

# Label all six targets as "unit" for selective ctest runs
set_tests_properties(
    test_strip_arg test_monitor_csv test_monotonic_sleep
    test_network test_swclock_rwlock test_swclock_integration
    PROPERTIES LABELS "unit")

# -----------------------------------------------------------------------
# System integration test — calls ptpd_init/start/shutdown directly;
# requires root + live GM on IFACE.  Labelled "integration" so unit-only
# runs can exclude it:  ctest -L unit   vs   ctest (all)
# -----------------------------------------------------------------------
ptpd_gtest(test_system_integration test_system_integration.cpp)
target_link_libraries(test_system_integration PRIVATE ptpd-shared)
target_include_directories(test_system_integration PRIVATE
    ${CMAKE_SOURCE_DIR}/src)
set_tests_properties(test_system_integration PROPERTIES
    TIMEOUT 300
    LABELS  "integration"
    WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}"
    ENVIRONMENT "PTPD_TEST_CONFIG=${CMAKE_SOURCE_DIR}/resources/ptpd-daemon-current.conf")

message(STATUS "ptpd src-gtests: 7 test targets configured (6 unit + 1 integration)")
