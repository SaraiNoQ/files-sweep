# FileSweep

macOS 13+ / Apple Silicon 原生只读文件探查工具。扫描、文件名搜索、目录树、环图、Treemap、Finder 定位，以及 Python、Node、Rust、Go、Java 的开发产物探查。没有删除、提权或网络上传能力。

## 下载与安装

从 [GitHub Releases](https://github.com/SaraiNoQ/files-sweep/releases/latest) 下载 `FileSweep-0.4.0-macos-arm64.dmg`，打开后将 `FileSweep.app` 拖入 `Applications`。更新前请先退出旧版应用。也提供 ZIP 压缩包与 SHA-256 校验文件。

当前发布包为 ad-hoc 临时签名，**尚未经过 Developer ID 签名或 Apple 公证**。macOS 可能阻止首次打开；请先核对下载来源，再参考 [Apple 官方说明](https://support.apple.com/zh-cn/guide/mac-help/mh40616/mac)。不支持 Intel Mac。

## 打开应用

本轮 v0.4 构建位于 `dist/FileSweep.app`。选择目录后默认自动监听变化并重扫相关子目录，可在页头暂停/恢复；恢复时补齐暂停期间的变化。根目录移动或被替换时停止并提示重新选择。目录树、空间图和详情共享同一快照；“开发产物”支持语言与名称筛选。LLM 接入延后。

工具栏“扫描记录”或 File 菜单可保存/打开 `.filesweep` 记录；⌘S 保存、⇧⌘O 打开。记录包含文件名、路径和大小，请自行选择保存位置。打开后明确显示历史时间；需要获取当前状态时点“重新扫描”。

当前版本为 v0.4.0，包含玻璃质感控件、环图分组浏览、目录树与界面重绘优化；签名状态见上方安装说明。

开发构建采用独立签名与原子包替换，避免原地覆盖造成签名失效闪退。`dist/.previous-build-*.app` 保留旧包供仍运行的进程使用，不要在旧进程运行时改写它。重新打开应用可加载最新构建。

## 构建

需要 Swift 6 / Apple Silicon / Command Line Tools 或 Xcode：

```sh
sh scripts/build-app.sh
```

生成 DMG、ZIP 和 SHA-256 校验文件：

```sh
sh scripts/package-release.sh
```

打包脚本会验证 DMG、只读挂载后核对内含应用与签名，再输出到 `dist/`。默认使用 ad-hoc 签名，不代表通过 Apple 公证。

## 核心检查

```sh
CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache" \
SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/swift-cache" \
swift run --disable-sandbox filesweep-checks
```

使用 Debug 运行，不能加 `-c release`（assert 会被优化掉）。当前环境的 SwiftPM 用户缓存不可写警告不影响构建；模块缓存定向到本项目。

文件事件检查需要连接 macOS FSEvents 服务，在禁止连接系统服务的受限执行环境中会明确失败。检查只监听自建临时目录。发布检查：`python3 scripts/check-publish.py`。

## 可复现基准

```sh
CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache" \
SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/swift-cache" \
swift build --disable-sandbox -c release --product filesweep-bench
python3 scripts/benchmark.py --files 100000
python3 scripts/benchmark.py --files 1000000
```

脚本只在项目 `.bench-fixture` 新建样本，拒绝覆盖不完整的既有目录。不扫描个人文件。结果写入 `docs/benchmark-*.json`，保留每轮数据与和系统 du 的对照。

## 文档

- [性能与已知边界](docs/performance.md)
- [可交互线框](design/wireframes.html)
- [获奖产品参考与设计评审](docs/design-research.md)
- [AI 数据边界](docs/ai-explanation.md)
- [开发产物规则与保护边界](docs/developer-rules.md)
- [扫描记录格式与限制](docs/scan-archives.md)
- [自动增量扫描](docs/incremental-scanning.md)
- [闪退分析与修复](docs/crash-analysis.md)
- [设计约定](DESIGN.md)
- [持续开发约束](AGENTS.md)

## 范围

仅元数据扫描，不通过读取文件正文判断风险。扫描错误、取消与跨卷跳过会使结果标为不完整。逻辑大小、分配空间和实际可回收空间不同。当前 22 条规则识别已知位置和结构；“待核验”不表示可以安全删除。个人数据内容识别、自定义工具配置解析、跨启动自动索引恢复和真实 API 接入尚未实现。
