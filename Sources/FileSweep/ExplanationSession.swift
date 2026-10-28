import Foundation
import Combine
import FileSweepCore

@MainActor
final class ExplanationSession: ObservableObject, Identifiable {
    let id = UUID()
    let context: ExplanationContext
    let sourceGeneration: UUID
    let sourceEntryID: Int
    let sourceURL: URL
    let sourceDevice: UInt64
    let sourceInode: UInt64
    let capturedAt: Date
    private let capturedLocalStatus: String
    @Published private(set) var snapshotChanged = false
    var localStatus: String {
        snapshotChanged ? "受保护 · 目录已变化，仅供打开时的快照参考" : capturedLocalStatus
    }
    @Published private(set) var hasStarted = false
    @Published private(set) var response: AIExplanation?
    @Published private(set) var responseEndpoint: ExplanationEndpoint?
    @Published private(set) var isLoading = false
    @Published private(set) var invalidated = false
    @Published var error: String?
    private var task: Task<Void, Never>?
    private var attempt = UUID()
    private let client: @Sendable (ExplanationRequest, String) async throws -> AIExplanation

    init(snapshot: ScanSnapshot, entryID: Int, finding: DeveloperFinding? = nil, localStatus: String,
         client: @escaping @Sendable (ExplanationRequest, String) async throws -> AIExplanation = {
             try await ExplanationClient.explain($0, apiKey: $1)
         }) {
        context = ExplanationContext(snapshot: snapshot, entryID: entryID, finding: finding)
        sourceGeneration = snapshot.generation
        sourceEntryID = entryID
        sourceURL = snapshot.url(for: entryID)
        sourceDevice = snapshot.entries[entryID].device
        sourceInode = snapshot.entries[entryID].inode
        capturedAt = snapshot.capturedAt
        capturedLocalStatus = localStatus
        self.client = client
    }

    func matchesSelection(snapshot: ScanSnapshot, entryID: Int?) -> Bool {
        guard let entryID, snapshot.entries.indices.contains(entryID) else { return false }
        if snapshot.generation == sourceGeneration && entryID != sourceEntryID { return false }
        let entry = snapshot.entries[entryID]
        return entry.device == sourceDevice && entry.inode == sourceInode && entry.kind == context.kind &&
            snapshot.url(for: entryID) == sourceURL
    }

    func noteSnapshotChanged() {
        // The response belongs only to this capture; never rebase its request onto the live tree.
        snapshotChanged = true
    }

    func start(endpoint: ExplanationEndpoint, apiKey: String) {
        guard !invalidated, !isLoading else { return }
        cancel()
        hasStarted = true
        let request: ExplanationRequest
        do { request = try ExplanationRequest(context: context, endpoint: endpoint) }
        catch { self.error = error.localizedDescription; return }
        let nonce = UUID()
        attempt = nonce
        isLoading = true; error = nil; response = nil
        let client = client
        task = Task { [weak self] in
            do {
                let result = try await client(request, apiKey)
                guard let self, self.attempt == nonce, !self.invalidated, !Task.isCancelled else { return }
                self.responseEndpoint = request.endpoint
                self.response = result; self.isLoading = false; self.task = nil
            } catch {
                guard let self, self.attempt == nonce, !self.invalidated, !Task.isCancelled else { return }
                self.error = error.localizedDescription; self.isLoading = false; self.task = nil
            }
        }
    }

    func cancel() {
        attempt = UUID()
        task?.cancel(); task = nil
        response = nil; responseEndpoint = nil; error = nil; isLoading = false
    }

    func invalidate() {
        cancel()
        invalidated = true
        error = "当前项目或扫描范围已切换，或项目已移动。请关闭后重新选择项目。"
    }
}

extension Workspace {
    func beginExplanation() {
        guard !isBusy, !analyzing, let snapshot, let id = selectedID,
              snapshot.entries.indices.contains(id) else { return }
        let finding = selectedFinding
        let status: String
        if snapshot.isHistorical { status = "受保护 · 历史记录，需重新扫描核验" }
        else if snapshot.isStale { status = "受保护 · 目录状态已变化" }
        else if !snapshot.isComplete || snapshot.entries[id].incomplete { status = "受保护 · 扫描不完整" }
        else if finding?.isProtected == true { status = "受保护 · " + (finding?.protectionReasons.joined(separator: "；") ?? "") }
        else if finding != nil { status = "待人工核验 · 已识别到开发产物线索" }
        else { status = "用途未确认 · 缺少本地识别依据" }
        explanationSession?.cancel()
        explanationSession = ExplanationSession(snapshot: snapshot, entryID: id, finding: finding, localStatus: status)
    }
}
