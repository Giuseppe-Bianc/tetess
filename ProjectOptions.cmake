include(cmake/SystemLink.cmake)
include(cmake/LibFuzzer.cmake)
include(CMakeDependentOption)
include(CheckCXXCompilerFlag)


macro(tetess_supports_sanitizers)
  if((CMAKE_CXX_COMPILER_ID MATCHES ".*Clang.*" OR CMAKE_CXX_COMPILER_ID MATCHES ".*GNU.*") AND NOT WIN32)
    set(SUPPORTS_UBSAN ON)
  else()
    set(SUPPORTS_UBSAN OFF)
  endif()

  if((CMAKE_CXX_COMPILER_ID MATCHES ".*Clang.*" OR CMAKE_CXX_COMPILER_ID MATCHES ".*GNU.*") AND WIN32)
    set(SUPPORTS_ASAN OFF)
  else()
    set(SUPPORTS_ASAN ON)
  endif()
endmacro()

macro(tetess_setup_options)
  option(tetess_ENABLE_HARDENING "Enable hardening" ON)
  option(tetess_ENABLE_COVERAGE "Enable coverage reporting" OFF)
  cmake_dependent_option(
    tetess_ENABLE_GLOBAL_HARDENING
    "Attempt to push hardening options to built dependencies"
    ON
    tetess_ENABLE_HARDENING
    OFF)

  tetess_supports_sanitizers()

  if(NOT PROJECT_IS_TOP_LEVEL OR tetess_PACKAGING_MAINTAINER_MODE)
    option(tetess_ENABLE_IPO "Enable IPO/LTO" OFF)
    option(tetess_WARNINGS_AS_ERRORS "Treat Warnings As Errors" OFF)
    option(tetess_ENABLE_USER_LINKER "Enable user-selected linker" OFF)
    option(tetess_ENABLE_SANITIZER_ADDRESS "Enable address sanitizer" OFF)
    option(tetess_ENABLE_SANITIZER_LEAK "Enable leak sanitizer" OFF)
    option(tetess_ENABLE_SANITIZER_UNDEFINED "Enable undefined sanitizer" OFF)
    option(tetess_ENABLE_SANITIZER_THREAD "Enable thread sanitizer" OFF)
    option(tetess_ENABLE_SANITIZER_MEMORY "Enable memory sanitizer" OFF)
    option(tetess_ENABLE_UNITY_BUILD "Enable unity builds" OFF)
    option(tetess_ENABLE_CLANG_TIDY "Enable clang-tidy" OFF)
    option(tetess_ENABLE_CPPCHECK "Enable cpp-check analysis" OFF)
    option(tetess_ENABLE_PCH "Enable precompiled headers" OFF)
    option(tetess_ENABLE_CACHE "Enable ccache" OFF)
  else()
    option(tetess_ENABLE_IPO "Enable IPO/LTO" ON)
    option(tetess_WARNINGS_AS_ERRORS "Treat Warnings As Errors" ON)
    option(tetess_ENABLE_USER_LINKER "Enable user-selected linker" OFF)
    option(tetess_ENABLE_SANITIZER_ADDRESS "Enable address sanitizer" ${SUPPORTS_ASAN})
    option(tetess_ENABLE_SANITIZER_LEAK "Enable leak sanitizer" OFF)
    option(tetess_ENABLE_SANITIZER_UNDEFINED "Enable undefined sanitizer" ${SUPPORTS_UBSAN})
    option(tetess_ENABLE_SANITIZER_THREAD "Enable thread sanitizer" OFF)
    option(tetess_ENABLE_SANITIZER_MEMORY "Enable memory sanitizer" OFF)
    option(tetess_ENABLE_UNITY_BUILD "Enable unity builds" OFF)
    option(tetess_ENABLE_CLANG_TIDY "Enable clang-tidy" ON)
    option(tetess_ENABLE_CPPCHECK "Enable cpp-check analysis" ON)
    option(tetess_ENABLE_PCH "Enable precompiled headers" OFF)
    option(tetess_ENABLE_CACHE "Enable ccache" ON)
  endif()

  if(NOT PROJECT_IS_TOP_LEVEL)
    mark_as_advanced(
      tetess_ENABLE_IPO
      tetess_WARNINGS_AS_ERRORS
      tetess_ENABLE_USER_LINKER
      tetess_ENABLE_SANITIZER_ADDRESS
      tetess_ENABLE_SANITIZER_LEAK
      tetess_ENABLE_SANITIZER_UNDEFINED
      tetess_ENABLE_SANITIZER_THREAD
      tetess_ENABLE_SANITIZER_MEMORY
      tetess_ENABLE_UNITY_BUILD
      tetess_ENABLE_CLANG_TIDY
      tetess_ENABLE_CPPCHECK
      tetess_ENABLE_COVERAGE
      tetess_ENABLE_PCH
      tetess_ENABLE_CACHE)
  endif()

  tetess_check_libfuzzer_support(LIBFUZZER_SUPPORTED)
  if(LIBFUZZER_SUPPORTED AND (tetess_ENABLE_SANITIZER_ADDRESS OR tetess_ENABLE_SANITIZER_THREAD OR tetess_ENABLE_SANITIZER_UNDEFINED))
    set(DEFAULT_FUZZER ON)
  else()
    set(DEFAULT_FUZZER OFF)
  endif()

  option(tetess_BUILD_FUZZ_TESTS "Enable fuzz testing executable" ${DEFAULT_FUZZER})

endmacro()

macro(tetess_global_options)
  if(tetess_ENABLE_IPO)
    include(cmake/InterproceduralOptimization.cmake)
    tetess_enable_ipo()
  endif()

  tetess_supports_sanitizers()

  if(tetess_ENABLE_HARDENING AND tetess_ENABLE_GLOBAL_HARDENING)
    include(cmake/Hardening.cmake)
    if(NOT SUPPORTS_UBSAN 
       OR tetess_ENABLE_SANITIZER_UNDEFINED
       OR tetess_ENABLE_SANITIZER_ADDRESS
       OR tetess_ENABLE_SANITIZER_THREAD
       OR tetess_ENABLE_SANITIZER_LEAK)
      set(ENABLE_UBSAN_MINIMAL_RUNTIME FALSE)
    else()
      set(ENABLE_UBSAN_MINIMAL_RUNTIME TRUE)
    endif()
    message("${tetess_ENABLE_HARDENING} ${ENABLE_UBSAN_MINIMAL_RUNTIME} ${tetess_ENABLE_SANITIZER_UNDEFINED}")
    tetess_enable_hardening(tetess_options ON ${ENABLE_UBSAN_MINIMAL_RUNTIME})
  endif()
endmacro()

macro(tetess_local_options)
  if(PROJECT_IS_TOP_LEVEL)
    include(cmake/StandardProjectSettings.cmake)
  endif()

  add_library(tetess_warnings INTERFACE)
  add_library(tetess_options INTERFACE)

  include(cmake/CompilerWarnings.cmake)
  tetess_set_project_warnings(
    tetess_warnings
    ${tetess_WARNINGS_AS_ERRORS}
    ""
    ""
    ""
    "")

  if(tetess_ENABLE_USER_LINKER)
    include(cmake/Linker.cmake)
    configure_linker(tetess_options)
  endif()

  include(cmake/Sanitizers.cmake)
  tetess_enable_sanitizers(
    tetess_options
    ${tetess_ENABLE_SANITIZER_ADDRESS}
    ${tetess_ENABLE_SANITIZER_LEAK}
    ${tetess_ENABLE_SANITIZER_UNDEFINED}
    ${tetess_ENABLE_SANITIZER_THREAD}
    ${tetess_ENABLE_SANITIZER_MEMORY})

  set_target_properties(tetess_options PROPERTIES UNITY_BUILD ${tetess_ENABLE_UNITY_BUILD})

  if(tetess_ENABLE_PCH)
    target_precompile_headers(
      tetess_options
      INTERFACE
      <vector>
      <string>
      <utility>)
  endif()

  if(tetess_ENABLE_CACHE)
    include(cmake/Cache.cmake)
    tetess_enable_cache()
  endif()

  include(cmake/StaticAnalyzers.cmake)
  if(tetess_ENABLE_CLANG_TIDY)
    tetess_enable_clang_tidy(tetess_options ${tetess_WARNINGS_AS_ERRORS})
  endif()

  if(tetess_ENABLE_CPPCHECK)
    tetess_enable_cppcheck(${tetess_WARNINGS_AS_ERRORS} "" # override cppcheck options
    )
  endif()

  if(tetess_ENABLE_COVERAGE)
    include(cmake/Tests.cmake)
    tetess_enable_coverage(tetess_options)
  endif()

  if(tetess_WARNINGS_AS_ERRORS)
    check_cxx_compiler_flag("-Wl,--fatal-warnings" LINKER_FATAL_WARNINGS)
    if(LINKER_FATAL_WARNINGS)
      # This is not working consistently, so disabling for now
      # target_link_options(tetess_options INTERFACE -Wl,--fatal-warnings)
    endif()
  endif()

  if(tetess_ENABLE_HARDENING AND NOT tetess_ENABLE_GLOBAL_HARDENING)
    include(cmake/Hardening.cmake)
    if(NOT SUPPORTS_UBSAN 
       OR tetess_ENABLE_SANITIZER_UNDEFINED
       OR tetess_ENABLE_SANITIZER_ADDRESS
       OR tetess_ENABLE_SANITIZER_THREAD
       OR tetess_ENABLE_SANITIZER_LEAK)
      set(ENABLE_UBSAN_MINIMAL_RUNTIME FALSE)
    else()
      set(ENABLE_UBSAN_MINIMAL_RUNTIME TRUE)
    endif()
    tetess_enable_hardening(tetess_options OFF ${ENABLE_UBSAN_MINIMAL_RUNTIME})
  endif()

endmacro()
