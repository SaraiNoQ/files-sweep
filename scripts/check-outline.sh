#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/swift-cache"
swift build --disable-sandbox --product FileSweep
swiftc -parse-as-library -swift-version 6 -I .build/debug/Modules -I Sources/CSQLite \
  Sources/FileSweep/FileOutline.swift Sources/FileSweep/PaperAppearance.swift Sources/FileSweep/Workspace.swift \
  Sources/FileSweep/WorkspaceMonitoring.swift Tests/InteractionChecks/OutlineChecks.swift \
  .build/debug/FileSweepCore.build/*.o -lsqlite3 -o .build/outline-checks
.build/outline-checks
