cmake_minimum_required(VERSION 3.10)

project(verovio_flutter LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

set(VRV_ROOT ${CMAKE_CURRENT_SOURCE_DIR}/../third_party/verovio)

file(GLOB_RECURSE VEROVIO_SRC
  ${VRV_ROOT}/src/*.cpp
  ${VRV_ROOT}/src/json/*.cc
  ${VRV_ROOT}/libmei/addons/*.cpp
  ${VRV_ROOT}/libmei/dist/*.cpp
  ${VRV_ROOT}/tools/c_wrapper.cpp
)

add_library(verovio_flutter SHARED
  verovio_ffi.cpp
  ${VEROVIO_SRC}
)

target_include_directories(verovio_flutter PRIVATE
  ${CMAKE_CURRENT_SOURCE_DIR}
  ${VRV_ROOT}/include
  ${VRV_ROOT}/include/vrv
  ${VRV_ROOT}/include/pugi
  ${VRV_ROOT}/include/midi
  ${VRV_ROOT}/include/crc
  ${VRV_ROOT}/include/hum
  ${VRV_ROOT}/include/json
  ${VRV_ROOT}/include/tuning-library
  ${VRV_ROOT}/include/zip
  ${VRV_ROOT}/libmei/dist
  ${VRV_ROOT}/libmei/addons
)

target_link_options(verovio_flutter PRIVATE -Wl,-z,max-page-size=0x4000)
target_link_libraries(verovio_flutter PRIVATE log)
