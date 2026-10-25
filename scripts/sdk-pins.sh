# platform: host-agnostic
#   usage: . sdk-pins.sh     (sourced; defines the four functions below)
#          shipyard_sdk_pin <arch>                            "<url> <sha256> <tarball> <sdk-dir>"; 1 if unknown
#          shipyard_sdk_settings_json <arch>                  the SDKSettings.json fetch_sdk.sh adds; 1 if none
#          shipyard_sdk_rule <arch> <filetype> <minos> <sdk>  0 if compliant, else prints why and returns 1
#          shipyard_sdk_exempt_sha256 <sha256>                0 if the bytes are a pinned third-party file
# spec: claude-plugins/mavergreen/skills/mavergreen-conventions/SKILL.md "SDK pinning" -- the ONE place
#       the pins and the per-arch rule live; fetch_sdk.sh, assert_binary_compatible.sh and
#       check-artifact-conformance.sh all source it, so the three cannot disagree.

shipyard_sdk_pin() {
  case "$1" in
    x86_64) echo "https://github.com/phracker/MacOSX-SDKs/releases/download/11.3/MacOSX10.9.sdk.tar.xz fcf88ce8ff0dd3248b97f4eb81c7909f2cc786725de277f4d05a2b935cc49de0 MacOSX10.9.sdk.tar.xz MacOSX10.9.sdk" ;;
    # platform: phracker publishes no checksum; this one was recorded on first download (2026-09-24)
    #           and cross-checked against joseluisq/macosx-sdks 11.3, whose published sha256 verified:
    #           every .tbd and framework header in the two was identical.
    arm64)  echo "https://github.com/phracker/MacOSX-SDKs/releases/download/11.3/MacOSX11.3.sdk.tar.xz cd4f08a75577145b8f05245a2975f7c81401d75e9535dcffbb879ee1deefcbf4 MacOSX11.3.sdk.tar.xz MacOSX11.3.sdk" ;;
    *) return 1 ;;
  esac
}

shipyard_sdk_settings_json() {
  case "$1" in
    # platform: the 10.9 SDK ships only SDKSettings.plist, and swiftc takes the SDK version only from
    #           SDKSettings.json (clang::parseDarwinSDKInfo), so without one it links sdk n/a. LLVM 22's
    #           clang/lib/Basic/DarwinSDKInfo.cpp requires Version and MaximumDeploymentTarget, and a
    #           CanonicalName naming the platform when SupportedTargets is absent; the values are the
    #           plist's own.
    x86_64) echo '{"CanonicalName":"macosx10.9","MaximumDeploymentTarget":"10.9","Version":"10.9"}' ;;
    *) return 1 ;;
  esac
}

shipyard_sdk_rule() {  # $1 arch, $2 filetype, $3 minos, $4 sdk
  if [ "$2" = KEXTBUNDLE ]; then
    [ "$1" = x86_64 ] && return 0
    echo "a kext must be x86_64, not $1"; return 1
  fi
  case "$1" in
    x86_64) _want_min=10.9; _want_sdk=10.9 ;;
    arm64)  _want_min=11.0; _want_sdk=11.3 ;;
    *) echo "arch $1 has no pinned SDK (only x86_64 and arm64 do)"; return 1 ;;
  esac
  # platform: an object file (a static archive's member, x86_64 only) may record sdk "n/a" when
  #           compiled against a 10.9 SDK with no SDKSettings.json to read a version from (Apple ships
  #           none; fetch_sdk.sh adds one) -- so a member can prove its minos but not its SDK. The 11.3 arm64 SDK includes
  #           SDKSettings.json, so arm64 members must record their SDK version.
  [ "$1" = x86_64 ] && [ "$2" = OBJECT ] && [ "$4" = n/a ] && [ "$3" = "$_want_min" ] && return 0
  # platform: OS X 10.9's own clang (pre-Xcode 7) writes no version-min load command into a
  #           relocatable .o at all -- only into what it links -- so a static archive built natively on
  #           10.9 has members recording neither minos nor sdk, though every compile passed the pinned
  #           10.9 SDK and -mmacosx-version-min=10.9. Every modern toolchain writes one, so an x86_64
  #           member with no version load command can only come from a 10.9-era toolchain.
  [ "$1" = x86_64 ] && [ "$2" = OBJECT ] && [ "$3" = - ] && [ "$4" = - ] && return 0
  [ "$3" = "$_want_min" ] && [ "$4" = "$_want_sdk" ] && return 0
  echo "$1 records minos $3 sdk $4; the pin is minos $_want_min sdk $_want_sdk"; return 1
}

# platform: Sparkle 1.27.3 is prebuilt upstream against SDK 12.0 and embedded verbatim in every updater;
#           exempted by CONTENT, so only these exact bytes pass -- a patched or different Sparkle does not.
SHIPYARD_SDK_EXEMPT_SHA256='95ad6ce1558b1ffef550455bf9aa05ad6686d434279631d170ab92fb3747c93f
afc568f0d8d2a93eb9e59cda546cafab0a14cc60a4d78b4c611800d33ad5dced
4ea4718635b69a7746078674aba2af31249d20e3155010bd06f1e9d5487c94b2'
shipyard_sdk_exempt_sha256() { [ -n "$1" ] && printf '%s\n' "$SHIPYARD_SDK_EXEMPT_SHA256" | grep -qx "$1"; }
