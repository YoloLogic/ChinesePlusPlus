cmake_minimum_required(VERSION 3.20)

# 关键：必须在 project() 之前设置，否则不生效。
# 把 C++ 编译器指定为本项目构建的中文版 clang++。
# 这样只在【本项目】生效，不必改动 CLion 的全局工具链设置。
set(CMAKE_CXX_COMPILER "E:/Chinese++/build/Release/bin/clang++.exe")

project(中文C++示例 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

add_executable(中文示例 示例.cpp)
