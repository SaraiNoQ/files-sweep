---
name: FileSweep · 墨色三境（未批准概念）
description: 三个独立的武侠水墨交互方向，仅适用于本目录内的 MagicPath 演示。
colors:
  crimson-paper: "#eeece5"
  crimson-ink: "#222a2c"
  crimson-muted: "#62686a"
  crimson-accent: "#a3322f"
  crimson-gold: "#a48649"
  crimson-panel: "#f4f2eaef"
  jade-paper: "#e9ede0"
  jade-ink: "#183d37"
  jade-muted: "#53695f"
  jade-accent: "#215f53"
  jade-gold: "#b79a51"
  jade-panel: "#edf0e5"
  frost-paper: "#edf0f0"
  frost-ink: "#203641"
  frost-muted: "#5b6e78"
  frost-accent: "#365f78"
  frost-gold: "#ab915e"
  frost-panel: "#eef2f2"
  divider: "#2d363525"
  frost-second-tile: "#b2cbd6"
typography:
  display: {fontFamily: '"Noto Serif SC", "Songti SC", "STSong", serif', fontWeight: 600, lineHeight: 1.2}
  body: {fontFamily: '"Noto Sans SC", -apple-system, BlinkMacSystemFont, "PingFang SC", "Microsoft YaHei", sans-serif', fontSize: "14px", lineHeight: 1.45}
  numeric: {fontFamily: "Georgia, serif", fontSize: "37px", lineHeight: 1.1}
  label: {fontFamily: '"Noto Sans SC", system-ui', fontSize: "11px"}
rounded:
  controls: "0px"
spacing:
  tile-gap: "7px"
  folio-gap: "8px"
  workspace-gap: "24px"
  wide-gutter: "40px"
components:
  button-primary-crimson: {backgroundColor: "{colors.crimson-ink}", textColor: "{colors.crimson-paper}", rounded: "{rounded.controls}", height: "36px", padding: "0 12px"}
  button-primary-jade: {backgroundColor: "{colors.jade-ink}", textColor: "{colors.jade-paper}", rounded: "{rounded.controls}", height: "36px", padding: "0 12px"}
  button-primary-frost: {backgroundColor: "{colors.frost-ink}", textColor: "{colors.frost-paper}", rounded: "{rounded.controls}", height: "36px", padding: "0 12px"}
---
# FileSweep · 墨色三境

## Overview
**Creative North Star: "墨色三境"**
武侠水墨、流动绸带与山峦雾气构成三个并列的探索方向。数据区域保留清楚的名称、大小、选中态与保护状态；艺术背景提供气势，不承担信息编码。
这是未批准的 MagicPath 概念记录，不能作为原生 Swift 应用的最终设计规范。项目根目录的 DESIGN.md 与 PRODUCT.md 继续有效。
**Key Characteristics:**
- 赤墨·断流：朱砂与墨锋，斜向动势、矩形空间图。
- 青玉·回澜：玉色与金线，环形导航、两翼信息。
- 霜蓝·云阙：冷雾与山势，竖向卷页、展开选择。

## Colors
每个方向独立使用对应前缀的 paper / ink / muted / accent / gold / panel；不要混成第四套配色。paper 承托正文，ink 用于内容与主按钮，accent 标记交互，gold 描出选中边缘，divider 分隔信息。
图块分类颜色取自各方向 Data.ts 的 palettes；霜蓝第二图块采用 frost-second-tile 的浅底与深字覆盖，以保持可读性。它们区分类别，不表示可清理程度。

## Typography
Noto Serif SC 用于中文标题、印章与淡墨大字；Noto Sans SC 用于控件和正文，Georgia 用于主要容量数字，表格数字使用等宽数位。标题在宽桌面为赤墨 46px、青玉和霜蓝 40px；桌面高度不超过 900px 时统一降至 32px。
各概念 Fonts.css 内嵌 Noto Sans SC 400/600、Noto Serif SC 600 的 TrueType 字符子集（font-display: swap）；源文件为 artwork/chinese-0.ttf 至 chinese-2.ttf，申请字符见 font-request.txt，许可证见 notosanssc-LICENSE.txt 与 notoserifsc-LICENSE.txt。新增字符需扩展子集；系统字体承担未覆盖字符的回退。

## Layout
桌面工具栏 66px、状态栏 44px；宽度超过 760px 时窗口采用 100vh、最小高度 620px，目录与详情各自滚动。默认侧边距 40px，1100px 以下收至 26px；1500px 以上为 4%。
赤墨将空间图置于上方，目录与详情按 1.55:1 排在下方。青玉以图例、环形图、详情横排，下方整行目录。霜蓝以山景标题引出可展开卷页，下方沿用目录与详情。
桌面高度不超过 900px 时压缩标题、图形与间距。760px 以下为紧凑预览：工具栏换行，图块双列，详情下移；此断点不构成新增移动端产品承诺。

## Elevation & Depth
纸面与半透明墨色叠层为主。图块悬停上移 3px，阴影为 0 12px 28px #17252130；选择用金线。弹层用柔和阴影，正文始终落在稳定底色上。

## Shapes
控件以方角和细线为主。赤墨前两个大图块保留不对称圆角（20–30px），青玉使用双环与菱形图例，霜蓝使用顶部细金线的竖页；不推广为原生全局圆角体系。

## Components
空间图、列表、图例共享选择；双击或“进入目录”进入示例目录，面包屑与返回键回退。搜索、开发产物筛选与平铺切换作用于同一演示数据。环形弧长按逻辑大小；矩形和卷页面积设下限，明确标注非等比。
键盘支持 Tab、⌘/Ctrl+F、Escape，以及环形项的 Enter/Space。焦点使用 2px accent 外框、4px 偏移；选中与禁用状态通过语义属性表达。
动效包括赤墨 5s 刀光、0.7s 展卷、0.3s 详情显现与 0.18–0.5s 状态过渡；prefers-reduced-motion: reduce 时全部关闭动画和过渡，滚动恢复 auto。
根目录选择、扫描/取消、自动更新、历史保护、读取失败和跨卷跳过均为状态演示；Finder 按钮只显示说明。演示不访问文件系统、不执行删除、不发送 AI 请求；逻辑大小不等于可回收空间。

## Do's and Don'ts
- **Do** 保留明确的演示身份、范围限制、读取问题、取消状态与历史保护。
- **Do** 用布局解释层级，把风险文字留在对应决策处。
- **Don't** 将任一方向或本文件视为已批准的原生视觉方案。
- **Don't** 使用花卉图像、加入清理动作，或让水墨纹理遮挡文件名称和容量。
原画由内置 imagegen 根据用户提供的《王者荣耀·墨染江湖》参考图生成；准确提示词见 artwork/prompt-01.txt、prompt-02.txt、prompt-03.txt，各方向资产为 0N/assets/world.webp，随附 .json 记录来源。画面只取水墨、武侠、绸带与山势，不含花卉。
MagicPath 项目 465512338078961664；01 组件/最终版本：465512388515491840 / 465517883380867072；02：465512397818466304 / 465517906474713088；03：465512407113011200 / 465517928859725824。
检查记录：qa/results.json（交互），qa/final-layout.json（布局），qa/REVIEW.md（最终审查）；截图：qa/01-desktop.png 至 03-desktop.png，以及对应 01-compact.png 至 03-compact.png。截图与记录是概念验证材料，不代表原生实现验收。
