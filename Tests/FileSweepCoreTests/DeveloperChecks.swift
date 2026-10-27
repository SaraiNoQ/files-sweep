import Foundation
import Darwin
import FileSweepCore

extension ScanChecks {
    func testDeveloperRecognition() throws {
        try fixture { home in
            try makeFiles(home, [
                "python/pyproject.toml", "python/pkg/__pycache__/module.cpython-313.pyc",
                "python/.pytest_cache/v/cache/nodeids", "python/.venv/pyvenv.cfg", "python/.venv/bin/python",
                "python/.mypy_cache/3.13/state", "python/.ruff_cache/version/entry",
                "node/package.json", "node/package-lock.json", "node/node_modules/dependency/package.json",
                "node/.next/cache/data", "node/dist/server.js",
                "rust/Cargo.toml", "rust/target/debug/app", "rust/target/.rustc_info.json",
                "maven/pom.xml", "maven/target/classes/App.class",
                "gradle/build.gradle.kts", "gradle/build/libs/app.jar", "gradle/.gradle/8.0/state",
                "Library/Caches/go-build/00/a", "go/pkg/mod/cache/download/package.zip",
                "Library/Caches/pip/http-v2/entry", ".cache/uv/wheels-v5/package.whl",
                ".npm/_cacache/content-v2/file", ".cargo/registry/cache/index/package.crate",
                ".cargo/registry/src/index/lib.rs", ".m2/repository/local/app.jar", ".gradle/caches/modules-2/data",
                "Library/pnpm/store/v3/files/package"
            ])
            let snapshot = try FileScanner.scan(root: home)
            let report = DeveloperAnalyzer.analyze(snapshot, home: home)
            let rules = Set(report.findings.values.map(\.ruleID))
            assert(rules.isSuperset(of: ["python.bytecode", "python.environment", "python.pytest-cache", "python.mypy-cache", "python.ruff-cache", "node.dependencies", "node.next", "node.output-name", "rust.target", "java.maven-target", "java.gradle-build", "java.project-cache", "go.build-cache", "go.module-cache", "python.pip-cache", "python.uv-cache", "node.npm-cache", "rust.registry-cache", "rust.registry-source", "java.local-repository", "java.user-cache", "node.pnpm-store"]))
            assert(Set(report.findings.values.map(\.ecosystem)).count == 5)
            for rule in ["python.environment", "node.output-name", "go.module-cache", "java.local-repository", "node.pnpm-store", "rust.registry-source"] {
                assert(report.findings.values.first { $0.ruleID == rule }!.isProtected)
            }
            assert(report.findings.values.allSatisfy { !$0.evidence.isEmpty && !$0.cautions.isEmpty })
            assert(report.findings.values.allSatisfy { $0.cautions.contains { $0.contains("未核验") } })
            assert(report.logicalBytes <= snapshot.entries[0].logicalBytes)
        }
    }

    func testAmbiguousNamesAndSymlinkMarkers() throws {
        try fixture { root in
            try makeFiles(root, ["unknown/target/debug/file", "unknown/dist/app.js", "unknown/.venv/bin/python", "unknown/.mypy_cache/data", "unknown/.pytest_cache/data", "unknown/.gradle/data", "real-manifest", "node/node_modules/lib/file", "rust/Cargo.toml/not-a-file", "rust/target/debug/app"])
            try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("node/package.json"), withDestinationURL: root.appendingPathComponent("real-manifest"))
            let snapshot = try FileScanner.scan(root: root)
            assert(DeveloperAnalyzer.analyze(snapshot, home: root).findings.isEmpty)
        }
    }

    func testDeveloperProtectionPropagation() throws {
        try fixture { root in
            try makeFiles(root, [
                "rust/Cargo.toml", "rust/target/debug/app", "rust/target/private/identity.pem",
                "node/package.json", "node/node_modules/dependency/.git/config",
                "database/pom.xml", "database/target/classes/App.class", "database/target/runtime/state.db",
                "Client.app/Contents/project/package.json", "Client.app/Contents/project/node_modules/lib/index.js",
                "Library/Application Support/Tool/project/package.json", "Library/Application Support/Tool/project/node_modules/lib/index.js",
                "library/containers/Other/project/package.json", "library/containers/Other/project/node_modules/lib/index.js",
                "clean/Cargo.toml", "clean/target/debug/app", "clean/private.pem"
            ])
            let snapshot = try FileScanner.scan(root: root)
            let report = DeveloperAnalyzer.analyze(snapshot, home: root)
            for finding in report.findings.values {
                let path = snapshot.url(for: finding.id).path
                if path.contains("/clean/target") { assert(!finding.isProtected) }
                else { assert(finding.isProtected, path) }
            }
            assert(report.findings.count == 7)
        }
    }

    func testPartialScanProtectsCandidates() throws {
        try fixture { root in
            try makeFiles(root, ["rust/Cargo.toml", "rust/target/debug/app", "blocked/entry"])
            let path = root.appendingPathComponent("blocked").path
            chmod(path, 0)
            defer { chmod(path, 0o700) }
            let scan = try FileScanner.scan(root: root)
            let report = DeveloperAnalyzer.analyze(scan, home: root)
            assert(report.findings.count == 1)
            assert(report.findings.values.allSatisfy(\.isProtected))
            assert(report.findings.values.first!.protectionReasons.contains { $0.contains("不完整") })
        }
    }

    func testAnalysisNeverExpandsSnapshotScope() throws {
        try fixture { root in
            try makeFiles(root, ["Cargo.toml", "target/debug/app"])
            let limited = try FileScanner.scan(root: root.appendingPathComponent("target"))
            assert(DeveloperAnalyzer.analyze(limited, home: root).findings.isEmpty)
            let full = try FileScanner.scan(root: root)
            let before = DeveloperAnalyzer.analyze(full, home: root)
            try FileManager.default.moveItem(at: root.appendingPathComponent("Cargo.toml"), to: root.appendingPathComponent("moved.toml"))
            let after = DeveloperAnalyzer.analyze(full, home: root)
            assert(before.orderedIDs == after.orderedIDs)
            assert(after.findings.count == 1)
        }
    }

    func testDefaultPathsNeedStructureAndUserScope() throws {
        try fixture { home in
            try makeFiles(home, ["Library/Caches/go-build/personal.txt", ".cache/uv/personal.txt", "other/Library/Caches/pip/http-v2/file", "other/.npm/_cacache/content-v2/file"])
            let report = DeveloperAnalyzer.analyze(try FileScanner.scan(root: home), home: home)
            assert(report.findings.isEmpty)
        }
    }

    func testAmbiguousToolchainsAndNestedCandidates() throws {
        try fixture { root in
            try makeFiles(root, ["Cargo.toml", "pom.xml", "target/debug/app", "package.json", "node_modules/sub/package.json", "node_modules/sub/node_modules/lib/file"])
            let scan = try FileScanner.scan(root: root)
            let report = DeveloperAnalyzer.analyze(scan, home: root)
            assert(report.findings.count == 2)
            let rust = report.findings.values.first { $0.ecosystem == .rust }!
            assert(rust.isProtected)
            assert(rust.protectionReasons.contains { $0.contains("歧义") })
            assert(report.findings.values.filter { $0.ruleID == "node.dependencies" }.count == 1)
            assert(report.logicalBytes == report.orderedIDs.reduce(0) { $0 + scan.entries[$1].logicalBytes })
        }
    }

    private func makeFiles(_ root: URL, _ paths: [String]) throws {
        for path in paths {
            let url = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("fixture".utf8).write(to: url)
        }
    }
}
