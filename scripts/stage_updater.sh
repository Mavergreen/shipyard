#!/bin/sh
# platform: host-agnostic
#   usage: stage_updater.sh --stage ROOT --app APP --product P [--scripts-out DIR] [--snippet-out FILE]
#          Stages product P's Sparkle updater and its daily-check LaunchAgent into a pkg payload root,
#          and emits the postinstall logic that loads the agent, rendered from the shared updater/*.in
#          templates. Where the app goes, what it is called and the agent's label are P's, derived by
#          product-name.sh from shipyard's scripts/product-names; --app-dir and --agent-label are refused.
#            --stage        payload root that pkgbuild --root will package
#            --app          the built updater, P-updater.app (mavericks_add_updater_app(PRODUCT P))
#            --product      P, a registered short name
#            --scripts-out  dir to write a complete `postinstall` into (pass as --scripts to pkgbuild)
#            --snippet-out  file to write JUST the agent-load fragment into, for a postinstall to source
#          Both outputs are optional. There is deliberately NO manual-trigger shim in /usr/local/bin:
#          the agent checks daily on its own, and a command nobody documented is a command nobody runs.
# spec: tests/stage_updater.sh
set -eu
SELF="$(cd "$(dirname "$0")" && pwd)"
. "$SELF/registry-lookup.sh"
TPL="$SELF/../updater"

STAGE=""; APP=""; P=""; SCRIPTSOUT=""; SNIPPETOUT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --stage) STAGE="$2"; shift 2;;
    --app) APP="${2%/}"; shift 2;;
    --product) P="$2"; shift 2;;
    --scripts-out) SCRIPTSOUT="$2"; shift 2;;
    --snippet-out) SNIPPETOUT="$2"; shift 2;;
    --app-dir|--agent-label) echo "stage_updater: $1 is derived from shipyard's scripts/product-names; pass --product" >&2; exit 2;;
    *) echo "stage_updater: unknown arg: $1" >&2; exit 2;;
  esac
done
[ -n "$STAGE" ] && [ -n "$APP" ] && [ -n "$P" ] \
  || { echo "stage_updater: need --stage --app --product" >&2; exit 2; }
[ -d "$APP" ] || { echo "stage_updater: no updater .app: $APP" >&2; exit 1; }
registry_need stage_updater updater-app "$P"; REL="$REG_V"
registry_need stage_updater agent-label "$P"; LABEL="$REG_V"
APPDIR="/${REL%/*}"
appbase="${REL##*/}"
[ "${APP##*/}" = "$appbase" ] \
  || { echo "stage_updater: $P's updater is $appbase, built by mavericks_add_updater_app(PRODUCT $P); got ${APP##*/}" >&2; exit 2; }
for t in updatecheck.plist.in agent-load.in; do
  [ -f "$TPL/$t" ] || { echo "stage_updater: missing template $TPL/$t" >&2; exit 1; }
done

exec_name=${appbase%.app}
installed_app="$APPDIR/$appbase"
installed_exec="$installed_app/Contents/MacOS/$exec_name"

export COPYFILE_DISABLE=1
mkdir -p "$STAGE$APPDIR" "$STAGE/Library/LaunchAgents"
rm -rf "$STAGE$APPDIR/$appbase"
cp -R "$APP" "$STAGE$APPDIR/"

# platform: `#` as the sed delimiter -- labels and abs paths never contain it.
sed -e "s#@MAVERICKS_AGENT_LABEL@#$LABEL#g" \
    -e "s#@MAVERICKS_UPDATER_INSTALLED_EXEC@#$installed_exec#g" \
    "$TPL/updatecheck.plist.in" > "$STAGE/Library/LaunchAgents/$LABEL.plist"

render_agent_load() { sed -e "s#@MAVERICKS_AGENT_LABEL@#$LABEL#g" "$TPL/agent-load.in"; }

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
