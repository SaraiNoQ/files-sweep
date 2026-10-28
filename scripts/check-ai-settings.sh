#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/swift-cache"
swift build --disable-sandbox --product FileSweep
swiftc -parse-as-library -swift-version 6 -I .build/debug/Modules -I Sources/CSQLite \
  Sources/FileSweep/AISettings.swift Tests/InteractionChecks/AISettingsChecks.swift \
  .build/debug/FileSweepCore.build/*.o -lsqlite3 -o .build/ai-settings-checks
.build/ai-settings-checks
