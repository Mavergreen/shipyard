# platform: host-agnostic
#   usage: . sdk-pins.sh     (sourced; defines the three functions below)
#          mav_sdk_pin <arch>                            "<url> <sha256> <tarball> <sdk-dir>"; 1 if unknown
#          mav_sdk_rule <arch> <filetype> <minos> <sdk>  0 if compliant, else prints why and returns 1
#          mav_sdk_exempt_sha256 <sha256>                0 if the bytes are a pinned third-party file
# spec: claude-plugins/mavergreen/skills/mavergreen-conventions/SKILL.md "SDK pinning" -- the ONE place
#       the pins and the per-arch rule live; fetch_sdk.sh, assert_binary_compatible.sh and
#       check-artifact-conformance.sh all source it, so the three cannot disagree.

mav_sdk_pin() {
  case "$1" in
    x86_64) echo "https://github.com/phracker/MacOSX-SDKs/releases/download/11.3/MacOSX10.9.sdk.tar.xz fcf88ce8ff0dd3248b97f4eb81c7909f2cc786725de277f4d05a2b935cc49de0 MacOSX10.9.sdk.tar.xz MacOSX10.9.sdk" ;;
    # platform: phracker publishes no checksum; this one was recorded on first download (2026-09-24)
    #           and cross-checked against joseluisq/macosx-sdks 11.3, whose published sha256 verified:
    #           every .tbd and framework header in the two was identical.
    arm64)  echo "https://github.com/phracker/MacOSX-SDKs/releases/download/11.3/MacOSX11.3.sdk.tar.xz cd4f08a75577145b8f05245a2975f7c81401d75e9535dcffbb879ee1deefcbf4 MacOSX11.3.sdk.tar.xz MacOSX11.3.sdk" ;;
    *) return 1 ;;
  esac
}

mav_sdk_rule() {  # $1 arch, $2 filetype, $3 minos, $4 sdk
  if [ "$2" = KEXTBUNDLE ]; then
    [ "$1" = x86_64 ] && return 0
    echo "a kext must be x86_64, not $1"; return 1
  fi
  case "$1" in
    x86_64) _want_min=10.9; _want_sdk=10.9 ;;
    arm64)  _want_min=11.0; _want_sdk=11.3 ;;
    *) echo "arch $1 has no pinned SDK (only x86_64 and arm64 do)"; return 1 ;;
  esac
  # platform: an object file (a static archive's member) records sdk "n/a" when compiled against the
  #           10.9 SDK, which ships no SDKSettings.json to read a version from -- so a member can prove
  #           its minos but not its SDK.
  [ "$2" = OBJECT ] && [ "$4" = n/a ] && [ "$3" = "$_want_min" ] && return 0
  [ "$3" = "$_want_min" ] && [ "$4" = "$_want_sdk" ] && return 0
  echo "$1 records minos $3 sdk $4; the pin is minos $_want_min sdk $_want_sdk"; return 1
}

# platform: Sparkle 1.27.3 is prebuilt upstream against SDK 12.0 and embedded verbatim in every updater;
#           exempted by CONTENT, so only these exact bytes pass -- a patched or different Sparkle does not.
MAV_SDK_EXEMPT_SHA256='95ad6ce1558b1ffef550455bf9aa05ad6686d434279631d170ab92fb3747c93f
afc568f0d8d2a93eb9e59cda546cafab0a14cc60a4d78b4c611800d33ad5dced
4ea4718635b69a7746078674aba2af31249d20e3155010bd06f1e9d5487c94b2'
mav_sdk_exempt_sha256() { [ -n "$1" ] && printf '%s\n' "$MAV_SDK_EXEMPT_SHA256" | grep -qx "$1"; }
