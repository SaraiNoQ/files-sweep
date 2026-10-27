# 设计参考与本轮线框

检索日期：2026-10-25。获奖记录与当前产品界面分开看：获奖年份不代表今天每一个新增功能都获过奖。

| 参考 | 一手来源 | 迁移到 FileSweep 的模式 |
| --- | --- | --- |
| Things，Apple Design Award 2009 / 2017 | [官方获奖回顾](https://culturedcode.com/things/blog/2017/06/back-from-wwdc/)、[产品界面](https://culturedcode.com/things/) | 稳定列表位置、明确选择态、通过留白和字重组织信息；不靠反复解释功能 |
| Fantastical 2，Apple Design Award 2015 | [Apple 颁奖视频](https://developer.apple.com/videos/play/wwdc2015/103/)、[官方产品页](https://flexibits.com/fantastical) | 同一数据的列表与图形视图并置，选中项上下文连续；应用于目录与空间图联动 |
| Flighty，Apple Design Award 2023 Interaction | [Apple 获奖介绍](https://developer.apple.com/design/awards/2023/)、[Apple 设计访谈](https://developer.apple.com/news/?id=970ncww4) | 关键状态始终可见，复杂详情按需展开；应用于扫描完整性、异常与风险证据 |

以上为交互启发，不复制素材。访谈和产品网页已阅读；本机浏览器预览用于验证自制线框，不宣称已运行三款获奖应用。

## 用户确认

- 默认先看空间占用。
- 先低保真线框，共同选择布局。原生程序是功能验证壳，尚未确认最终视觉。
- UI/UX：Avoid unnecessary secondary labels and descriptions. Let the layout do the explaining.
- 不做满屏玻璃效果；后续在支持系统上由标准原生工具栏承载材质。文件区域保持清晰。

## 本轮方案

- A 并排：目录、Treemap、证据三栏。适合持续检查多个项目。
- B 空间图：扩大 Treemap，详情在底部。适合先找最大项。
- C 核查：宽目录列表，紧凑大小排序和证据栏。适合逐项排查；右侧概览明确不按面积编码。

`design/wireframes.html` 可切换三种布局、搜索演示项目、选择项目查看依据、切换空/扫描/部分结果状态，以及预览 AI 发送确认流程。全部数据为演示，无网络调用。

用户要求精简后：移除了布局说明、重复只读提示、树区教程、常规操作提示和大段解释；保留单处空间口径、异常提示，以及发送时的隐私边界。

## 用户评审

用户已认可精简后的线框。默认采用 A 并排布局；尚未确认高保真视觉、材质、窄窗口收起逻辑与细节密度。
