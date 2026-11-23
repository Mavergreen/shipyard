cmake_minimum_required(VERSION 3.16)
# spec: scripts/build_updater.sh -- the one configure of a product's updater, its inputs in UPDATER_ARGS_FILE
project(MavergreenProductUpdater LANGUAGES OBJC)
set(MAVERICKS_REQUIRE_APPLECLANG OFF)
include("${CMAKE_CURRENT_LIST_DIR}/../../MavericksSparkle.cmake")
include("${UPDATER_ARGS_FILE}")
if(UPDATER_ICON)
  set(_icon ICON "${UPDATER_ICON}")
else()
  set(_icon ALLOW_GENERIC)
endif()
set(_opt)
foreach(k LOG_PREFIX RELAUNCH_MARKER)
  if(DEFINED UPDATER_${k})
    list(APPEND _opt ${k} "${UPDATER_${k}}")
  endif()
endforeach()
mavericks_add_updater_app(
  PRODUCT "${UPDATER_PRODUCT}"
  PRODUCT_NAME "${UPDATER_DISPLAY_NAME}"
  VERSION "${UPDATER_VERSION}"
  ED_PUBKEY_FILE "${UPDATER_PUBKEY_FILE}"
  CONFIRM_TITLE "${UPDATER_CONFIRM_TITLE}"
  CONFIRM_BODY "${UPDATER_CONFIRM_BODY}"
  ${_icon}
  ${_opt})
