# RequireAppleClang.cmake -- fail configuration fast on a non-Apple compiler.
#
# Include right after project() (which populates CMAKE_<LANG>_COMPILER_ID). Apple's
# clang + SDK are what produce loadable/ABI-correct 10.9 artifacts; an IDE (CLion)
# discovers a compiler from PATH and can silently land on a pkgsrc/Homebrew gcc or
# LLVM clang. Both build hosts use Apple's clang -- Xcode 6's /usr/bin/clang on
# 10.9, the current Xcode's clang on a modern host.
#
# By default this checks every language project() enabled and requires each to be
# AppleClang -- so a plain `include(Mavergreen)` just works, no configuration. Knobs:
#   set(MAVERICKS_REQUIRE_APPLECLANG OFF)  # opt out (an intentional non-Apple
#                                          # toolchain, or a foreign/Go build)
#   set(MAVERICKS_REQUIRE_LANGS C OBJC)    # override which languages to check
#                                          # (default: the project's enabled languages)
#   set(MAVERICKS_REQUIRE_BLOCKS ON)       # optional -fblocks functional backstop

if(NOT DEFINED MAVERICKS_REQUIRE_APPLECLANG)
  set(MAVERICKS_REQUIRE_APPLECLANG ON)
endif()

# Default to whatever languages project() enabled. A `LANGUAGES NONE` project reports
# ENABLED_LANGUAGES as "NONE"; drop it so the gate is a no-op there.
if(NOT DEFINED MAVERICKS_REQUIRE_LANGS)
  get_property(MAVERICKS_REQUIRE_LANGS GLOBAL PROPERTY ENABLED_LANGUAGES)
endif()
list(REMOVE_ITEM MAVERICKS_REQUIRE_LANGS NONE)

if(MAVERICKS_REQUIRE_APPLECLANG)
  foreach(_lang IN LISTS MAVERICKS_REQUIRE_LANGS)
    if(NOT CMAKE_${_lang}_COMPILER_ID STREQUAL "AppleClang")
      message(FATAL_ERROR
        "${PROJECT_NAME} requires Apple's clang (AppleClang) for ${_lang}, but got "
        "'${CMAKE_${_lang}_COMPILER_ID}' (${CMAKE_${_lang}_COMPILER}).\n"
        "A gcc or Homebrew/pkgsrc LLVM clang (often from an IDE's PATH) produces "
        "artifacts that will not load. Point the compiler at Apple's clang and "
        "reconfigure a CLEAN build dir, e.g.:\n"
        "    cmake -S . -B build -DCMAKE_C_COMPILER=/usr/bin/clang -DCMAKE_CXX_COMPILER=/usr/bin/clang++\n"
        "In CLion: Settings > Build > CMake > Toolchain -> /usr/bin/clang, then reset the cache.\n"
        "If a non-Apple toolchain is intended here, set(MAVERICKS_REQUIRE_APPLECLANG OFF) before include(Mavergreen).")
    endif()
  endforeach()

  # Functional backstop for a mislabeled/misconfigured compiler: many of these
  # projects use Apple blocks. Opt in with MAVERICKS_REQUIRE_BLOCKS.
  if(MAVERICKS_REQUIRE_BLOCKS)
    include(CheckCSourceCompiles)
    set(_mav_save_flags "${CMAKE_REQUIRED_FLAGS}")
    set(CMAKE_REQUIRED_FLAGS "-fblocks")
    check_c_source_compiles("int main(void){ void (^b)(void) = ^{}; b(); return 0; }" MAVERICKS_CC_HAS_BLOCKS)
    set(CMAKE_REQUIRED_FLAGS "${_mav_save_flags}")
    if(NOT MAVERICKS_CC_HAS_BLOCKS)
      message(FATAL_ERROR
        "The selected C compiler (${CMAKE_C_COMPILER_ID}, ${CMAKE_C_COMPILER}) cannot "
        "build Apple blocks (-fblocks). Use Apple's clang.")
    endif()
  endif()

  list(LENGTH MAVERICKS_REQUIRE_LANGS _mav_nlangs)
  if(_mav_nlangs GREATER 0)
    list(GET MAVERICKS_REQUIRE_LANGS 0 _mav_first_lang)
    message(STATUS "${PROJECT_NAME} compiler OK: AppleClang "
                   "${CMAKE_${_mav_first_lang}_COMPILER_VERSION} (${CMAKE_${_mav_first_lang}_COMPILER})")
  endif()
endif()
