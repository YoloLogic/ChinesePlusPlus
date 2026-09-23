cmake_minimum_required(VERSION 3.20)

# ============ 项目自包含的编译器配置（不依赖任何环境变量）============

# 1) 必须在 project() 之前设置，否则不生效。
#    指向本项目构建的中文版 clang++。
set(CMAKE_CXX_COMPILER "E:/Chinese++/build/Release/bin/clang++.exe")

# 2) CMake 在 Windows 上给 clang 默认传 -fuse-ld=lld-link，
#    但本项目只构建了 clang、没有构建 lld。改用 MSVC 的 link.exe。
set(CMAKE_LINKER_TYPE MSVC)

# 3) CMake 还需要资源编译器 rc.exe，它在 Windows SDK 里、默认不在 PATH。
#    这里自动挑选已安装的最新版本，免去配置环境变量的麻烦。
if(WIN32 AND NOT CMAKE_RC_COMPILER)
  file(GLOB _rc_all "C:/Program Files (x86)/Windows Kits/10/bin/*/x64/rc.exe")
  if(_rc_all)
    list(SORT _rc_all)
    list(GET _rc_all -1 _rc_newest)
    set(CMAKE_RC_COMPILER "${_rc_newest}")
    message(STATUS "使用 rc.exe: ${CMAKE_RC_COMPILER}")
  endif()
endif()

# =====================================================================

project(zhcpp_demo LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

add_executable(demo demo.cpp)

