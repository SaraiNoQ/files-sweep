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
mkdir -p "$staging/contents" "$staging/mounted" "$staging/payload/Applications" "$staging/installer-resources"
ditto "$bundle" "$staging/payload/Applications/FileSweep.app"
cat > "$staging/contents/安装说明.txt" <<'TEXT'
FileSweep · macOS 13+ · Apple Silicon

双击 FileSweep 安装器，按系统安装步骤继续。
已安装到“应用程序”的旧版会被直接升级，无需先卸载。
如果旧版仍在运行，安装器会提示先退出再继续。
安装只替换 /Applications/FileSweep.app，保留设置、钥匙串密钥与扫描记录。
其他位置的手动副本不会自动移动或删除。

安装器尚未签名；应用为 ad-hoc 临时签名，尚未经过 Apple 公证。
macOS 可能阻止首次打开。请先确认下载来源；处理方式参见 Apple 官方说明：
https://support.apple.com/zh-cn/guide/mac-help/mh40616/mac

应用只读取所选目录的文件元数据，不读取文件正文、不删除文件。
扫描与规则分析在本机完成。AI 默认关闭；启用后点击“AI 辅助判断”，
会向你配置的服务发送脱敏线索，不包含原始路径、个人文件名或文件内容。
AI 请求可能产生费用，数据保留政策由该服务决定。
逻辑大小和分配空间不等于实际可回收空间。
TEXT
cp "$staging/contents/安装说明.txt" "$staging/installer-resources/welcome.txt"
pkgbuild --root "$staging/payload" --component-plist resources/installer-components.plist \
  --identifier dev.filesweep.mac.pkg --version "$version" --install-location / \
  "$staging/FileSweep-component.pkg"
installer="FileSweep-$version-macos-arm64.pkg"
productbuild --distribution resources/installer-distribution.xml --package-path "$staging" \
  --resources "$staging/installer-resources" "$staging/contents/$installer"
python3 scripts/check-installer.py "$staging/contents/$installer" "$bundle"
image="FileSweep-$version-macos-arm64.dmg"
archive="FileSweep-$version-arm64.zip"
hdiutil create -volname FileSweep -srcfolder "$staging/contents" -format UDZO "$staging/output.dmg"
hdiutil verify "$staging/output.dmg"
hdiutil attach -readonly -nobrowse -mountpoint "$staging/mounted" "$staging/output.dmg"
mounted=1
cmp "$staging/contents/$installer" "$staging/mounted/$installer"
test -f "$staging/mounted/安装说明.txt"
hdiutil detach "$staging/mounted"
mounted=0
ditto -c -k --sequesterRsrc --keepParent "$bundle" "$staging/output.zip"
unzip -tq "$staging/output.zip"
mv "$staging/output.dmg" "dist/$image"
mv "$staging/output.zip" "dist/$archive"
mv "$staging/contents/$installer" "dist/$installer"
(cd dist && shasum -a 256 "$installer" "$image" "$archive" > SHA256SUMS.txt)
printf '%s\n' "$PWD/dist/$installer" "$PWD/dist/$image" "$PWD/dist/$archive" "$PWD/dist/SHA256SUMS.txt"
