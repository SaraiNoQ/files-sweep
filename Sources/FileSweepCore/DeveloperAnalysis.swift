import Foundation

public enum DeveloperEcosystem: String, CaseIterable, Sendable {
    case python = "Python", node = "Node", rust = "Rust", go = "Go", java = "Java"
}

public enum ArtifactKind: String, Sendable {
    case cache = "缓存", build = "构建产物", dependencies = "依赖", environment = "运行环境", repository = "本地仓库"
}

public struct DeveloperFinding: Identifiable, Sendable {
    public var id: Int { entryID }
    public let entryID: Int
    public let ecosystem: DeveloperEcosystem
    public let kind: ArtifactKind
    public let title: String
    public let ruleID: String
    public var evidence: [String]
    public var protectionReasons: [String]
    public var cautions: [String]
    public let reference: URL
    public var isProtected: Bool { !protectionReasons.isEmpty }
}

public struct DeveloperReport: Sendable {
    public let findings: [Int: DeveloperFinding]
    public let orderedIDs: [Int]
    public let logicalBytes: UInt64
    public let elapsed: Double
    public let cancelled: Bool
    public var protectedCount: Int { findings.values.filter(\.isProtected).count }
}

private struct ProjectContext {
    var python: Int?
    var node: Int?
    var rust: Int?
    var maven: Int?
    var gradle: Int?
}

private struct GuardFlags: OptionSet {
    let rawValue: UInt8
    static let repository = Self(rawValue: 1)
    static let sensitive = Self(rawValue: 2)
    static let symlink = Self(rawValue: 4)
    static let incomplete = Self(rawValue: 8)
    static let app = Self(rawValue: 16)
}

public enum DeveloperAnalyzer {
    /// Uses only the existing snapshot. No file reads, subprocesses or extra scan roots.
    public static func analyze(
        _ snapshot: ScanSnapshot,
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        cancellation: ScanCancellation = ScanCancellation()
    ) -> DeveloperReport {
        let start = ProcessInfo.processInfo.systemUptime
        var proposals: [Int: DeveloperFinding] = [:]
        var contexts: [Int: ProjectContext] = [:]
        var insideArtifact = [Bool](repeating: false, count: snapshot.entries.count)
        var guards = [GuardFlags](repeating: [], count: snapshot.entries.count)
        let homePath = home.standardizedFileURL.path
        let candidateNames: Set<String> = ["__pycache__", ".pytest_cache", ".mypy_cache", ".ruff_cache", ".venv", "venv", "node_modules", ".next", "dist", "build", "target", ".gradle", "pip", "uv", "_cacache", "store", "cache", "src", "go-build", "mod", "caches", "repository", ".pnpm-store"]
        let markers: Set<String> = ["pyproject.toml", "requirements.txt", "setup.py", "setup.cfg", "Pipfile", "package.json", "package-lock.json", "pnpm-lock.yaml", "yarn.lock", "Cargo.toml", "Cargo.lock", "pom.xml", "build.gradle", "build.gradle.kts", "settings.gradle", "settings.gradle.kts", "pyvenv.cfg", "bin", "lib", "v", "cache", "debug", "release", ".rustc_info.json", ".rustc-info.json", "classes", "test-classes", "maven-status", "generated-sources", "libs", "tmp", "reports", "http", "http-v2", "wheels", "content-v2", "index-v5"]

        for entry in snapshot.entries {
            if entry.id % 256 == 0 && cancellation.isCancelled { break }
            let id = entry.id
            let lower = entry.name.lowercased()
            if lower == ".git" { guards[id].insert(.repository) }
            if sensitiveName(lower) { guards[id].insert(.sensitive) }
            if entry.kind == .symbolicLink { guards[id].insert(.symlink) }
            if entry.incomplete { guards[id].insert(.incomplete) }
            if lower.hasSuffix(".app") { guards[id].insert(.app) }
            insideArtifact[id] = entry.parent.map { insideArtifact[$0] || proposals[$0] != nil } ?? false
            guard entry.kind == .directory else { continue }

            let children = snapshot.children(of: id)
            var files: Set<String> = []
            var folders: Set<String> = []
            var bytecode = false
            var uvLayout = false
            var goLayout = false
            for childID in children {
                let child = snapshot.entries[childID]
                if markers.contains(child.name) {
                    if child.kind == .file { files.insert(child.name) }
                    if child.kind == .directory { folders.insert(child.name) }
                }
                if entry.name == "__pycache__", child.kind == .file, child.name.hasSuffix(".pyc") { bytecode = true }
                if child.kind == .directory {
                    if ["archive-v", "wheels-v", "sdists-v", "simple-v", "git-v"].contains(where: { child.name.hasPrefix($0) }) { uvLayout = true }
                    if child.name.count == 2 && child.name.allSatisfy({ $0.isHexDigit }) { goLayout = true }
                }
            }
            var project = entry.parent.flatMap { contexts[$0] } ?? ProjectContext()
            if !files.isDisjoint(with: ["pyproject.toml", "requirements.txt", "setup.py", "setup.cfg", "Pipfile"]) { project.python = id }
            if files.contains("package.json") { project.node = id }
            if files.contains("Cargo.toml") { project.rust = id }
            if files.contains("pom.xml") { project.maven = id }
            if !files.isDisjoint(with: ["build.gradle", "build.gradle.kts", "settings.gradle", "settings.gradle.kts"]) { project.gradle = id }
            contexts[id] = project
            guard candidateNames.contains(entry.name), !insideArtifact[id] else { continue }
            let parent = entry.parent
            let parentProject = parent.flatMap { contexts[$0] } ?? ProjectContext()
            let path = snapshot.url(for: id).standardizedFileURL.path
            let relativeHome = path.hasPrefix(homePath + "/") ? String(path.dropFirst(homePath.count + 1)) : nil
            let parentFiles: Set<String> = Set(parent.map { snapshot.children(of: $0).compactMap {
                let child = snapshot.entries[$0]
                return child.kind == .file && markers.contains(child.name) ? child.name : nil
            }} ?? [])

            func propose(_ ecosystem: DeveloperEcosystem, _ kind: ArtifactKind, _ title: String,
                         _ ruleID: String, _ evidence: [String], _ caution: String,
                         protected: [String] = []) {
                proposals[id] = DeveloperFinding(entryID: id, ecosystem: ecosystem, kind: kind,
                    title: title, ruleID: ruleID, evidence: evidence, protectionReasons: protected,
                    cautions: [caution, "使用状态与 Git 跟踪情况未核验。"], reference: reference(ecosystem, kind, ruleID))
            }

            switch entry.name {
            case "__pycache__" where bytecode:
                propose(.python, .cache, "Python 字节码缓存", "python.bytecode",
                        ["目录名为 __pycache__", "含 .pyc 普通文件"], "尚未确认对应源码仍存在，字节码可能是仅存副本。")
            case let name where [".pytest_cache", ".mypy_cache", ".ruff_cache"].contains(name) && parentProject.python != nil:
                let tool = name == ".pytest_cache" ? "pytest" : name == ".mypy_cache" ? "mypy" : "ruff"
                propose(.python, .cache, "\(tool) 缓存", "python.\(tool)-cache",
                        ["已扫描祖先中有 Python 项目标记", "目录名为 \(entry.name)"], "工具类型由名称推断，未验证内部格式或个人数据。")
            case let name where [".venv", "venv"].contains(name) && files.contains("pyvenv.cfg") && folders.contains("bin"):
                propose(.python, .environment, "Python 虚拟环境", "python.environment",
                        ["含 pyvenv.cfg 普通文件", "含 bin 目录"], "依赖、解释器与本地修改可能无法完整恢复。", protected: ["运行环境不作为普通缓存。"])
            case "node_modules" where parentFiles.contains("package.json"):
                var evidence = ["同级有 package.json 普通文件", "目录名为 node_modules"]
                if !parentFiles.isDisjoint(with: ["package-lock.json", "pnpm-lock.yaml", "yarn.lock"]) { evidence.append("同级有依赖锁文件（未读取内容）") }
                propose(.node, .dependencies, "Node 项目依赖", "node.dependencies", evidence,
                        "可能含手动修改或应用运行依赖；锁文件不保证仍可重新下载。")
            case ".next" where parentFiles.contains("package.json") && folders.contains("cache"):
                propose(.node, .build, "Next.js 构建目录", "node.next",
                        ["同级有 package.json 普通文件", ".next 内有 cache 目录"], "可能包含部署产物，缓存与最终产物未分离。")
            case "target" where parentFiles.contains("Cargo.toml") && (!folders.isDisjoint(with: ["debug", "release"]) || !files.isDisjoint(with: [".rustc_info.json", ".rustc-info.json"])):
                propose(.rust, .build, "Cargo 构建目录", "rust.target",
                        ["同级有 Cargo.toml 普通文件", "含 Cargo 常见编译结构"], "可能包含唯一的发布二进制；共享 target 与自定义配置未核验。")
                if parentFiles.contains("pom.xml") { proposals[id]?.protectionReasons.append("同级同时有 Rust 与 Maven 标记，目录归属有歧义。") }
            case "target" where parentFiles.contains("pom.xml") && !folders.isDisjoint(with: ["classes", "test-classes", "maven-status", "generated-sources"]):
                propose(.java, .build, "Maven 构建目录", "java.maven-target",
                        ["同级有 pom.xml 普通文件", "含 classes / maven-status 等构建结构"], "可能保留唯一的 JAR、报告或生成源码。")
                if parentFiles.contains("Cargo.toml") { proposals[id]?.protectionReasons.append("同级同时有 Rust 与 Maven 标记，目录归属有歧义。") }
            case "build" where parent != nil && parentProject.gradle == parent && !folders.isDisjoint(with: ["classes", "libs", "tmp", "reports"]):
                propose(.java, .build, "Gradle 构建目录", "java.gradle-build",
                        ["同级有 Gradle 项目标记", "含 classes / libs 等构建结构"], "可能含签名后的发布包、测试报告或唯一生成文件。")
            case ".gradle" where parent != nil && parentProject.gradle == parent:
                propose(.java, .cache, "Gradle 项目缓存", "java.project-cache",
                        ["同级有 Gradle 项目标记", "目录名为 .gradle"], "可能正在被 Gradle daemon 使用；未核验锁状态。")
            case let name where ["dist", "build"].contains(name) && parentFiles.contains("package.json"):
                propose(.node, .build, "待确认的 Node 输出目录", "node.output-name",
                        ["同级有 package.json 普通文件", "目录名为 \(entry.name)"], "未读取构建配置，无法确认它是否是输出目录。", protected: ["目录名有歧义，可能保存源码或唯一产物。"])
            default: break
            }

            // Global locations are recognized only when explicitly included in the snapshot.
            switch relativeHome {
            case "Library/Caches/pip", ".cache/pip":
                if !folders.isDisjoint(with: ["http", "http-v2", "wheels"]) {
                    propose(.python, .cache, "pip 下载缓存", "python.pip-cache", ["位于当前用户的 pip 默认缓存路径", "含 http / wheels 缓存结构"], "离线安装可能依赖这些文件；自定义缓存位置未探查。")
                }
            case ".cache/uv", "Library/Caches/uv":
                if uvLayout {
                    propose(.python, .cache, "uv 缓存候选", "python.uv-cache", ["位于当前用户的 uv 常见缓存路径", "含 uv 版本化缓存结构"], "未核验具体版本或链接模式；应由 uv 管理共享数据。")
                }
            case ".npm/_cacache":
                if folders.contains("content-v2") || folders.contains("index-v5") {
                    propose(.node, .cache, "npm 内容缓存", "node.npm-cache", ["位于 ~/.npm/_cacache", "含 npm 内容寻址结构"], "npm 缓存通常会自行维护；清理可能导致重新下载。")
                }
            case "Library/pnpm/store", ".local/share/pnpm/store", ".pnpm-store":
                propose(.node, .dependencies, "pnpm 共享 store", "node.pnpm-store", ["位于当前用户的 pnpm 常见 store 路径"], "多个项目可能共享内容，引用关系未核验。", protected: ["共享依赖库不作为独立项目缓存。"])
            case ".cargo/registry/cache":
                propose(.rust, .cache, "Cargo 下载归档", "rust.registry-cache", ["位于 ~/.cargo/registry/cache"], "包含离线构建所需的依赖归档；来源可用性未验证。")
            case ".cargo/registry/src":
                propose(.rust, .dependencies, "Cargo 依赖源码", "rust.registry-source", ["位于 ~/.cargo/registry/src"], "可能包含本地修改，不能当作纯下载缓存。", protected: ["依赖源码可能是唯一修改副本。"])
            case "Library/Caches/go-build", ".cache/go-build":
                if goLayout {
                    propose(.go, .cache, "Go 构建缓存", "go.build-cache", ["位于当前用户的 Go 默认构建缓存路径", "含两位十六进制分桶目录"], "自定义 GOCACHE 未解析；未确认当前是否被 Go 使用。")
                }
            case "go/pkg/mod":
                propose(.go, .dependencies, "Go 模块缓存", "go.module-cache", ["位于默认 GOPATH 的 pkg/mod"], "可包含解包源码、本地改动与离线依赖。", protected: ["共享模块源码未核验，不能当作构建缓存。"])
            case ".gradle/caches":
                propose(.java, .cache, "Gradle 用户缓存", "java.user-cache", ["位于 ~/.gradle/caches"], "跨版本缓存与多个项目共享，应由 Gradle 管理。", protected: ["共享缓存的引用与 daemon 状态未核验。"])
            case ".m2/repository":
                propose(.java, .repository, "Maven 本地仓库", "java.local-repository", ["位于 ~/.m2/repository"], "混合远程下载与本地 install 的构件；不能证明全部可重新下载。", protected: ["可能包含尚未发布的本地构件。"])
            default: break
            }
        }

        for entry in snapshot.entries.reversed() {
            if let parent = entry.parent { guards[parent].formUnion(guards[entry.id]) }
        }
        for id in Array(proposals.keys) {
            if snapshot.isHistorical { proposals[id]?.protectionReasons.append("历史扫描记录，当前文件状态尚未重新核验。") }
            if snapshot.isStale { proposals[id]?.protectionReasons.append("目录已经变化，当前状态等待重新核验。") }
            if isProtectedPath(snapshot.url(for: id).pathComponents) { proposals[id]?.protectionReasons.append("位于系统资源、应用数据、应用包或版本库管理目录内。") }
            if guards[id].contains(.repository) { proposals[id]?.protectionReasons.append("包含嵌套的 .git 标记，可能是独立仓库。") }
            if guards[id].contains(.sensitive) { proposals[id]?.protectionReasons.append("文件名提示可能含密钥、配置、数据库或个人数据。") }
            if guards[id].contains(.app) { proposals[id]?.protectionReasons.append("包含应用包，可能影响应用运行。") }
            if guards[id].contains(.incomplete) || !snapshot.isComplete || cancellation.isCancelled {
                proposals[id]?.protectionReasons.append("扫描不完整，无法排除未读区域中的重要数据。")
            }
            if guards[id].contains(.symlink) { proposals[id]?.cautions.append("含符号链接；链接目标未展开或验证。") }
        }

        var covered = [Bool](repeating: false, count: snapshot.entries.count)
        var total: UInt64 = 0
        for entry in snapshot.entries {
            let parentCovered = entry.parent.map { covered[$0] } ?? false
            let isFinding = proposals[entry.id] != nil
            covered[entry.id] = parentCovered || isFinding
            if isFinding && !parentCovered { total += entry.logicalBytes }
        }
        let ids = proposals.keys.sorted {
            let a = snapshot.entries[$0], b = snapshot.entries[$1]
            return a.logicalBytes == b.logicalBytes ? $0 < $1 : a.logicalBytes > b.logicalBytes
        }
        return DeveloperReport(findings: proposals, orderedIDs: ids, logicalBytes: total,
                               elapsed: ProcessInfo.processInfo.systemUptime - start, cancelled: cancellation.isCancelled)
    }

    private static func sensitiveName(_ name: String) -> Bool {
        if [".env", ".npmrc", ".pypirc", "credentials", "credentials.json", "settings.xml", "gradle.properties", "id_rsa", "id_ed25519"].contains(name) || name.hasPrefix(".env.") { return true }
        return [".pem", ".key", ".p12", ".pfx", ".jks", ".keystore", ".sqlite", ".sqlite3", ".db", ".parquet", ".csv", ".ipynb"].contains { name.hasSuffix($0) }
    }

    private static func isProtectedPath(_ parts: [String]) -> Bool {
        let parts = parts.map { $0.lowercased() }
        if parts.count > 1 && ["system", "bin", "sbin", "usr", "library", "applications"].contains(parts[1]) { return true }
        if parts.contains(where: { $0.hasSuffix(".app") || [".git", ".ssh", ".gnupg"].contains($0) }) { return true }
        return zip(parts, parts.dropFirst()).contains { a, b in
            a == "library" && ["application support", "containers", "group containers", "keychains", "mail", "messages"].contains(b)
        }
    }

    private static func reference(_ ecosystem: DeveloperEcosystem, _ kind: ArtifactKind, _ ruleID: String) -> URL {
        let address: String
        switch ecosystem {
        case .python:
            switch ruleID {
            case "python.environment": address = "https://docs.python.org/3/library/venv.html"
            case "python.bytecode": address = "https://docs.python.org/3/tutorial/modules.html#compiled-python-files"
            case "python.uv-cache": address = "https://docs.astral.sh/uv/concepts/cache/"
            case "python.pytest-cache": address = "https://docs.pytest.org/en/stable/how-to/cache.html"
            case "python.mypy-cache": address = "https://mypy.readthedocs.io/en/stable/command_line.html"
            case "python.ruff-cache": address = "https://docs.astral.sh/ruff/settings/#cache-dir"
            default: address = "https://pip.pypa.io/en/stable/topics/caching/"
            }
        case .node:
            switch ruleID {
            case "node.pnpm-store": address = "https://pnpm.io/cli/store"
            case "node.next": address = "https://nextjs.org/docs/app/guides/self-hosting"
            case "node.npm-cache": address = "https://docs.npmjs.com/cli/commands/npm-cache/"
            default: address = "https://docs.npmjs.com/cli/configuring-npm/package-json/"
            }
        case .rust: address = ruleID.hasPrefix("rust.registry") ? "https://doc.rust-lang.org/cargo/guide/cargo-home.html" : "https://doc.rust-lang.org/cargo/reference/build-cache.html"
        case .go: address = kind == .cache ? "https://pkg.go.dev/cmd/go#hdr-Build_and_test_caching" : "https://go.dev/ref/mod"
        case .java: address = kind == .repository ? "https://maven.apache.org/repositories/local.html" : ruleID == "java.maven-target" ? "https://maven.apache.org/guides/introduction/introduction-to-the-standard-directory-layout.html" : "https://docs.gradle.org/current/userguide/directory_layout.html"
        }
        return URL(string: address)!
    }
}
