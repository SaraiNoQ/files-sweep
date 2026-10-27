#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
label="${1:-after}"
case "$label" in before|after) ;; *) exit 2 ;; esac
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/swift-cache"
swift build --disable-sandbox --product FileSweep
mkdir -p design/qa/ui-performance
python3 - <<'PY'
from pathlib import Path
source=Path('Sources/FileSweep/WorkspaceView.swift').read_text()
old='@StateObject private var model = Workspace()'
assert source.count(old)==1
source=source.replace(old, '@StateObject private var model: Workspace')
source=source.replace('    var body: some View {', '    init(model: Workspace, radial: Bool) {\n        _model = StateObject(wrappedValue: model)\n        _radialMap = State(initialValue: radial)\n    }\n\n    var body: some View {',1)
Path('.build/rendering-workspace.swift').write_text(source)
PY
set --
for source in Sources/FileSweep/*.swift; do
  case "$source" in */FileSweepApp.swift|*/WorkspaceView.swift) ;; *) set -- "$@" "$source" ;; esac
done
swiftc -O -parse-as-library -swift-version 6 -I .build/debug/Modules -I Sources/CSQLite \
  "$@" .build/rendering-workspace.swift Tests/InteractionChecks/RenderingBenchmark.swift \
  .build/debug/FileSweepCore.build/*.o -lsqlite3 -o .build/rendering-benchmark
.build/rendering-benchmark "$label"
