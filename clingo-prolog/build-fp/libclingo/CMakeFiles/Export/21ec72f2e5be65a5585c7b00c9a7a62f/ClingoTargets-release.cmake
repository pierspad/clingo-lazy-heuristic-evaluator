#----------------------------------------------------------------
# Generated CMake target import file for configuration "Release".
#----------------------------------------------------------------

# Commands may need to know the format version.
set(CMAKE_IMPORT_FILE_VERSION 1)

# Import target "libclingo" for configuration "Release"
set_property(TARGET libclingo APPEND PROPERTY IMPORTED_CONFIGURATIONS RELEASE)
set_target_properties(libclingo PROPERTIES
  IMPORTED_LOCATION_RELEASE "${_IMPORT_PREFIX}/lib/libclingo.so.4.0"
  IMPORTED_SONAME_RELEASE "libclingo.so.4"
  )

list(APPEND _cmake_import_check_targets libclingo )
list(APPEND _cmake_import_check_files_for_libclingo "${_IMPORT_PREFIX}/lib/libclingo.so.4.0" )

# Commands beyond this point should not need to know the version.
set(CMAKE_IMPORT_FILE_VERSION)
