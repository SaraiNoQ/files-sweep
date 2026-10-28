import Foundation
import SwiftUI
import FileSweepCore

extension Workspace {
    var selectedFinding: DeveloperFinding? {
        guard let id = selectedID, var finding = developerReport?.findings[id] else { return nil }
        if snapshot?.isStale == true && !finding.protectionReasons.contains(where: { $0.contains("等待重新核验") }) {
            finding.protectionReasons.append("目录已经变化，当前状态等待重新核验。")
        }
        return finding
    }

    func startMonitoring(_ root: URL) throws {
        let identity = try ScanRootIdentity(root: root)
        let nonce = UUID()
        monitorID = nonce
        monitor = try DirectoryMonitor(root: root) { [weak self] changes in
            Task { @MainActor [weak self] in
                guard let self, self.monitorID == nonce, self.monitoring else { return }
                self.receiveChanges(changes)
            }
        }
        rootIdentity = identity; monitorRoot = root.standardizedFileURL; monitoring = true
    }

    func stopMonitoring() {
        monitorID = UUID()
        monitor?.stop(); monitor = nil; monitoring = false; monitorRoot = nil
        debounceTask?.cancel(); debounceTask = nil
        updateCancellation.cancel(); updateTask?.cancel(); updateTask = nil; updating = false
        pendingDirectories.removeAll(); pendingFullScan = false; firstPendingTime = nil
    }

    func setMonitoring(_ enabled: Bool) {
        wantsMonitoring = enabled
        if !enabled { stopMonitoring(); markStale(); status = "自动更新已暂停"; return }
        guard !isBusy, let snapshot, !snapshot.isHistorical, let rootEntry = snapshot.entries.first else { return }
        do {
            let current = try ScanRootIdentity(root: snapshot.root)
            guard current.device == rootEntry.device, current.inode == rootEntry.inode else {
                explanationSession?.invalidate()
                throw ScanError.failed("根目录已被替换，请重新选择目录。")
            }
            try startMonitoring(snapshot.root)
            // Changes while paused were not observed; repair the authorized scope once.
            pendingFullScan = true; markStale(); scheduleUpdate()
        } catch { stopMonitoring(); markStale(); status = error.localizedDescription }
    }

    func markStale() {
        if snapshot != nil { snapshot?.isStale = true }
        if developerOnly { protectedMatchCount = matchCount }
        if searching { search() }
    }

    func receiveChanges(_ changes: [DirectoryChange]) {
        guard let identity = rootIdentity else { return }
        if changes.contains(where: \.rootChanged) {
            explanationSession?.invalidate()
            stopMonitoring(); markStale(); status = "根目录已移动或替换，请重新选择目录。"; return
        }
        let root = monitorRoot ?? snapshot?.root ?? URL(fileURLWithPath: identity.canonicalPath)
        for change in changes {
            if change.requiresFullScan { pendingFullScan = true }
            if let directory = change.directory(in: root, canonicalRoot: URL(fileURLWithPath: identity.canonicalPath)) {
                if pendingDirectories.count < 128 { pendingDirectories.insert(directory) }
                else { pendingFullScan = true }
            }
        }
        guard pendingFullScan || !pendingDirectories.isEmpty else { return }
        markStale()
        if firstPendingTime == nil { firstPendingTime = ProcessInfo.processInfo.systemUptime }
        scheduleUpdate()
    }

    func scheduleUpdate() {
        guard monitoring, pendingFullScan || !pendingDirectories.isEmpty, !scanning, !transferring, !updating else { return }
        debounceTask?.cancel()
        let elapsed = ProcessInfo.processInfo.systemUptime - (firstPendingTime ?? ProcessInfo.processInfo.systemUptime)
        let delay = min(0.5, max(0, 2 - elapsed))
        debounceTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(delay)) } catch { return }
            self?.refreshIncrementally()
        }
    }

    private func refreshIncrementally() {
        guard monitoring, !isBusy, let old = snapshot, !old.isHistorical, let identity = rootIdentity else { return }
        let directories = Array(pendingDirectories), full = pendingFullScan
        pendingDirectories.removeAll(); pendingFullScan = false; firstPendingTime = nil
        updateCancellation = ScanCancellation()
        let token = updateCancellation, session = sessionID
        updating = true; status = "正在更新变化目录…"
        updateTask = Task { [weak self] in
            do {
                let result = try await Task.detached(priority: .utility) {
                    let update = try IncrementalScanner.refresh(old, dirtyDirectories: directories,
                        identity: identity, forceFullScan: full, cancellation: token)
                    return (update.snapshot, DeveloperAnalyzer.analyze(update.snapshot, cancellation: token))
                }.value
                guard let self, self.sessionID == session, self.snapshot?.generation == old.generation,
                      !token.isCancelled, !Task.isCancelled else { return }
                var fresh = result.0
                fresh.isStale = self.pendingFullScan || !self.pendingDirectories.isEmpty
                let focusURL = old.url(for: self.focusID)
                let selectedURL = self.selectedID.flatMap { old.entries.indices.contains($0) ? old.url(for: $0) : nil }
                var focus = focusURL
                while fresh.entryID(at: focus) == nil && focus.pathComponents.count > fresh.root.pathComponents.count { focus.deleteLastPathComponent() }
                self.snapshot = fresh; self.developerReport = result.1
                self.focusID = fresh.entryID(at: focus) ?? 0
                self.selectedID = selectedURL.flatMap { fresh.entryID(at: $0) }
                self.revision += 1; self.updating = false; self.search()
                self.status = "已自动更新 · \(fresh.entries.count.formatted()) 项 · \(Date().formatted(date: .omitted, time: .standard))"
                if !fresh.isComplete { self.stopMonitoring(); self.status += " · 统计不完整，自动更新已暂停" }
                self.scheduleUpdate()
            } catch {
                guard let self, self.sessionID == session, !token.isCancelled else { return }
                self.explanationSession?.invalidate()
                self.stopMonitoring(); self.markStale()
                self.status = "自动更新已停止：" + error.localizedDescription
            }
        }
    }

}
