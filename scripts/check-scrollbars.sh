#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/swift-cache"
swift build --disable-sandbox --product FileSweep
swiftc -parse-as-library -swift-version 6 Sources/FileSweep/PaperAppearance.swift \
  Tests/InteractionChecks/ScrollbarChecks.swift -o .build/scrollbar-checks
.build/scrollbar-checks
