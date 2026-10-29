#!/bin/zsh
set -euo pipefail
ROOT="${0:A:h:h}"
APP="${1:?Usage: package-dmg.sh /path/to/TaskGlass.app /path/to/output.dmg}"
OUTPUT="${2:?Specify the destination DMG path}"
[[ -d "$APP/Contents" ]] || { print -u2 'App bundle not found'; exit 1; }
codesign --verify --deep --strict "$APP"
STAGE="$(mktemp -d /private/tmp/taskglass-dmg.XXXXXX)"
trap 'rm -rf "$STAGE"' EXIT
# Stage only the app, an Applications link and generic installation instructions.
ditto --norsrc "$APP" "$STAGE/TaskGlass.app"
ln -s /Applications "$STAGE/Applications"
cp "$ROOT/INSTALL.txt" "$STAGE/Install TaskGlass.txt"
hdiutil create -volname TaskGlass -srcfolder "$STAGE" -format UDZO -ov "$OUTPUT"
hdiutil verify "$OUTPUT"
print "Created: $OUTPUT"
