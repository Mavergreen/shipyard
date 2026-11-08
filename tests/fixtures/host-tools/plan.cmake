# usage: cmake -DMODULE_DIR=<dir> -DSYSCTL=<program> -DCOMPILER=<path> -DOUT=<file> -P plan.cmake
#        writes the host plan and configure arguments mavergreen_build_host_tools would use, one per line
cmake_minimum_required(VERSION 3.19)
list(APPEND CMAKE_MODULE_PATH "${MODULE_DIR}")
include(MavergreenHostTools)
set(MAVERGREEN_HOST_TOOLS_SYSCTL "${SYSCTL}")
set(MAVERGREEN_HOST_TOOLS_UNAME "${UNAME}")
_mht_host_plan(plan)
_mht_configure_args(args ARCH "${plan_ARCH}" TARGET "${plan_TARGET}" MIN "${plan_MIN}" SDK "/sdk/for/${plan_ARCH}"
  COMPILER "${COMPILER}" SOURCE /src BUILD_DIR /build MAKE /usr/bin/make)
_mht_cache_key(k1 ARCH x86_64 COMPILER_ID "cc 1" SDK_PIN "pin-a" SOURCE_ID "src-a" IMPL_ID "impl-a")
_mht_cache_key(k2 ARCH x86_64 COMPILER_ID "cc 1" SDK_PIN "pin-b" SOURCE_ID "src-a" IMPL_ID "impl-a")
_mht_cache_key(k3 ARCH x86_64 COMPILER_ID "cc 1" SDK_PIN "pin-a" SOURCE_ID "src-b" IMPL_ID "impl-a")
_mht_cache_key(k4 ARCH arm64 COMPILER_ID "cc 1" SDK_PIN "pin-a" SOURCE_ID "src-a" IMPL_ID "impl-a")
_mht_cache_key(k5 ARCH x86_64 COMPILER_ID "cc 2" SDK_PIN "pin-a" SOURCE_ID "src-a" IMPL_ID "impl-a")
_mht_cache_key(k6 ARCH x86_64 COMPILER_ID "cc 1" SDK_PIN "pin-a" SOURCE_ID "src-a" IMPL_ID "impl-b")
_mht_cache_key(k1again ARCH x86_64 COMPILER_ID "cc 1" SDK_PIN "pin-a" SOURCE_ID "src-a" IMPL_ID "impl-a")
string(JOIN "\n" text "arch=${plan_ARCH}" "target=${plan_TARGET}" "min=${plan_MIN}" "launch=${plan_LAUNCH}"
  "keys=${k1} ${k2} ${k3} ${k4} ${k5} ${k6}" "key-again=${k1again}" ${args})
file(WRITE "${OUT}" "${text}\n")
