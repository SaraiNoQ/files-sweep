import Foundation
import CoreServices
import FileSweepCore

private actor Replies {
    var pending: [CheckedContinuation<AIExplanation, Error>] = []
    var bodies: [Data] = []
    var count: Int { pending.count }
    func call(_ request: ExplanationRequest) async throws -> AIExplanation {
        bodies.append(request.body)
        return try await withCheckedThrowingContinuation { pending.append($0) }
    }
    func finish(_ index: Int) {
        pending[index].resume(returning: AIExplanation(explanation: "合成用途说明", missingEvidence: ["未核验"], manualChecks: ["人工检查"]))
    }
    func fail(_ index: Int) {
        pending[index].resume(throwing: URLError(.cannotConnectToHost))
    }
}

@main
struct ExplanationSessionChecks {
    @MainActor
    static func main() async throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".bench-fixture/ai-session-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data([1]).write(to: root.appendingPathComponent("synthetic-one"))
        try Data([2]).write(to: root.appendingPathComponent("synthetic-two"))
        let snapshot = try FileScanner.scan(root: root)
        assert(snapshot.entries.count == 3)
        let endpoint = try ExplanationEndpoint(address: "https://example.com/v1/chat/completions", model: "synthetic-model")
        let replies = Replies()
        let session = ExplanationSession(snapshot: snapshot, entryID: 0, localStatus: "用途未确认") { request, _ in
            try await replies.call(request)
        }
        let expectedBody = try ExplanationRequest(context: session.context, endpoint: endpoint).body
        let initialCount = await replies.count
        assert(initialCount == 0 && !session.hasStarted, "Creating a session must not send")
        session.start(endpoint: endpoint, apiKey: "synthetic-key")
        session.start(endpoint: endpoint, apiKey: "synthetic-key")
        try await waitForCalls(replies, count: 1)
        let firstBodies = await replies.bodies
        assert(firstBodies == [expectedBody], "Start must send the captured context")
        assert(session.isLoading && session.hasStarted, "Duplicate start while loading must not send twice")
        session.cancel()
        assert(session.hasStarted, "A cancelled session must not autosend when its view reappears")
        await replies.finish(0)
        for _ in 0..<10 { await Task.yield() }
        assert(session.response == nil && !session.isLoading)
        let cancelledCount = await replies.count
        assert(cancelledCount == 1)
        session.start(endpoint: endpoint, apiKey: "synthetic-key")
        try await waitForCalls(replies, count: 2)
        await replies.finish(1)
        try await waitForCompletion(session)
        assert(session.response?.explanation == "合成用途说明")
        assert(session.responseEndpoint?.url == endpoint.url && session.responseEndpoint?.model == endpoint.model)
        session.start(endpoint: endpoint, apiKey: "synthetic-key")
        try await waitForCalls(replies, count: 3)
        await replies.fail(2)
        try await waitForCompletion(session)
        assert(session.error != nil && session.response == nil && session.hasStarted)
        for _ in 0..<10 { await Task.yield() }
        let failedCount = await replies.count
        assert(failedCount == 3, "A failure must not automatically retry")
        session.start(endpoint: endpoint, apiKey: "synthetic-key")
        try await waitForCalls(replies, count: 4)
        await replies.finish(3)
        try await waitForCompletion(session)
        assert(session.error == nil && session.response != nil, "Explicit retry after failure must work")
        session.invalidate(); session.start(endpoint: endpoint, apiKey: "synthetic-key")
        assert(session.response == nil && session.invalidated)
        let invalid = ExplanationSession(snapshot: snapshot, entryID: 0, localStatus: "用途未确认") { request, _ in
            try await replies.call(request)
        }
        invalid.invalidate(); invalid.start(endpoint: endpoint, apiKey: "synthetic-key")
        for _ in 0..<10 { await Task.yield() }
        let invalidCount = await replies.count
        assert(invalidCount == 4 && !invalid.hasStarted, "Invalidated sessions must never start")

        let targetID = 1
        let targetURL = snapshot.url(for: targetID)
        let workspace = Workspace()
        assert(!workspace.wantsMonitoring && !workspace.monitoring && workspace.monitor == nil,
               "New windows must leave automatic updates off until explicitly enabled")
        workspace.snapshot = snapshot; workspace.selectedID = targetID
        let referenceReplies = Replies()
        let reference = ExplanationSession(snapshot: snapshot, entryID: targetID, localStatus: "用途未确认") { request, _ in
            try await referenceReplies.call(request)
        }
        workspace.explanationSession = reference
        let originalBody = try ExplanationRequest(context: reference.context, endpoint: endpoint).body
        let originalContext = try reference.context.preview()
        workspace.rootIdentity = try ScanRootIdentity(root: root)
        workspace.receiveChanges([DirectoryChange(path: root.appendingPathComponent("unrelated"),
            flags: UInt32(kFSEventStreamEventFlagItemModified))])
        assert(!reference.invalidated && reference.snapshotChanged)
        assert(!workspace.pendingDirectories.isEmpty && !workspace.monitoring)
        assert(reference.localStatus.contains("受保护"))
        let beforeStartBody = try ExplanationRequest(context: reference.context, endpoint: endpoint).body
        assert(beforeStartBody == originalBody, "Background events must not change the captured payload")
        workspace.markStale()
        let repeatedStaleContext = try reference.context.preview()
        let beforeStartCount = await referenceReplies.count
        assert(repeatedStaleContext == originalContext && !reference.invalidated && !reference.hasStarted)
        assert(beforeStartCount == 0, "Background events must not initiate a request")
        reference.start(endpoint: endpoint, apiKey: "synthetic-key")
        try await waitForCalls(referenceReplies, count: 1)
        let sentBodies = await referenceReplies.bodies
        assert(sentBodies == [originalBody], "Send must use exactly the captured bytes")

        // Reindex this flat fixture so the captured index now belongs to the other file.
        var fresh = snapshot
        fresh.generation = UUID()
        fresh.entries.swapAt(1, 2)
        fresh.entries[1].id = 1; fresh.entries[2].id = 2
        fresh.entries[0].firstChild = 2
        fresh.entries[2].nextSibling = 1; fresh.entries[1].nextSibling = nil
        let remappedID = fresh.entryID(at: targetURL)!
        assert(remappedID != targetID && fresh.url(for: targetID) != targetURL)
        assert(!reference.matchesSelection(snapshot: fresh, entryID: targetID))
        assert(reference.matchesSelection(snapshot: fresh, entryID: remappedID))
        assert(!reference.matchesSelection(snapshot: fresh, entryID: nil))
        assert(!reference.matchesSelection(snapshot: fresh, entryID: fresh.entries.count))
        workspace.snapshot = fresh; workspace.selectedID = remappedID
        assert(!reference.invalidated && reference.isLoading)
        assert(reference.sourceGeneration == snapshot.generation && reference.sourceEntryID == targetID)
        assert(reference.sourceURL == targetURL && reference.capturedAt == snapshot.capturedAt)
        assert(reference.sourceDevice == snapshot.entries[targetID].device && reference.sourceInode == snapshot.entries[targetID].inode)
        let frozenContext = try reference.context.preview()
        assert(frozenContext == originalContext)
        await referenceReplies.finish(0)
        try await waitForCompletion(reference)
        assert(reference.response?.explanation == "合成用途说明", "Captured explanation must survive unrelated updates")
        assert(workspace.snapshot?.generation == fresh.generation && workspace.selectedID == remappedID)
        let referenceCount = await referenceReplies.count
        assert(referenceCount == 1, "Background updates must not automatically send again")

        var replaced = fresh
        replaced.generation = UUID()
        replaced.entries[remappedID].inode &+= 1
        assert(!reference.matchesSelection(snapshot: replaced, entryID: remappedID))
        workspace.snapshot = replaced; workspace.selectedID = remappedID
        assert(reference.invalidated, "Same path with a replacement inode is a different target")

        workspace.snapshot = snapshot; workspace.selectedID = targetID
        workspace.beginExplanation()
        let selected = workspace.explanationSession!
        workspace.selectedID = 2
        assert(selected.invalidated, "Explicit selection change must invalidate the old scope")
        workspace.beginExplanation()
        let missing = workspace.explanationSession!
        workspace.snapshot = nil
        assert(missing.invalidated)

        let otherRoot = root.appendingPathComponent("other-root")
        try FileManager.default.createDirectory(at: otherRoot, withIntermediateDirectories: true)
        workspace.snapshot = snapshot; workspace.selectedID = targetID
        workspace.beginExplanation()
        let changedRoot = workspace.explanationSession!
        workspace.snapshot = try FileScanner.scan(root: otherRoot)
        assert(changedRoot.invalidated, "A different scan root must not inherit an explanation")

        workspace.snapshot = snapshot; workspace.selectedID = targetID
        workspace.beginExplanation()
        let movedRoot = workspace.explanationSession!
        workspace.rootIdentity = try ScanRootIdentity(root: root)
        workspace.receiveChanges([DirectoryChange(path: root, flags: UInt32(kFSEventStreamEventFlagRootChanged))])
        assert(movedRoot.invalidated, "Root move must invalidate even without a new snapshot")

        workspace.snapshot = snapshot; workspace.selectedID = targetID
        let lateReplies = Replies()
        let late = ExplanationSession(snapshot: snapshot, entryID: targetID, localStatus: "用途未确认") { request, _ in
            try await lateReplies.call(request)
        }
        workspace.explanationSession = late
        late.start(endpoint: endpoint, apiKey: "synthetic-key")
        try await waitForCalls(lateReplies, count: 1)
        workspace.selectedID = 2
        await lateReplies.finish(0)
        for _ in 0..<10 { await Task.yield() }
        assert(late.invalidated && late.response == nil && !late.isLoading)

        workspace.beginExplanation()
        let rescanned = workspace.explanationSession!
        assert(!workspace.wantsMonitoring)
        workspace.scan(root)
        assert(!workspace.monitoring && workspace.monitor == nil,
               "A manual scan must not start a watcher by default")
        assert(rescanned.invalidated)
        workspace.shutdown()
        let closingWorkspace = Workspace()
        closingWorkspace.snapshot = snapshot; closingWorkspace.selectedID = targetID
        closingWorkspace.beginExplanation()
        let closed = closingWorkspace.explanationSession!
        closingWorkspace.shutdown()
        assert(closed.invalidated && closingWorkspace.explanationSession == nil)
        print("PASS: AI direct start, retry guards, frozen snapshot, background updates, index remapping, identity replacement, cancellation and shutdown")
    }

    private static func waitForCalls(_ replies: Replies, count: Int) async throws {
        for _ in 0..<1000 {
            if await replies.count == count { return }
            try await Task.sleep(for: .milliseconds(1))
        }
        assertionFailure("Client did not start")
    }

    @MainActor
    private static func waitForCompletion(_ session: ExplanationSession) async throws {
        for _ in 0..<1000 {
            if !session.isLoading { return }
            try await Task.sleep(for: .milliseconds(1))
        }
        assertionFailure("Client did not finish")
    }
}
