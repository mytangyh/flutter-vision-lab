cmake_minimum_required(VERSION 3.18)
project(aicamera_mnn LANGUAGES C CXX)

include(FetchContent)

set(MNN_BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)
set(MNN_BUILD_TOOLS OFF CACHE BOOL "" FORCE)
set(MNN_BUILD_CONVERTER OFF CACHE BOOL "" FORCE)
set(MNN_BUILD_TEST OFF CACHE BOOL "" FORCE)
set(MNN_BUILD_BENCHMARK OFF CACHE BOOL "" FORCE)
set(MNN_BUILD_TRAIN OFF CACHE BOOL "" FORCE)
set(MNN_BUILD_QUANTOOLS OFF CACHE BOOL "" FORCE)
set(MNN_SEP_BUILD OFF CACHE BOOL "" FORCE)
set(MNN_OPENCL ON CACHE BOOL "" FORCE)
set(MNN_VULKAN OFF CACHE BOOL "" FORCE)
set(MNN_ARM82 ON CACHE BOOL "" FORCE)
set(MNN_KLEIDIAI OFF CACHE BOOL "" FORCE)
set(MNN_LOW_MEMORY ON CACHE BOOL "" FORCE)
set(MNN_USE_LOGCAT ON CACHE BOOL "" FORCE)

if(DEFINED ENV{AICAMERA_MNN_SOURCE_DIR}
   AND EXISTS "$ENV{AICAMERA_MNN_SOURCE_DIR}/CMakeLists.txt")
  set(mnn_SOURCE_DIR "$ENV{AICAMERA_MNN_SOURCE_DIR}")
  add_subdirectory(
    "${mnn_SOURCE_DIR}"
    "${CMAKE_BINARY_DIR}/_deps/mnn-build"
  )
else()
  FetchContent_Declare(
    mnn
    URL https://github.com/alibaba/MNN/archive/refs/tags/3.5.0.tar.gz
  )
  FetchContent_MakeAvailable(mnn)
endif()

add_library(aicamera_mnn SHARED mnn_bridge.cpp)
target_compile_features(aicamera_mnn PRIVATE cxx_std_17)
target_include_directories(aicamera_mnn PRIVATE ${mnn_SOURCE_DIR}/include)
target_link_libraries(aicamera_mnn PRIVATE MNN log android)
