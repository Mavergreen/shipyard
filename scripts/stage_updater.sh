#!/bin/sh
# platform: macOS-only -- PlistBuddy reads the updater bundle
#   usage: stage_updater.sh --stage ROOT --app UPDATER.app \
#            --app-dir "/Library/Application Support/Mavergreen" \
#            --agent-label dev.mavergreen.<product>-updatecheck \
#            [--scripts-out DIR] [--snippet-out FILE]
#          Stages a Sparkle updater .app + its daily-check LaunchAgent into a pkg payload root, and
#          emits the postinstall logic that loads the agent, rendered from the shared updater/*.in
#          templates so each product supplies only its label and paths.
#            --stage        payload root that pkgbuild --root will package
#            --app          the built updater .app (its basename minus .app is the executable name)
#            --app-dir      ABSOLUTE install dir for the .app; may contain spaces
#            --agent-label  LaunchAgent Label; the installed plist is <label>.plist
#            --scripts-out  dir to write a complete `postinstall` into (pass as --scripts to
#                           pkgbuild)
#            --snippet-out  file to write JUST the agent-load fragment into, for a product that
#                           already has its own postinstall to `.` it from
#          Both outputs are optional: pass whichever the product needs, or neither to stage payload
#          only. There is deliberately NO manual-trigger shim in /usr/local/bin: the agent checks
#          daily on its own, and a command nobody documented is a command nobody runs.
# spec: tests/stage_updater.sh
set -eu
SELF="$(cd "$(dirname "$0")" && pwd)"
TPL="$SELF/../updater"

STAGE=""; APP=""; APPDIR=""; LABEL=""; SCRIPTSOUT=""; SNIPPETOUT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --stage) STAGE="$2"; shift 2;;
    --app) APP="$2"; shift 2;;
    --app-dir) APPDIR="$2"; shift 2;;
    --agent-label) LABEL="$2"; shift 2;;
    --scripts-out) SCRIPTSOUT="$2"; shift 2;;
    --snippet-out) SNIPPETOUT="$2"; shift 2;;
    *) echo "stage_updater: unknown arg: $1" >&2; exit 2;;
  esac
done
[ -n "$STAGE" ] && [ -n "$APP" ] && [ -n "$APPDIR" ] && [ -n "$LABEL" ] \
  || { echo "stage_updater: need --stage --app --app-dir --agent-label" >&2; exit 2; }
[ -d "$APP" ] || { echo "stage_updater: no updater .app: $APP" >&2; exit 1; }
case "$APPDIR" in /*) ;; *) echo "stage_updater: --app-dir must be absolute: $APPDIR" >&2; exit 2;; esac
for t in updatecheck.plist.in agent-load.in; do
  [ -f "$TPL/$t" ] || { echo "stage_updater: missing template $TPL/$t" >&2; exit 1; }
done

appbase=$(basename "$APP")            # DockerUpdater.app
exec_name=${appbase%.app}             # DockerUpdater
installed_app="$APPDIR/$appbase"      # /Library/Application Support/Mavergreen/DockerUpdater.app
installed_exec="$installed_app/Contents/MacOS/$exec_name"

export COPYFILE_DISABLE=1             # no ._AppleDouble sidecars in the payload
mkdir -p "$STAGE$APPDIR" "$STAGE/Library/LaunchAgents"
rm -rf "$STAGE$APPDIR/$appbase"
cp -R "$APP" "$STAGE$APPDIR/"

# platform: `#` as the sed delimiter -- labels and abs paths never contain it.
sed -e "s#@MAVERICKS_AGENT_LABEL@#$LABEL#g" \
    -e "s#@MAVERICKS_UPDATER_INSTALLED_EXEC@#$installed_exec#g" \
    "$TPL/updatecheck.plist.in" > "$STAGE/Library/LaunchAgents/$LABEL.plist"

# platform: PlistBuddy reads binary and XML plists alike, on 10.9 and on the modern runner.
bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist" 2>/dev/null || true)"
render_agent_load() { sed -e "s#@MAVERICKS_AGENT_LABEL@#$LABEL#g" -e "s#@MAVERICKS_UPDATER_APP@#$appbase#g" \
                          -e "s#@MAVERICKS_UPDATER_BUNDLE_ID@#$bundle_id#g" "$TPL/agent-load.in"; }

if [ -n "$SNIPPETOUT" ]; then
  mkdir -p "$(dirname "$SNIPPETOUT")"
  render_agent_load > "$SNIPPETOUT"
fi

if [ -n "$SCRIPTSOUT" ]; then
  mkdir -p "$SCRIPTSOUT"
  { printf '#!/bin/sh\n# Rendered by stage_updater.sh from updater/agent-load.in -- do not edit here.\n'
    render_agent_load
    printf 'exit 0\n'
  } > "$SCRIPTSOUT/postinstall"
  chmod +x "$SCRIPTSOUT/postinstall"
fi

echo "stage_updater: $installed_app + /Library/LaunchAgents/$LABEL.plist" >&2
