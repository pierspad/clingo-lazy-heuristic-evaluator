# [[[source: .
set(ide_source_group "Source Files")
set(source-group
    "${CMAKE_CURRENT_SOURCE_DIR}/astv2.cc"
    "${CMAKE_CURRENT_SOURCE_DIR}/clingo.cc"
    "${CMAKE_CURRENT_SOURCE_DIR}/heuristic_propagator.cc"
    "${CMAKE_CURRENT_SOURCE_DIR}/propagator.cc"
    "${CMAKE_CURRENT_SOURCE_DIR}/symbol.cc"
    "${CMAKE_CURRENT_SOURCE_DIR}/tests.hh"
    "${CMAKE_CURRENT_SOURCE_DIR}/variant.cc")
source_group("${ide_source_group}" FILES ${source-group})
set(source
    ${source-group})
if(CLINGO_BUILD_SHARED)
    list(APPEND source "${CMAKE_CURRENT_SOURCE_DIR}/../src/heuristic_propagator.cc")
    list(APPEND source "${CMAKE_CURRENT_SOURCE_DIR}/../src/swi_prolog_heuristic_backend.cc")
endif()
# ]]]

add_executable(test_clingo ${source})
target_link_libraries(test_clingo PRIVATE libclingo Catch2::Catch2WithMain)
target_include_directories(test_clingo PRIVATE
    $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}>
)
if (CLINGO_USE_SWIPL)
    target_compile_definitions(test_clingo PRIVATE CLINGO_USE_SWIPL)
    target_include_directories(test_clingo PRIVATE ${SWIPL_INCLUDE_DIRS})
    target_link_directories(test_clingo PRIVATE ${SWIPL_LIBRARY_DIRS})
    target_link_libraries(test_clingo PRIVATE ${SWIPL_LIBRARIES})
endif()
set_target_properties(test_clingo PROPERTIES FOLDER test)
if(MSVC)
    target_compile_definitions(test_clingo PRIVATE _SCL_SECURE_NO_WARNINGS)
endif()

add_test(NAME test_clingo COMMAND test_clingo)
