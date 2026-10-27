---
name: FileSweep
description: 原生 macOS 磁盘空间查看器，赤墨 · 断流，无背景图
colors:
  paper: "#eeece5"
  ink: "#222a2c"
  secondary: "#62686a"
  cinnabar: "#a3322f"
  selection: "#e0e2da"
  gold: "#b99149"
  line: "rgb(34 42 44 / 12%)"
  map-teal: "#284750"
  map-charcoal: "#46413e"
  map-ochre: "#746249"
  map-slate: "#a7b3b6"
  map-stone: "#c3c3bb"
  light-text: "#ffffff"
typography:
  headline:
    fontFamily: "SF Pro, system"
    fontSize: "27pt"
    fontWeight: 600
  ring-title:
    fontFamily: "SF Pro, system"
    fontSize: "22pt"
    fontWeight: 600
  ring-center-size:
    fontFamily: "System serif"
    fontSize: "24pt"
    fontWeight: 400
  inspector-title:
    fontFamily: "SF Pro, system"
    fontSize: "24pt"
    fontWeight: 600
  app-title:
    fontFamily: "SF Pro, system"
    fontSize: "16pt"
    fontWeight: 600
  row:
    fontFamily: "SF Pro, system"
    fontSize: "14pt"
    fontWeight: 400
  body:
    fontFamily: "SF Pro, system"
    fontSize: "13pt"
    fontWeight: 400
  control:
    fontFamily: "SF Pro, system"
    fontSize: "13pt"
    fontWeight: 500
  label:
    fontFamily: "SF Pro, system"
    fontSize: "12pt"
    fontWeight: 500
  caption:
    fontFamily: "SF Pro, system"
    fontSize: "11pt"
    fontWeight: 400
  inspector-size:
    fontFamily: "System serif"
    fontSize: "34pt"
    fontWeight: 400
  map-size-large:
    fontFamily: "System serif"
    fontSize: "32pt"
    fontWeight: 400
rounded:
  selection: "5pt"
  control: "10pt"
  map-small: "5pt"
  map-large: "16pt"
  search: "12pt"
spacing:
  tight: "8pt"
  control: "12pt"
  section: "16pt"
  inset: "24pt"
components:
  paper-button:
    textColor: "{colors.ink}"
    typography: "{typography.control}"
    rounded: "{rounded.control}"
    height: "32pt"
    padding: "0 11pt"
  search:
    textColor: "{colors.ink}"
    typography: "{typography.body}"
    rounded: "{rounded.search}"
    width: "240pt"
    height: "34pt"
    padding: "0 12pt"
  paper-button-prominent:
    backgroundColor: "{colors.ink}"
    textColor: "{colors.paper}"
    typography: "{typography.control}"
    rounded: "{rounded.control}"
    height: "32pt"
    padding: "0 11pt"
  scope-selected:
    textColor: "{colors.ink}"
    typography: "{typography.control}"
    height: "30pt"
    padding: "0 6pt"
  outline-selected:
    backgroundColor: "{colors.selection}"
    textColor: "{colors.ink}"
    typography: "{typography.row}"
    rounded: "{rounded.selection}"
    height: "44pt"
  treemap-red:
    backgroundColor: "{colors.cinnabar}"
    textColor: "{colors.light-text}"
    rounded: "{rounded.map-small}"
---

# Design System: FileSweep

## Overview

**Creative North Star: "赤墨 · 断流"**

用户于 2026-10-27 选定 MagicPath 第一方案“赤墨 · 断流”，明确不使用背景图。原生实现以纸色、朱砂、墨色、金线和较大的衬线数字表达该方向，默认以左侧多层环图、右侧上详情下目录呈现；矩形模式保留原上下分层结构。执行依据为 design/native-crimson-brief.md；MagicPath 组件 465512388515491840，版本 465517883380867072。旧“层野”选择与另外两套概念仅保留为历史。

这是原生 SwiftUI/AppKit macOS 13+、Apple Silicon 应用。采用系统 SF 字体和 SF Symbols；紧凑原生工具栏与窗口控制同排，保留菜单、焦点和键盘行为。轻量色面和留白形成层次，界面文字只承担对象、数值、状态与必要风险。

**Key Characteristics:**

- 默认左侧多层环图，右侧详情在上、当前目录在下；“环图 / 矩形”可切回原矩形布局。
- 纸色与朱砂的六色地图；环图角度按逻辑大小分配，矩形面积明确标注非等比。
- 矩形使用原生按钮；环图绘制与原生事件输入分离，目录保留 AppKit 行复用。
- 布局解释关系，避免重复标签和操作教程。

## Colors

前置 token 对应 `PaperAppearance.swift` 的 sRGB 值；原生尺寸均以点计。颜色用于分组和交互，不承担删除安全结论。

### Primary

- **朱砂**（`cinnabar`）：工具栏「扫」印记、目录符号、集合下划线、搜索焦点与强调按钮悬停。
- **灰纸选中底**（`selection`）：目录选中行与可进入的地图分组，配墨色文字。
- **金线**（`gold`）：地图选中项的 3 点描边，矩形另有内缩 4 点的 1 点前景色描边；保留原填色。

### Neutral

- **纸色 / 墨色 / 灰墨**（`paper` / `ink` / `secondary`）：工作区背景、正文与次要信息；`line` 用于细分隔。
- **地图六色**：朱砂、墨青、炭灰、赭色配白字；浅石蓝、石灰配墨字。矩形按当前排序循环分配，环图的后代沿用顶层分支颜色（随深度使用 100% / 85% / 70% 不透明度；“其他”为 45%）。颜色不表示文件类别或可清理性；环形扇区内不放正文，名称与数值放在中心、图例和详情。
- 基础文字与填色的 10 组对比度均不低于 4.5:1，记录见 design/qa/native-crimson/contrast.txt；这不替代原生视觉与辅助功能检查。

**The Evidence Rule.** 保护状态必须有文字与符号；面积和颜色都不能代表可删除性。

## Typography

使用平台系统 SF 字体；符号使用 SF Symbols。类型 token 记录 Swift 点数，不是网页 CSS 像素。数字使用系统等宽数字特性；目录总量、较大地图容量和详情逻辑大小使用系统 serif 设计。名称与路径保留系统字形，不导入网页 Noto 字体。

- **Headline / Inspector title**：环图目录标题 22 点、矩形目录标题 27 点，详情名称 24 点；矩形目录大小为 25 点系统衬线，详情逻辑大小为 34 点。环图边长超过 380 点时中心名称/容量为 15/24 点，否则为 12/18 点，容量采用系统衬线。
- **App title**：页头产品名。
- **Row**：目录名称；目录使用 medium、普通文件使用 regular 字重。搜索结果路径用较小的系统文字（12 点）。
- **Body / Control**：证据、指标、搜索和按钮。
- **Label / Caption**：集合切换、保护状态、列头、路径与状态栏。
- 地图矩形宽度超过 240 点且高度超过 130 点时，名称与大小使用 16/32 点，大小为系统衬线；其余使用 13/14 点，均保留名称与大小。

**The Quiet Copy Rule.** 删除重复标题、泛泛说明和显而易见的操作提示；必要状态只在相关位置出现。

## Layout

最小内容区为 1000×620 点，默认窗口为 1240×820 点。顶部采用 unifiedCompact 原生工具栏，与红黄绿窗口控制同排；选择目录、扫描、自动更新、记录与搜索位于左侧，空间图样式切换独立位于窗口最右侧；工具栏不显示「扫」印记与产品名。内容区不再保留独立的 64 点页头或其分隔线，底部状态栏保持 34 点，内容水平留白为 24 点。

默认环图模式使用原生 `HSplitView`：左侧地图最小 500 点、理想 700 点宽；右侧最小 360 点、理想 420 点宽，内部 `VSplitView` 将详情置于上方（最小/理想高度 210/280 点）、当前目录置于下方（230/320 点）。分界可拖动。地图标题旁 124 点宽的原生分段选择器切换“环图 / 矩形”。

矩形模式保留全宽上层 Treemap、下层目录（57%）与详情（约 43%，含一条分隔线）。原生 `VSplitView` 调整上下高度：地图最小/理想高度 280/340 点，下层 230/320 点。模式切换不替换快照或扫描范围。

目录浏览、集合切换、搜索、加载与空结果共享相同表格容器。加载提示留在栏头，不卸载表格。目录行高 44 点；搜索结果行高 54 点以容纳必要的相对路径。大小列固定 104 点，数字右对齐；表格文档宽度按实际 clip 宽度减去系统 overlay 滚动条宽度计算，再扣除大小列得到名称列；关闭自动尺寸调整，由布局统一控制。使用 plain 表格样式、零单元格间距和预留的纵向滚动条槽，避免右侧遮挡，无横向滚动条。

地图不滚动。目录与详情仅使用标准 NSScroller 的 `.overlay` 模式，无自绘滑块。目录在挂入窗口与布局时保持 scroll view 和实际纵向滚动条为 overlay，并手动预留系统滚动条宽度，避免遮挡大小列。详情将 `TransparentScrollbars` 标记放在自身滚动内容内，仅通过 `enclosingScrollView` 设置所属 scroll view 及实际纵横滚动条为 overlay、关闭背景绘制；不遍历整窗，也不改全局偏好。详情单独滚动，目录的“进入目录”与 Finder 操作固定在滚动区外；普通文件仅显示 Finder 操作。路径显示根目录名起始的相对位置，最多两行、中部截断，完整路径可通过工具提示读取。

## Elevation & Depth

2026-10-28 用户确认：在原有纸色、朱砂、墨色和地图六色基础上，将玻璃质感与拟物动态扩展到整个应用。此约定覆盖原平面样式及仅切换控件使用玻璃的限制；不改变只读边界、布局结构和地图几何。

共享 `GlassSurface` 使用不透明纸色或既有强调色、方向高光和细边缘表达玻璃质感，避免嵌套实时模糊；不再为分区、按钮或地图叠加柔化投影。只有窗口工具栏保留系统 ultraThinMaterial（降低透明度时使用纸色）。增加对比度时加强轮廓。原生文件对话框和警告继续使用系统控件。

共享按钮保留 0.25 秒按压弹簧与轻微下沉，系统减少动态效果时停用位移与缩放。环图静态底图与局部高亮用两个 Canvas 分开绘制，底图按布局键复用；悬停与选择即时更新高亮，不动画整个环图。原生输入层与辅助功能动作保留，不改变地图角度、数据或命中区域。

只为主分区保留一个边界；详情底部操作按钮直接放在详情分区内，图例不加独立玻璃底。目录树背景透明，选中行使用无模糊投影的渐变；展开符号和名称列整体右移 12 点，固定大小列不变。状态更新不重复展开相同选择的祖先；可见区域跟踪对象由 AppKit 维护，滚动和批量刷新不添加动画。

## Shapes

行选中底为 9 点圆角，共享按钮为 10 点，搜索为 12 点；地图普通块为 5 点，超过 240×130 点的大块为 16 点。保护状态采用文字与盾牌符号，不加胶囊底。Treemap 色块内缩 2 点形成清晰间隙。环图从正上方顺时针绘制，内外半径按总半径的 0.32 + 层级×0.22 / 0.54 + 层级×0.22，扇区间以 1.5 点纸色描边分隔；中心返回区域直径为图边长的 29%。集合切换用下划线，不围成卡片。

## Components

### Paper button

系统按钮语义保留；默认使用共享玻璃表面，悬停上浮、按下轻微下沉并回弹。详情主按钮使用墨底纸色字，悬停或按下改为朱砂底。禁用时整体透明度 40%；图标按钮必须有辅助功能名称与工具提示。

### Search

固定尺寸搜索框，浅墨底，默认玻璃高光边缘。聚焦使用朱砂 1.5 点描边，非聚焦为 1 点。清除按钮只在有输入时出现，并具有“清除搜索”辅助功能名称。

### Scope navigation

“全部文件 / 开发产物”使用共享玻璃按钮与朱砂选中描边，选中文字加粗；控件高度 32 点，不增加重复栏标题。语言筛选仅在开发产物集合出现，保持栏头高度；选中集合提供原生 selected 辅助功能特征。

### Directory outline

AppKit `NSOutlineView` 保留行复用、惰性展开与按逻辑大小排序；单选与空间图、详情同步。层级缩进 18 点，文件夹采用 20 点实心 SF Symbol，图标与文字间距 10 点；未选中行以墨色 7% 透明度的半点细线分隔。双击目录进入，键盘上下键选择；增加对比度时给选中行补上朱砂描边。搜索结果用语言与相对项目路径区分同名目录。环图普通浏览的树根跟随当前焦点目录，选中扇区时展开必要祖先并滚动到对应行；矩形模式的树根仍为扫描根。进入环图分组后，右侧显示该组全部成员；有搜索或开发产物筛选时先限定组成员，再应用匹配与 500 项显示上限。普通搜索继续沿用原范围。

### Sunburst

默认多层环图按正逻辑大小绘制最多三层、180 个扇区，每组同级最多 24 个；同级按大小降序、同大小按索引排序，角度按同级大小比例分配。角宽不足一圈 0.8% 或超过容量的小项合并为“其他”，保留真实 memberIDs、合计大小与项数；目录扇区至少占一圈 1.6% 才向外展开。零大小项目留在目录树中；正大小链接仅使用自身元数据，不跟随链接或读取内容。同级角度比例不等于跨层面积比例。

环图是被动绘制，由单个持续存在的 AppKit 输入层处理事件；极坐标命中测试与绘制共用半径，避免重叠 SwiftUI 扇区按钮拦截点击。普通扇区单击同步目录与详情，目录双击进入，文件双击显示元数据预览。悬停在中心显示名称、大小与当前范围占比；中心点击先退上一级分组，再退父目录，扫描根处无返回动作。图例仅列前六个顶层分支，使用单击与“在目录中查看”辅助功能动作，不附加双击手势。

“其他”单击进入真实成员组成的分组；当前组超过容量两倍时采用均衡子组，容量内直接展开成员，局部返回栈支持“上一级分组 / 返回目录”。右侧未筛选列表保留全部成员；搜索先在组内匹配，再截取最多 500 项并显示总匹配数。同代次的过期标记和记录保存失败重试保留当前范围；焦点目录、快照代次或图样模式变化时清空分组范围。

输入层获得焦点后，方向键循环定位扇区并选择普通项；聚合项仅获得焦点，Enter 才进入。Enter 激活当前项，Backspace 返回；按住 Space 显示名称、大小、占比及路径等元数据，松开或 Escape 隐藏。双击文件的预览也可用 Escape 关闭。绘制与输入层不重复暴露辅助功能元素，单独提供每个扇区的语义按钮与激活动作。

布局在后台任务计算，以快照代次、焦点根与分组标识为任务键；取消令牌贯穿计算，旧键结果不展示。预览不读取文件内容、不启动扫描或网络请求。环图仅选择状态使用 0.12 秒 ease-out，减少动态效果时关闭；没有根目录过渡动画。

### Treemap

矩形地图只包含当前目录的直接子目录，以及严格大于 10 MiB（10×1024×1024 字节）的普通文件；等于阈值的文件、符号链接及其他类型不进入地图。目录不受该大小门槛限制。2026-10-28 按用户标注删除地图页脚说明；“矩形”按钮悬停提示保留文件筛选门槛与面积非等比信息，不再提供滚动放大条。

`Treemap.readableLayout` 按字节升序、从小到大分行，每个原始布局矩形至少 144×76 点（可见按钮宽高各减 4 点，形成间隙）。先锁定最小尺寸，再按字节权重分配剩余行高和列宽；有多行空间且最大项超过总量一半时，为其保留最后一行。该界面布局不等比；`Treemap.layout` 保留独立的等比面积 API。

当前目录全部符合条件的子项参与计算，不先截取 180 项。单次渲染最多 180 个原生 SwiftUI Button，且按可用几何容量进一步收紧。容量不足时合并最小前缀为可点击分组；组内适度溢出仍只合并最小前缀，让其余真实名称直接出现；仅当组内数量超过当前容量的两倍时使用均衡子组，避免巨大尾部逐项深入。`MapRegion` 保留原始绝对索引范围与字节合计；“上一级分组 / 返回目录”提供明确退路。

单项点击选中，目录双击进入；分组点击显示该子集。按钮提供名称、大小、提示和选中辅助功能特征；悬停或增加对比度时描边。数据按根目录与快照代次异步筛选、排序；布局按根目录、代次、分组范围和尺寸异步缓存，悬停不重排全部子项。目录树仍提供同一文件的键盘入口。

### Inspector and status

详情显示逻辑大小、分配空间、识别依据、保护原因及仍需确认的信息；已识别项目只使用“受保护 / 待核验”与对应盾牌符号，不生成安全评分；其他项目显示用途未确认。历史候选项沿用保护规则。底部持续显示统计状态与“逻辑大小不等于可回收空间”，读取问题按需展开。AI 入口仍收起，发送边界不在工作区重复铺陈。

详情选择采用 0.16 秒 ease-out 淡入，矩形地图按钮选中变化采用 0.12 秒、环图选中变化采用 0.12 秒 ease-out；`accessibilityReduceMotion` 开启时停用动画。没有用于扫描或路径数据的网络动画依赖。

## Do's and Don'ts

### Do:

- Do 使用系统 SF 字体、SF Symbols、原生菜单和可见键盘焦点。
- Do 让目录树提供空间图对应的键盘入口，搜索和空结果保持工作区几何。
- Do 区分逻辑大小、分配空间与统计不完整；保护状态同时使用文字与符号。
- Do 在详情滚动区外保留进入目录与 Finder 操作，显示相对路径并以工具提示提供完整路径。

### Don't:

- Don’t 恢复永久竖向三栏，或增加未经确认的布局配置层。
- Don’t 添加背景图片、纹理、玻璃内容背景、装饰阴影、外部字体或图标依赖。
- Don’t 用“安全可删”或可回收空间替代当前证据与逻辑大小。
- Don’t 把系统字体误记为 web/iOS 平台，也不要把预览 HTML 当作应用实现。

本轮 32 项核心检查及 `scripts/check-sunburst-input.sh` 的原生内存 NSEvent 事件测试、Workspace 分组搜索测试通过；最终 Release 包已独立签名、原子发布并通过严格签名验证。既有 10 组基础配色对比度记录继续有效。尚未进行真实用户窗口交互、视觉或 VoiceOver 验证，未使用 Computer Use，不声称截图验收；macOS 13 实机检查仍未完成。
