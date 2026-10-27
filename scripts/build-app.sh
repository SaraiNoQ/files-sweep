#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/swift-cache"
swift build --disable-sandbox -c release --product FileSweep
mkdir -p "$PWD/dist"
staging="$(mktemp -d "$PWD/dist/.previous-build-XXXXXXXX")"
bundle="$staging/FileSweep.app"
mkdir -p "$bundle/Contents/MacOS"
mkdir -p "$bundle/Contents/Resources"
cp .build/release/FileSweep "$bundle/Contents/MacOS/FileSweep"
cp resources/AppIcon.icns "$bundle/Contents/Resources/AppIcon.icns"
cat > "$bundle/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>FileSweep</string>
<key>CFBundleIdentifier</key><string>dev.filesweep.mac</string>
<key>CFBundleName</key><string>FileSweep</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.4.0</string>
<key>CFBundleVersion</key><string>4</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSArchitecturePriority</key><array><string>arm64</string></array>
<key>NSHighResolutionCapable</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>UTExportedTypeDeclarations</key><array><dict>
<key>UTTypeIdentifier</key><string>dev.filesweep.scan</string>
<key>UTTypeDescription</key><string>FileSweep 扫描记录</string>
<key>UTTypeConformsTo</key><array><string>public.database</string></array>
<key>UTTypeTagSpecification</key><dict>
<key>public.filename-extension</key><array><string>filesweep</string></array>
</dict>
</dict></array>
</dict></plist>
PLIST
codesign --force --sign - "$bundle"
codesign --verify "$bundle"
mv "$bundle" "$PWD/dist/$(basename "$staging").app"
rmdir "$staging"
python3 scripts/publish-app.py "$PWD/dist/$(basename "$staging").app" "$PWD/dist/FileSweep.app"
printf '%s\n' "$PWD/dist/FileSweep.app"
