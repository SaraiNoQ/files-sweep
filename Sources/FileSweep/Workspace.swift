import AppKit
import SwiftUI
import FileSweepCore
import UniformTypeIdentifiers

func formatBytes(_ count: UInt64) -> String {
    if count == 0 { return "0 B" }
    return ByteCountFormatter.string(fromByteCount: Int64(clamping: count), countStyle: .binary)
}

@MainActor
final class Workspace: ObservableObject {
    private static let archiveType = UTType(exportedAs: "dev.filesweep.scan", conformingTo: .database)
    @Published var snapshot: ScanSnapshot? {
        didSet {
            guard let session = explanationSession,
                  snapshot?.generation != oldValue?.generation || snapshot?.isStale != oldValue?.isStale else { return }
            guard let snapshot, let oldValue, snapshot.root == oldValue.root,
                  snapshot.entries.first?.device == oldValue.entries.first?.device,
                  snapshot.entries.first?.inode == oldValue.entries.first?.inode,
                  session.matchesSelection(snapshot: snapshot, entryID: snapshot.generation == session.sourceGeneration
                    ? session.sourceEntryID : snapshot.entryID(at: session.sourceURL)) else {
                session.invalidate(); return
            }
            session.noteSnapshotChanged()
        }
    }
    @Published var developerReport: DeveloperReport?
    @Published var developerOnly = false
    @Published var ecosystem: DeveloperEcosystem?
    @Published var analyzing = false
    @Published var selectedID: Int? {
        didSet {
            guard let session = explanationSession else { return }
            guard let snapshot, session.matchesSelection(snapshot: snapshot, entryID: selectedID) else {
                session.invalidate(); return
            }
        }
    }
    @Published var explanationSession: ExplanationSession?
    @Published var focusID = 0
    @Published var query = ""
    @Published var searchResults: [Int]?
    @Published var matchCount = 0
    @Published var protectedMatchCount = 0
    @Published var status = "选择一个文件夹开始。扫描只读取元数据。"
    @Published var scanning = false
    @Published var searching = false
    @Published var revision = 0
    @Published var error: String?
    @Published var transferring = false
    @Published var monitoring = false
    @Published var updating = false
    var isBusy: Bool { scanning || transferring || updating }
    var wantsMonitoring = false
    var monitor: DirectoryMonitor?
    var rootIdentity: ScanRootIdentity?
    var monitorRoot: URL?
    var sessionID = UUID()
    var monitorID = UUID()
    var pendingDirectories: Set<URL> = []
    var pendingFullScan = false
    var firstPendingTime: Double?
    var updateTask: Task<Void, Never>?
    var debounceTask: Task<Void, Never>?
    var updateCancellation = ScanCancellation()
    var scanTask: Task<Void, Never>?
    var cancellation = ScanCancellation()
    private var searchTask: Task<Void, Never>?
    private var searchCancellation = ScanCancellation()
    private var activeSearchScope: (generation: UUID, ids: [Int])?

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "只读扫描"
        panel.message = "仅扫描选中的目录，不读取文件正文，不删除文件。"
        if panel.runModal() == .OK, let url = panel.url { scan(url) }
    }

    func scan(_ root: URL) {
        guard !isBusy else { return }
        explanationSession?.invalidate()
        stopMonitoring()
        rootIdentity = try? ScanRootIdentity(root: root)
        sessionID = UUID()
        let session = sessionID
        searchTask?.cancel(); searchCancellation.cancel()
        cancellation = ScanCancellation()
        let token = cancellation
        scanning = true; error = nil; query = ""; searchResults = nil
        developerReport = nil; analyzing = false; searching = false
        snapshot = nil; selectedID = nil; focusID = 0; revision += 1
        status = "正在读取目录…"
        var watchError: String?
        if wantsMonitoring {
            do { try startMonitoring(root) }
            catch { watchError = error.localizedDescription }
        }
        let reportProgress: @Sendable (ScanProgress) -> Void = { [weak self] progress in
            guard let self else { return }
            Task { @MainActor [weak self] in
                guard let self, self.sessionID == session, self.scanning, !self.analyzing else { return }
                self.status = "已发现 \(progress.entryCount.formatted()) 项 · \(progress.elapsed.formatted(.number.precision(.fractionLength(1)))) 秒"
            }
        }
        scanTask = Task { [weak self] in
            do {
                var result = try await Task.detached(priority: .utility) {
                    try FileScanner.scan(root: root, cancellation: token, progress: reportProgress)
                }.value
                guard let self, self.sessionID == session, !Task.isCancelled else { return }
                if let identity = self.rootIdentity, try ScanRootIdentity(root: root) != identity {
                    throw ScanError.failed("扫描根目录已被移动或替换，请重新选择。")
                }
                result.isStale = !self.pendingDirectories.isEmpty || self.pendingFullScan
                self.snapshot = result
                self.analyzing = true; self.status = "正在识别开发产物…"
                let captured = result
                let report = await Task.detached(priority: .utility) {
                    DeveloperAnalyzer.analyze(captured, cancellation: token)
                }.value
                guard self.sessionID == session, !Task.isCancelled else { return }
                result.isStale = !self.pendingDirectories.isEmpty || self.pendingFullScan || report.cancelled
                self.snapshot = result; self.developerReport = report
                self.analyzing = false; self.scanning = false
                if !result.isComplete || report.cancelled { self.stopMonitoring() }
                self.selectedID = result.entries.isEmpty ? nil : 0
                self.status = "\(result.cancelled || report.cancelled ? "已停止 · 部分结果" : result.isComplete ? "扫描完成" : "扫描不完整") · \(result.entries.count.formatted()) 项 · \(result.elapsed.formatted(.number.precision(.fractionLength(2)))) 秒"
                if let watchError { self.status += " · 自动更新不可用：" + watchError }
                if !result.isComplete && !result.cancelled { self.status += " · 自动更新已暂停" }
                self.revision += 1; self.search()
                self.scheduleUpdate()
            } catch {
                guard let self, self.sessionID == session else { return }
                self.stopMonitoring(); self.error = error.localizedDescription
                self.status = "扫描未完成"; self.scanning = false; self.analyzing = false
            }
        }
    }

    func stop() {
        wantsMonitoring = false
        cancellation.cancel()
        stopMonitoring()
        markStale()
        status = scanning ? "正在停止…" : "自动更新已暂停"
    }

    func shutdown() {
        explanationSession?.invalidate(); explanationSession = nil
        sessionID = UUID()
        cancellation.cancel(); scanTask?.cancel()
        searchTask?.cancel(); searchCancellation.cancel(); searching = false
        activeSearchScope = nil
        stopMonitoring()
    }

    func search() {
        search(scope: activeSearchScope?.generation == snapshot?.generation ? activeSearchScope?.ids : nil)
    }

    func search(scope: [Int]?) {
        searchTask?.cancel()
        searchCancellation.cancel()
        searchCancellation = ScanCancellation()
        let token = searchCancellation
        guard let snapshot else { return }
        activeSearchScope = scope.map { (snapshot.generation, $0) }
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let report = developerReport
        let developerOnly = developerOnly
        let ecosystem = ecosystem
        guard !text.isEmpty || developerOnly else {
            searchResults = scope?.filter { snapshot.entries.indices.contains($0) }
            matchCount = searchResults?.count ?? 0
            searching = false; revision += 1; return
        }
        searching = true
        searchTask = Task {
            if !text.isEmpty {
                do { try await Task.sleep(for: .milliseconds(180)) } catch { return }
            }
            let result = await Task.detached(priority: .userInitiated) {
                var matches: [Int] = []
                var count = 0
                var protectedCount = 0
                let ids = scope ?? (developerOnly ? (report?.orderedIDs ?? []) : nil)
                for offset in 0..<(ids?.count ?? snapshot.entries.count) {
                    if offset % 256 == 0 && token.isCancelled { break }
                    let id = ids?[offset] ?? offset
                    guard snapshot.entries.indices.contains(id) else { continue }
                    let entry = snapshot.entries[id]
                    if developerOnly && report?.findings[id] == nil { continue }
                    if developerOnly, let ecosystem, report?.findings[id]?.ecosystem != ecosystem { continue }
                    if text.isEmpty || entry.name.localizedStandardContains(text) {
                        count += 1
                        if report?.findings[id] != nil && (snapshot.isStale || report?.findings[id]?.isProtected == true) { protectedCount += 1 }
                        if matches.count < 500 { matches.append(entry.id) }
                    }
                }
                return (matches, count, protectedCount)
            }.value
            guard !Task.isCancelled, self.snapshot?.generation == snapshot.generation, self.snapshot?.isStale == snapshot.isStale else { return }
            searchResults = result.0; matchCount = result.1
            protectedMatchCount = result.2
            if developerOnly && !result.0.contains(selectedID ?? -1) { selectedID = result.0.first }
            searching = false; revision += 1
        }
    }

    func openDirectory(_ id: Int) {
        guard let snapshot, snapshot.entries.indices.contains(id), snapshot.entries[id].kind == .directory else { return }
        activeSearchScope = nil
        focusID = id; selectedID = id
    }

    func reveal() {
        guard let snapshot, let id = selectedID, snapshot.entries.indices.contains(id) else { return }
        let url = snapshot.url(for: id)
        guard FileManager.default.fileExists(atPath: url.path) else {
            error = "该项目已移动或不再可访问，请重新扫描。"; return
        }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func saveArchive() {
        guard !isBusy, let snapshot, !snapshot.entries.isEmpty else { return }
        let panel = NSSavePanel()
        panel.title = "保存扫描"
        panel.message = "记录包含本次扫描的文件名、路径与大小，不包含文件内容。"
        panel.allowedContentTypes = [Self.archiveType]
        panel.nameFieldStringValue = snapshot.root.lastPathComponent + ".filesweep"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let previousStatus = status
        transferring = true; status = "正在保存扫描…"
        Task {
            do {
                try await Task.detached(priority: .utility) { try ScanArchive.save(snapshot, to: url) }.value
                status = previousStatus
            } catch { self.error = error.localizedDescription; status = previousStatus }
            transferring = false
            scheduleUpdate()
        }
    }

    func openArchive() {
        guard !isBusy else { return }
        let panel = NSOpenPanel()
        panel.title = "打开扫描记录"
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [Self.archiveType]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let previousStatus = status
        let resumeMonitoring = monitoring
        explanationSession?.invalidate()
        stopMonitoring(); markStale(); sessionID = UUID()
        searchTask?.cancel(); searchCancellation.cancel()
        transferring = true; status = "正在读取扫描记录…"
        Task {
            do {
                let result = try await Task.detached(priority: .utility) {
                    let loaded = try ScanArchive.load(from: url)
                    return (loaded, DeveloperAnalyzer.analyze(loaded))
                }.value
                snapshot = result.0; developerReport = result.1
                focusID = 0; selectedID = 0; query = ""; searchResults = nil
                status = "历史扫描 · \(result.0.capturedAt.formatted(date: .abbreviated, time: .shortened)) · \(result.0.entries.count.formatted()) 项"
                if !result.0.isComplete { status += " · 统计不完整" }
                revision += 1
                search()
            } catch { self.error = error.localizedDescription; status = previousStatus; search() }
            transferring = false
            if snapshot?.isHistorical == false && resumeMonitoring { setMonitoring(true) }
        }
    }
}
