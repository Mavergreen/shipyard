# usage: cmake -DJSON=<inspector output> -DQUERY="<target name> <sources|headers|resources>" -P query.cmake
#        prints that phase's entries as "<kind> <path>", one per line, in the inspector's order
cmake_minimum_required(VERSION 3.19)
file(READ "${JSON}" j)
string(REGEX MATCH "^(.*) ([a-z]+)$" m "${QUERY}")
string(JSON n LENGTH "${j}" targets "${CMAKE_MATCH_1}" "${CMAKE_MATCH_2}")
if(n GREATER 0)
  math(EXPR last "${n} - 1")
  foreach(i RANGE ${last})
    string(JSON kind GET "${j}" targets "${CMAKE_MATCH_1}" "${CMAKE_MATCH_2}" ${i} kind)
    string(JSON path GET "${j}" targets "${CMAKE_MATCH_1}" "${CMAKE_MATCH_2}" ${i} path)
    execute_process(COMMAND "${CMAKE_COMMAND}" -E echo "${kind} ${path}")
  endforeach()
endif()
