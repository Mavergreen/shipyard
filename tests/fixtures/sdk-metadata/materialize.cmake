# usage: cmake -DMODULE_DIR=<dir> -DSDK=<dir> -DRECIPES=<json> -DIDS=<a;b> -DOUTPUT_DIR=<dir> -DRESULT=<file> -P materialize.cmake
cmake_minimum_required(VERSION 3.19)
list(APPEND CMAKE_MODULE_PATH "${MODULE_DIR}")
include(MavergreenSDKMetadata)
mavergreen_materialize_sdk_metadata(overlay SDK "${SDK}" RECIPES "${RECIPES}" IDS ${IDS} OUTPUT_DIR "${OUTPUT_DIR}")
file(WRITE "${RESULT}" "${overlay}")
