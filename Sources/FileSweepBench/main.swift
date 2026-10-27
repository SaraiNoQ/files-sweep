import Foundation
import FileSweepCore
import Darwin

do {
    let args = Array(CommandLine.arguments.dropFirst())
    guard args.count == 1 || (args.count == 3 && args[1] == "--archive") || (args.count == 2 && args[1] == "--incremental") else {
        fputs("Usage: filesweep-bench DIRECTORY [--archive OUTPUT.filesweep | --incremental]\n", stderr)
        exit(2)
    }
    let result = try FileScanner.scan(root: URL(fileURLWithPath: args[0]))
    let analysis = DeveloperAnalyzer.analyze(result)
    var usage = rusage()
    getrusage(RUSAGE_SELF, &usage)
    var report: [String: Any] = [
        "engine": "darwin-fts", "entries": result.entries.count,
        "seconds": result.elapsed, "peakRSSBytes": usage.ru_maxrss,
        "logicalBytes": result.entries.first?.logicalBytes ?? 0,
        "allocatedBytes": result.entries.first?.allocatedBytes ?? 0,
        "complete": result.isComplete, "issues": result.issueCount,
        "analysisSeconds": analysis.elapsed, "findings": analysis.findings.count,
        "protectedFindings": analysis.protectedCount,
        "finderMetadataEntries": result.entries.filter { $0.name == ".DS_Store" }.count
    ]
    if args.count == 3 {
        let url = URL(fileURLWithPath: args[2])
        let saving = ProcessInfo.processInfo.systemUptime
        try ScanArchive.save(result, to: url)
        report["archiveSaveSeconds"] = ProcessInfo.processInfo.systemUptime - saving
        let loading = ProcessInfo.processInfo.systemUptime
        let loaded = try ScanArchive.load(from: url)
        report["archiveLoadSeconds"] = ProcessInfo.processInfo.systemUptime - loading
        guard loaded.entries.count == result.entries.count, loaded.root == result.root,
              loaded.entries.first?.logicalBytes == result.entries.first?.logicalBytes,
              loaded.entries.first?.allocatedBytes == result.entries.first?.allocatedBytes,
              loaded.isHistorical else { throw ScanArchiveError.invalid }
        report["archiveRoundTripValid"] = true
        report["archiveBytes"] = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize
    }
    if args.count == 2 {
        let fixtureRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent(".bench-fixture")
        guard result.root.deletingLastPathComponent().standardizedFileURL == fixtureRoot.standardizedFileURL,
              ["100000", "1000000"].contains(result.root.lastPathComponent) else {
            throw ScanError.invalidRoot("增量基准只允许项目生成的测试样本。")
        }
        let directory = result.root.appendingPathComponent("project-0000")
        let file = directory.appendingPathComponent("filesweep-benchmark-\(UUID().uuidString).tmp")
        let identity = try ScanRootIdentity(root: result.root)
        try Data(repeating: 0, count: 64).write(to: file, options: .withoutOverwriting)
        defer { try? FileManager.default.removeItem(at: file) }
        let start = ProcessInfo.processInfo.systemUptime
        let update = try IncrementalScanner.refresh(result, dirtyDirectories: [directory], identity: identity)
        report["incrementalSeconds"] = ProcessInfo.processInfo.systemUptime - start
        report["rescannedDirectoryCount"] = update.rescannedDirectories.count
        let full = try FileScanner.scan(root: result.root)
        guard update.rescannedDirectories == [directory], update.snapshot.entries.count == full.entries.count,
              update.snapshot.entries[0].logicalBytes == full.entries[0].logicalBytes,
              update.snapshot.entries[0].allocatedBytes == full.entries[0].allocatedBytes else { throw ScanArchiveError.invalid }
        report["incrementalMatchesFullScan"] = true
    }
    getrusage(RUSAGE_SELF, &usage)
    report["peakRSSBytes"] = usage.ru_maxrss
    let data = try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys])
    print(String(decoding: data, as: UTF8.self))
    if !result.isComplete { exit(1) }
} catch {
    fputs("\(error.localizedDescription)\n", stderr)
    exit(1)
}
