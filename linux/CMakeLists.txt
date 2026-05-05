# The Flutter tooling requires that developers have CMake 3.10 or later
# installed. You should not increase this version, as doing so will cause
# the plugin to fail to compile for some customers of the plugin.
cmake_minimum_required(VERSION 3.10)

# Project-level configuration.
set(PROJECT_NAME "audio_converter")
project(${PROJECT_NAME} LANGUAGES CXX)

# List of absolute paths to libraries that should be bundled with the plugin.
# This list could contain prebuilt libraries, or libraries created by an
# external build triggered from this build file.
set(audio_converter_bundled_libraries "")
file(GLOB _ffmpeg_shared_libraries CONFIGURE_DEPENDS
  "${CMAKE_CURRENT_SOURCE_DIR}/../build/ffmpeg-linux/install/lib/*.so"
  "${CMAKE_CURRENT_SOURCE_DIR}/../build/ffmpeg-linux/install/lib/*.so.*")
if(_ffmpeg_shared_libraries)
  list(APPEND audio_converter_bundled_libraries ${_ffmpeg_shared_libraries})
endif()
if(NOT CMAKE_CURRENT_SOURCE_DIR STREQUAL CMAKE_SOURCE_DIR)
  set(audio_converter_bundled_libraries "${audio_converter_bundled_libraries}" PARENT_SCOPE)
endif()
