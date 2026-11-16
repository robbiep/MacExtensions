#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."

if xcodebuild -version >/dev/null 2>&1; then
  swift test
else
  PLUGIN_DIR="/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing"
  swift test --enable-swift-testing --disable-xctest \
    -Xswiftc -plugin-path -Xswiftc "$PLUGIN_DIR"
fi
