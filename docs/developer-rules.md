# 开发缓存与产物探查 v0.2

识别只使用已扫描快照中的名称、对象类型、位置与父子关系。不会读取 manifest/锁文件正文、调用包管理器、执行项目脚本、读取环境配置或增加扫描目录。

识别结果是待核验对象，不是删除建议。未受保护不表示安全；所有项目均保留使用状态、Git 跟踪与可重建性未核验的提示。

## 首批 22 条规则

| 生态 | 对象 | 依据与边界 |
| --- | --- | --- |
| Python | `__pycache__` | 目录名与普通 `.pyc` 文件；明确警告可能只剩字节码 |
| Python | pytest / mypy / Ruff 缓存 | 已扫描祖先有 Python 项目标记 + 对应缓存名；没有验证内部格式 |
| Python | `.venv` / `venv` | 普通 `pyvenv.cfg` + `bin` 目录；作为运行环境受保护 |
| Python | pip 缓存 | 当前用户默认路径 + http / wheels 结构 |
| Python | uv 缓存 | 当前用户常见路径 + 版本化缓存结构；共享模式未验证 |
| Node | `node_modules` | 同级普通 `package.json`；有锁文件时额外显示其存在，不宣称可以完整恢复 |
| Node | `.next` | 同级普通 `package.json` + 内含 cache；提示可能包括部署产物 |
| Node | `dist` / `build` | 同级普通 `package.json`；仅名称线索，归属有歧义，受保护 |
| Node | npm `_cacache` | 用户默认路径 + 内容寻址结构 |
| Node | pnpm store | 用户常见位置；共享依赖库受保护 |
| Rust | `target` | 同级普通 `Cargo.toml` + debug / release 或 rustc 信息标记；警告唯一发布包与共享 target |
| Rust | registry/cache | 当前用户默认下载归档路径；离线依赖可用性未知 |
| Rust | registry/src | 当前用户默认依赖源码路径；本地修改风险，受保护 |
| Go | 构建缓存 | 当前用户默认位置 + 两位十六进制分桶结构 |
| Go | 模块缓存 | 默认 GOPATH 的 pkg/mod；可能包含本地修改与共享源码，受保护 |
| Java | Maven target | 同级普通 pom.xml + classes / test-classes / maven-status / generated-sources 结构 |
| Java | Gradle build | 同级 Gradle 项目标记 + classes / libs / tmp / reports 结构 |
| Java | 项目 `.gradle` | 同级 Gradle 项目标记；daemon / 锁状态未知 |
| Java | 用户 Gradle caches | 当前用户默认位置；共享缓存受保护 |
| Java | Maven 本地仓库 | 当前用户默认 `.m2/repository`；可能含未发布本地 install 构件，受保护 |

Python 三种工具缓存各为一条。规则名称匹配区分大小写，保护路径匹配忽略大小写；不同文件系统或工具自定义格式会遗漏，不能以“未识别”推断没有缓存。

## 保护优先

- 系统资源、应用包、应用数据、容器、Keychains、Mail/Messages、`.git` / `.ssh` / `.gnupg` 内的候选项受保护。
- 候选子树中存在嵌套 `.git` 标记、应用包，或密钥/数据库/配置/数据类文件名时受保护。只基于名称推断可能性，不声称读到了秘密或个人数据。
- 同级同时出现 Rust 与 Maven 项目标记，且目录为 target 时，归属歧义受保护。
- 扫描取消、读取失败、跨卷跳过等使扫描不完整时，候选项不能排除未读数据，均受保护。
- 符号链接不作为普通 manifest 依据，不沿其探查。候选内出现链接时显示目标未验证。
- 虚拟环境、共享依赖源码、Maven 本地仓库等本身具有保护理由。
- 候选嵌套于已识别产物内时不重复列出；识别占用总量按顶层候选去重。目录树和空间图仍保留完整扫描数据。

## 已知限制

未读取项目配置，所以不能解析自定义 CARGO_TARGET_DIR、GOCACHE、GOMODCACHE、GRADLE_USER_HOME、Maven repository、包管理器缓存位置或构建脚本。Go 不把任意 bin/build 目录当作产物；缺少项目上下文的 target/node_modules 也不强行归类。

未查询进程、锁、Git 跟踪状态、远程可下载性或源码对应关系，不以文件年龄判断可删。识别只反映本次扫描时刻，后续改动需要重新扫描。所有操作保持只读，LLM 接入延后。

## 一手参考

- [Python 字节码](https://docs.python.org/3/tutorial/modules.html#compiled-python-files)、[venv](https://docs.python.org/3/library/venv.html)、[pip](https://pip.pypa.io/en/stable/topics/caching/)、[uv](https://docs.astral.sh/uv/concepts/cache/)
- [pytest cache](https://docs.pytest.org/en/stable/how-to/cache.html)、[mypy](https://mypy.readthedocs.io/en/stable/command_line.html)、[Ruff](https://docs.astral.sh/ruff/settings/#cache-dir)
- [npm cache](https://docs.npmjs.com/cli/commands/npm-cache/)、[pnpm store](https://pnpm.io/cli/store)、[Next.js 自托管与缓存](https://nextjs.org/docs/app/guides/self-hosting)
- [Cargo 构建布局](https://doc.rust-lang.org/cargo/reference/build-cache.html)、[Cargo Home](https://doc.rust-lang.org/cargo/guide/cargo-home.html)
- [Go 构建缓存](https://pkg.go.dev/cmd/go#hdr-Build_and_test_caching)、[Go 模块缓存](https://go.dev/ref/mod)
- [Gradle 目录](https://docs.gradle.org/current/userguide/directory_layout.html)、[Maven 本地仓库](https://maven.apache.org/repositories/local.html)、[Maven 构建布局](https://maven.apache.org/guides/introduction/introduction-to-the-standard-directory-layout.html)
