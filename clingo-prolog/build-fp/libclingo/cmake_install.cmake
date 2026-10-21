# Install script for directory: /home/ribben/Desktop/Thesis/clingo-lazy-heuristics/clingo-prolog/libclingo

# Set the install prefix
if(NOT DEFINED CMAKE_INSTALL_PREFIX)
  set(CMAKE_INSTALL_PREFIX "/usr/local")
endif()
string(REGEX REPLACE "/$" "" CMAKE_INSTALL_PREFIX "${CMAKE_INSTALL_PREFIX}")

# Set the install configuration name.
if(NOT DEFINED CMAKE_INSTALL_CONFIG_NAME)
  if(BUILD_TYPE)
    string(REGEX REPLACE "^[^A-Za-z0-9_]+" ""
           CMAKE_INSTALL_CONFIG_NAME "${BUILD_TYPE}")
  else()
    set(CMAKE_INSTALL_CONFIG_NAME "Release")
  endif()
  message(STATUS "Install configuration: \"${CMAKE_INSTALL_CONFIG_NAME}\"")
endif()

# Set the component getting installed.
if(NOT CMAKE_INSTALL_COMPONENT)
  if(COMPONENT)
    message(STATUS "Install component: \"${COMPONENT}\"")
    set(CMAKE_INSTALL_COMPONENT "${COMPONENT}")
  else()
    set(CMAKE_INSTALL_COMPONENT)
  endif()
endif()

# Install shared libraries without execute permission?
if(NOT DEFINED CMAKE_INSTALL_SO_NO_EXE)
  set(CMAKE_INSTALL_SO_NO_EXE "0")
endif()

# Is this installation the result of a crosscompile?
if(NOT DEFINED CMAKE_CROSSCOMPILING)
  set(CMAKE_CROSSCOMPILING "FALSE")
endif()

# Set path to fallback-tool for dependency-resolution.
if(NOT DEFINED CMAKE_OBJDUMP)
  set(CMAKE_OBJDUMP "/usr/bin/objdump")
endif()

if(CMAKE_INSTALL_COMPONENT STREQUAL "Unspecified" OR NOT CMAKE_INSTALL_COMPONENT)
  foreach(file
      "$ENV{DESTDIR}${CMAKE_INSTALL_PREFIX}/lib/libclingo.so.4.0"
      "$ENV{DESTDIR}${CMAKE_INSTALL_PREFIX}/lib/libclingo.so.4"
      )
    if(EXISTS "${file}" AND
       NOT IS_SYMLINK "${file}")
      file(RPATH_CHECK
           FILE "${file}"
           RPATH "/usr/local/lib:/home/ribben/Desktop/Thesis/swipl-moderno/swipl-10.0.2/build/src")
    endif()
  endforeach()
  file(INSTALL DESTINATION "${CMAKE_INSTALL_PREFIX}/lib" TYPE SHARED_LIBRARY FILES
    "/home/ribben/Desktop/Thesis/clingo-lazy-heuristics/clingo-prolog/build-fp/bin/libclingo.so.4.0"
    "/home/ribben/Desktop/Thesis/clingo-lazy-heuristics/clingo-prolog/build-fp/bin/libclingo.so.4"
    )
  foreach(file
      "$ENV{DESTDIR}${CMAKE_INSTALL_PREFIX}/lib/libclingo.so.4.0"
      "$ENV{DESTDIR}${CMAKE_INSTALL_PREFIX}/lib/libclingo.so.4"
      )
    if(EXISTS "${file}" AND
       NOT IS_SYMLINK "${file}")
      file(RPATH_CHANGE
           FILE "${file}"
           OLD_RPATH "/home/ribben/Desktop/Thesis/swipl-moderno/swipl-10.0.2/build/src:::::::::::::::"
           NEW_RPATH "/usr/local/lib:/home/ribben/Desktop/Thesis/swipl-moderno/swipl-10.0.2/build/src")
      if(CMAKE_INSTALL_DO_STRIP)
        execute_process(COMMAND "/usr/bin/strip" "${file}")
      endif()
    endif()
  endforeach()
endif()

if(CMAKE_INSTALL_COMPONENT STREQUAL "Unspecified" OR NOT CMAKE_INSTALL_COMPONENT)
  file(INSTALL DESTINATION "${CMAKE_INSTALL_PREFIX}/lib" TYPE SHARED_LIBRARY FILES "/home/ribben/Desktop/Thesis/clingo-lazy-heuristics/clingo-prolog/build-fp/bin/libclingo.so")
endif()

if(CMAKE_INSTALL_COMPONENT STREQUAL "Unspecified" OR NOT CMAKE_INSTALL_COMPONENT)
  file(INSTALL DESTINATION "${CMAKE_INSTALL_PREFIX}/include" TYPE FILE FILES
    "/home/ribben/Desktop/Thesis/clingo-lazy-heuristics/clingo-prolog/libclingo/clingo.hh"
    "/home/ribben/Desktop/Thesis/clingo-lazy-heuristics/clingo-prolog/libclingo/clingo.h"
    )
endif()

if(CMAKE_INSTALL_COMPONENT STREQUAL "Unspecified" OR NOT CMAKE_INSTALL_COMPONENT)
  if(EXISTS "$ENV{DESTDIR}${CMAKE_INSTALL_PREFIX}/lib/cmake/Clingo/ClingoTargets.cmake")
    file(DIFFERENT _cmake_export_file_changed FILES
         "$ENV{DESTDIR}${CMAKE_INSTALL_PREFIX}/lib/cmake/Clingo/ClingoTargets.cmake"
         "/home/ribben/Desktop/Thesis/clingo-lazy-heuristics/clingo-prolog/build-fp/libclingo/CMakeFiles/Export/21ec72f2e5be65a5585c7b00c9a7a62f/ClingoTargets.cmake")
    if(_cmake_export_file_changed)
      file(GLOB _cmake_old_config_files "$ENV{DESTDIR}${CMAKE_INSTALL_PREFIX}/lib/cmake/Clingo/ClingoTargets-*.cmake")
      if(_cmake_old_config_files)
        string(REPLACE ";" ", " _cmake_old_config_files_text "${_cmake_old_config_files}")
        message(STATUS "Old export file \"$ENV{DESTDIR}${CMAKE_INSTALL_PREFIX}/lib/cmake/Clingo/ClingoTargets.cmake\" will be replaced.  Removing files [${_cmake_old_config_files_text}].")
        unset(_cmake_old_config_files_text)
        file(REMOVE ${_cmake_old_config_files})
      endif()
      unset(_cmake_old_config_files)
    endif()
    unset(_cmake_export_file_changed)
  endif()
  file(INSTALL DESTINATION "${CMAKE_INSTALL_PREFIX}/lib/cmake/Clingo" TYPE FILE FILES "/home/ribben/Desktop/Thesis/clingo-lazy-heuristics/clingo-prolog/build-fp/libclingo/CMakeFiles/Export/21ec72f2e5be65a5585c7b00c9a7a62f/ClingoTargets.cmake")
  if(CMAKE_INSTALL_CONFIG_NAME MATCHES "^([Rr][Ee][Ll][Ee][Aa][Ss][Ee])$")
    file(INSTALL DESTINATION "${CMAKE_INSTALL_PREFIX}/lib/cmake/Clingo" TYPE FILE FILES "/home/ribben/Desktop/Thesis/clingo-lazy-heuristics/clingo-prolog/build-fp/libclingo/CMakeFiles/Export/21ec72f2e5be65a5585c7b00c9a7a62f/ClingoTargets-release.cmake")
  endif()
endif()

if(CMAKE_INSTALL_COMPONENT STREQUAL "Unspecified" OR NOT CMAKE_INSTALL_COMPONENT)
  file(INSTALL DESTINATION "${CMAKE_INSTALL_PREFIX}/lib/cmake/Clingo" TYPE FILE FILES
    "/home/ribben/Desktop/Thesis/clingo-lazy-heuristics/clingo-prolog/build-fp/libclingo/ClingoConfig.cmake"
    "/home/ribben/Desktop/Thesis/clingo-lazy-heuristics/clingo-prolog/build-fp/libclingo/ClingoConfigVersion.cmake"
    )
endif()

string(REPLACE ";" "\n" CMAKE_INSTALL_MANIFEST_CONTENT
       "${CMAKE_INSTALL_MANIFEST_FILES}")
if(CMAKE_INSTALL_LOCAL_ONLY)
  file(WRITE "/home/ribben/Desktop/Thesis/clingo-lazy-heuristics/clingo-prolog/build-fp/libclingo/install_local_manifest.txt"
     "${CMAKE_INSTALL_MANIFEST_CONTENT}")
endif()
