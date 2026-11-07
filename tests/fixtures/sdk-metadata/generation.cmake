# usage: cmake -DMODULE_DIR=<dir> -DSDK=<dir> -DRECIPES=<json> -DIDS=<a;b> -DOUTPUT_DIR=<root> -DRESULT=<file> -P generation.cmake
#        the generation step of mavergreen_target_sdk_metadata, without a project or a compiler
cmake_minimum_required(VERSION 3.19)
list(APPEND CMAKE_MODULE_PATH "${MODULE_DIR}")
include(MavergreenSDKMetadata)
_msm_generation(overlay SDK "${SDK}" RECIPES "${RECIPES}" IDS ${IDS} OUTPUT_DIR "${OUTPUT_DIR}" IDENTITY "fixture")
file(WRITE "${RESULT}" "${overlay}")
