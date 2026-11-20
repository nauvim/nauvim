cmake_minimum_required(VERSION 3.13)
project(nauvim_renderer_tests LANGUAGES CXX)

enable_testing()
find_package(PkgConfig REQUIRED)
pkg_check_modules(GLIB REQUIRED IMPORTED_TARGET glib-2.0)

add_executable(renderer_policy_test renderer_policy_test.cc ../renderer_policy.cc)
target_compile_features(renderer_policy_test PRIVATE cxx_std_14)
target_compile_options(renderer_policy_test PRIVATE -Wall -Wextra -Werror)
target_include_directories(renderer_policy_test PRIVATE ..)
target_link_libraries(renderer_policy_test PRIVATE PkgConfig::GLIB)
add_test(NAME renderer_policy COMMAND renderer_policy_test)
