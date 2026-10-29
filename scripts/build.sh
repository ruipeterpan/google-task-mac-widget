#!/bin/zsh
set -euo pipefail
ROOT="${0:A:h:h}"
: "${TASKGLASS_TEAM_ID:?Set TASKGLASS_TEAM_ID to your Apple signing team ID}"
SIGN_IDENTITY="${TASKGLASS_SIGN_IDENTITY:-Apple Development}"
BUILD_ROOT="${TASKGLASS_BUILD_ROOT:-$(mktemp -d /private/tmp/taskglass-release.XXXXXX)}"
# Xcode generates the App Intents metadata required by interactive widgets.
xcodebuild -project "$ROOT/TaskGlass.xcodeproj" -scheme TaskGlass \
  -configuration Release -derivedDataPath "$BUILD_ROOT" \
  DEVELOPMENT_TEAM="$TASKGLASS_TEAM_ID" CODE_SIGN_IDENTITY="$SIGN_IDENTITY" \
  ALWAYS_SEARCH_USER_PATHS=NO SWIFT_SERIALIZE_DEBUGGING_OPTIONS=NO \
  GCC_GENERATE_DEBUGGING_SYMBOLS=NO COPY_PHASE_STRIP=YES build
APP="$BUILD_ROOT/Build/Products/Release/TaskGlass.app"
codesign --verify --deep --strict "$APP"
print "Built app: $APP"
