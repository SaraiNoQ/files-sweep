# FileSweep 应用图标

2026-10-27，使用内置 imagegen 生成。暖纸圆角底板、苔绿文件夹和空间分块；外部透明，无文字。

- `source.png`：生成原图，保留透明通道。
- `../../resources/AppIcon.icns`：macOS 图标，包含 16、32、128、256、512 pt 的 1× / 2× 位图，由系统 `sips` 缩放和 `iconutil` 打包。
- `../../scripts/build-app.sh`：将图标复制到应用 Resources，通过 `CFBundleIconFile` 注册，再签名发布。

## 生成提示词

Use case: logo-brand. Asset type: production macOS app icon for FileSweep, a read-only disk usage explorer. Create one polished square 1024x1024 icon, front facing, on actual transparent background outside a rounded-square warm ivory tile. Tile occupies about 86% of canvas, with consistent generous transparent margins and a restrained soft shadow. Central symbol: a bold moss-green folder silhouette with a small tab, its front neatly divided into three or four large warm-paper and sage rectangular treemap compartments, suggesting readable disk space organization. The folder and compartments must form one simple memorable coherent emblem, readable at 32 pixels. Warm ivory #F8F6F0, muted moss #667859, darker olive #414D38, pale sage #DCE3D2. Refined macOS dimensional paper-cut relief, very subtle bevel, soft upper-left lighting, mostly flat broad surfaces, crisp silhouette. No text, letters, numbers, magnifier, broom, trash bin, sparkle, UI screenshot, mockup device, decorative background, or extra icons. Single icon only, centered, no perspective.
