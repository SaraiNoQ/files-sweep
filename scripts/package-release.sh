#!/bin/sh
set -eu
export LC_ALL=C
cd "$(dirname "$0")/.."
sh scripts/build-app.sh
bundle="$PWD/dist/FileSweep.app"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$bundle/Contents/Info.plist")"
staging="$(mktemp -d "$PWD/.build/release-package-XXXXXXXX")"
mounted=0
cleanup() {
    if [ "$mounted" -eq 1 ]; then hdiutil detach "$staging/mounted"; fi
    rm -rf "$staging"
}
trap cleanup EXIT
mkdir -p "$staging/contents" "$staging/mounted"
ditto "$bundle" "$staging/contents/FileSweep.app"
ln -s /Applications "$staging/contents/Applications"
cat > "$staging/contents/安装说明.txt" <<'TEXT'
FileSweep · macOS 13+ · Apple Silicon

将 FileSweep.app 拖到 Applications（应用程序），然后从应用程序中打开。
更新前请先退出旧版 FileSweep，再替换应用程序中的副本。

此版本为 ad-hoc 临时签名，尚未经过 Developer ID 签名或 Apple 公证。
macOS 可能阻止首次打开。请先确认下载来源；处理方式参见 Apple 官方说明：
https://support.apple.com/zh-cn/guide/mac-help/mh40616/mac

应用只读取所选目录的文件元数据，不读取文件正文、不删除文件、不上传数据。
逻辑大小和分配空间不等于实际可回收空间。
TEXT
image="FileSweep-$version-macos-arm64.dmg"
archive="FileSweep-$version-arm64.zip"
hdiutil create -volname FileSweep -srcfolder "$staging/contents" -format UDZO "$staging/output.dmg"
hdiutil verify "$staging/output.dmg"
hdiutil attach -readonly -nobrowse -mountpoint "$staging/mounted" "$staging/output.dmg"
mounted=1
codesign --verify --deep --strict "$staging/mounted/FileSweep.app"
cmp "$bundle/Contents/MacOS/FileSweep" "$staging/mounted/FileSweep.app/Contents/MacOS/FileSweep"
test "$(readlink "$staging/mounted/Applications")" = /Applications
test -f "$staging/mounted/安装说明.txt"
hdiutil detach "$staging/mounted"
mounted=0
ditto -c -k --sequesterRsrc --keepParent "$bundle" "$staging/output.zip"
unzip -tq "$staging/output.zip"
mv "$staging/output.dmg" "dist/$image"
mv "$staging/output.zip" "dist/$archive"
(cd dist && shasum -a 256 "$image" "$archive" > SHA256SUMS.txt)
printf '%s\n' "$PWD/dist/$image" "$PWD/dist/$archive" "$PWD/dist/SHA256SUMS.txt"
