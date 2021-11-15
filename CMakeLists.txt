cmake_minimum_required(VERSION 3.20)

set(CMAKE_TOOLCHAIN_FILE
    $ENV{VCPKG_ROOT}/scripts/buildsystems/vcpkg.cmake
    CACHE STRING "")
message(STATUS ${CMAKE_TOOLCHAIN_FILE})
project(minex VERSION 0.1.0)

include_directories(./src ./include)
add_executable(main src/main.cpp)

find_package(OpenCL REQUIRED)
find_package(fmt CONFIG REQUIRED)
target_link_libraries(main OpenCL::OpenCL fmt::fmt-header-only)
