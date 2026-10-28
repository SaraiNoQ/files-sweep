# FileSweep 应用图标

2026-10-29，按当前 UI 重新生成并替换。使用内置 ImageGen，保留文件夹与空间分块概念，改为纸色圆角底板、墨青文件夹、朱砂主分块与浅石色辅助分块；外部透明，无文字，保留玻璃高光与轻微立体边缘。完成一次透明边缘整理。

本轮完整生成与修整提示词：[prompt-2026-10-29.md](prompt-2026-10-29.md)。32 px 与 128 px 预览分别为 `preview-32.png`、`preview-128.png`。原生图标包经 iconutil 反解，核对全部 10 个位图尺寸与透明通道。

- `source.png`：生成原图，保留透明通道。
- `../../resources/AppIcon.icns`：macOS 图标，包含 16、32、128、256、512 pt 的 1× / 2× 位图，由系统 `sips` 缩放和 `iconutil` 打包。
- `../../scripts/build-app.sh`：将图标复制到应用 Resources，通过 `CFBundleIconFile` 注册，再签名发布。

## 旧版提示词（2026-10-27，仅供历史参考）

Use case: logo-brand. Asset type: production macOS app icon for FileSweep, a read-only disk usage explorer. Create one polished square 1024x1024 icon, front facing, on actual transparent background outside a rounded-square warm ivory tile. Tile occupies about 86% of canvas, with consistent generous transparent margins and a restrained soft shadow. Central symbol: a bold moss-green folder silhouette with a small tab, its front neatly divided into three or four large warm-paper and sage rectangular treemap compartments, suggesting readable disk space organization. The folder and compartments must form one simple memorable coherent emblem, readable at 32 pixels. Warm ivory #F8F6F0, muted moss #667859, darker olive #414D38, pale sage #DCE3D2. Refined macOS dimensional paper-cut relief, very subtle bevel, soft upper-left lighting, mostly flat broad surfaces, crisp silhouette. No text, letters, numbers, magnifier, broom, trash bin, sparkle, UI screenshot, mockup device, decorative background, or extra icons. Single icon only, centered, no perspective.
