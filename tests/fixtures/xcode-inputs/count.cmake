# usage: cmake -DFILE=<generated sources.cmake> -DVAR=<name> -P count.cmake
#        prints the generated variable's entries, one per line, by including the validated file
cmake_minimum_required(VERSION 3.19)
include("${FILE}")
foreach(p IN LISTS ${VAR})
  execute_process(COMMAND "${CMAKE_COMMAND}" -E echo "${p}")
endforeach()
