# usage: cmake -DMODULE_DIR=<dir> -DCOMPILER=<path> -DARCHIVE=<zip> -DSHA=<hex> -DMANIFEST=<tsv> -DPREFIX=<p>
#              -DVERSION_MEMBER=<path> -DEXPECT=<version> -DOUT=<dir> -DRESULT=<file> -P extract.cmake
#        extracts the manifest's members and writes the directory they are in
cmake_minimum_required(VERSION 3.19)
list(APPEND CMAKE_MODULE_PATH "${MODULE_DIR}")
include(MavergreenResourceInputs)
mavergreen_extract_resource_members(dir ARCHIVE "${ARCHIVE}" SHA256 "${SHA}" MANIFEST "${MANIFEST}"
  MEMBER_PREFIX "${PREFIX}" VERSION_MEMBER "${VERSION_MEMBER}" EXPECT_VERSION "${EXPECT}"
  HOST_COMPILER "${COMPILER}" OUTPUT_DIR "${OUT}")
file(WRITE "${RESULT}" "${dir}")
