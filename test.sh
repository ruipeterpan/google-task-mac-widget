#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
SWIFT_COMPILER="${TASKGLASS_SWIFTC:-/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc}"
SDK="${TASKGLASS_SDK:-/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk}"
if [[ ! -x "$SWIFT_COMPILER" ]]; then SWIFT_COMPILER="$(xcrun --find swiftc)"; SDK="$(xcrun --show-sdk-path)"; fi
TEST_ROOT="${TASKGLASS_TEST_ROOT:-$(mktemp -d /private/tmp/taskglass-tests.XXXXXX)}"
mkdir -p "$TEST_ROOT/modules"
"$SWIFT_COMPILER" -sdk "$SDK" -swift-version 5 -module-cache-path "$TEST_ROOT/modules" Sources/Core.swift Tests/main.swift -o "$TEST_ROOT/core-tests"
"$TEST_ROOT/core-tests"

"$SWIFT_COMPILER" -sdk "$SDK" -parse-as-library -swift-version 5 -module-cache-path "$TEST_ROOT/modules" Sources/Core.swift Sources/Auth.swift Tests/ListenerTests.swift -o "$TEST_ROOT/listener-tests"
"$TEST_ROOT/listener-tests"
