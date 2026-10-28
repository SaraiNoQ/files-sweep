import Foundation
import FileSweepCore

extension ScanChecks {
    func testExplanationEndpointAndRequest() throws {
        for address in ["https://api.example.com/v1/chat/completions", "http://localhost:11434/v1/chat/completions", "http://127.0.0.1:8080/v1/chat/completions", "http://[::1]:8080/v1/chat/completions"] {
            let endpoint = try ExplanationEndpoint(address: address, model: "test-model")
            assert(endpoint.url.absoluteString == address)
        }
        for address in ["http://api.example.com/v1/chat/completions", "http://127.0.0.2/v1/chat/completions", "http://localhost.example.com/v1/chat/completions", "https://user:secret@example.com/v1/chat/completions", "https://example.com/v1/chat/completions?api_key=secret", "https://example.com/v1/chat/completions#fragment", "file:///private/local", "https:///", "https://example.com:0/v1/chat/completions"] {
            assert((try? ExplanationEndpoint(address: address, model: "model")) == nil, address)
        }
        for model in ["", "\n", "test\nmodel", String(repeating: "x", count: 201)] {
            assert((try? ExplanationEndpoint(address: "https://api.example.com/v1/chat/completions", model: model)) == nil)
        }
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build/explanation-fixtures/\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("secret-personal-project/target/debug"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("private contents".utf8).write(to: root.appendingPathComponent("secret-personal-project/Cargo.toml"))
        try Data("private contents".utf8).write(to: root.appendingPathComponent("secret-personal-project/target/debug/customer-name"))
        for name in ["private-report.pdf", "private-clip.mp4", "private-code.swift", "private-data.sqlite", "private-archive.tar.gz", "private-installer.pkg", "private-image.dmg", "private-session.log", "private-secret.secretSuffix"] {
            try Data().write(to: root.appendingPathComponent(name))
        }
        try FileManager.default.createDirectory(at: root.appendingPathComponent("private-application.app"), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: root.appendingPathComponent("private-symlink.pdf").path, withDestinationPath: "/does-not-exist")
        var snapshot = try FileScanner.scan(root: root)
        let expectedRoles = ["private-report.pdf": "document", "private-clip.mp4": "media", "private-code.swift": "source_code", "private-data.sqlite": "database", "private-archive.tar.gz": "archive", "private-installer.pkg": "installer", "private-image.dmg": "disk_image", "private-session.log": "log_file", "private-secret.secretSuffix": "unknown", "private-application.app": "application_bundle", "private-symlink.pdf": "unknown"]
        for entry in snapshot.entries {
            if let expected = expectedRoles[entry.name] {
                let context = ExplanationContext(snapshot: snapshot, entryID: entry.id)
                assert(context.roleHint == expected)
                let preview = try context.preview()
                assert(!preview.contains(entry.name))
                assert(!preview.contains("secretSuffix"))
            }
        }
        let report = DeveloperAnalyzer.analyze(snapshot)
        let finding = report.findings.values.first!
        let context = ExplanationContext(snapshot: snapshot, entryID: finding.entryID, finding: finding)
        assert(context.evidenceScope == "captured_scan_snapshot_not_live_state")
        assert(context.localProtection == "requires_manual_verification")
        assert(context.localRuleID == "rust.target")
        let endpoint = try ExplanationEndpoint(address: "https://api.example.com/v1/chat/completions", model: "test-model")
        let request = try ExplanationRequest(context: context, endpoint: endpoint)
        assert(Data(request.preview.utf8) == request.body)
        assert(!request.preview.contains(root.path))
        assert(!request.preview.contains("secret-personal-project"))
        assert(!request.preview.contains("customer-name"))
        assert(!request.preview.contains("private contents"))
        let body = try JSONSerialization.jsonObject(with: request.body) as! [String: Any]
        assert(body["model"] as? String == "test-model")
        assert(body["store"] as? Bool == false && body["stream"] as? Bool == false)
        assert(body["max_completion_tokens"] as? Int == 1600)
        let messages = body["messages"] as! [[String: String]]
        assert(messages.count == 2 && messages[0]["role"] == "system")
        let instructions = messages[0]["content"]!
        for heading in ["这是什么", "删除前还缺什么信息", "建议怎么检查"] {
            assert(instructions.contains(heading))
        }
        assert(instructions.contains("不得降低本地保护等级"))
        assert(instructions.contains("不索要路径、个人名称、文件内容、凭据或更多目录树"))
        let styleExample = instructions.split(separator: "\n").last!
        let exampleData = try explanationResponse(content: String(styleExample))
        let example = try ExplanationClient.parse(exampleData)
        assert(example.explanation.count <= 180)
        assert([example.missingEvidence, example.manualChecks].allSatisfy {
            (1...3).contains($0.count) && $0.allSatisfy { !$0.isEmpty && $0.count <= 60 }
        })
        let contextPreview = try context.preview()
        assert(messages[1]["content"] == contextPreview)
        assert(context.usageState == "unknown" && context.versionControlState == "unknown" && context.rebuildability == "unknown")
        snapshot.isHistorical = true
        assert(ExplanationContext(snapshot: snapshot, entryID: finding.entryID, finding: finding).localProtection == "protected")
        snapshot.isHistorical = false
        snapshot.isStale = true
        assert(ExplanationContext(snapshot: snapshot, entryID: finding.entryID, finding: finding).localProtection == "protected")
        assert(ExplanationContext(snapshot: snapshot, entryID: 0).localRuleID == nil)
    }

    func testExplanationResponseValidation() throws {
        let valid = try explanationResponse()
        let result = try ExplanationClient.parse(valid)
        assert(result.explanation == "可能是构建产物。")
        assert(result.missingEvidence == ["尚未核验对应源码。"])
        assert(result.manualChecks == ["人工确认项目仍能重建。"])
        for data in [
            Data("not JSON; secret-service-body".utf8),
            try explanationResponse(finish: "length"),
            try explanationResponse(finish: "tool_calls"),
            try explanationResponse(content: "{}"),
            try explanationResponse(content: "```json\n{}\n```"),
            try explanationResponse(content: "{\"explanation\":\" \n\",\"missingEvidence\":[],\"manualChecks\":[]}"),
            try explanationResponse(content: String(repeating: "x", count: 16 * 1024 + 1)),
            try explanationResponse(content: "{\"explanation\":\"text\",\"missingEvidence\":[\"missing\"],\"manualChecks\":[\"check\"],\"safeToDelete\":true}"),
            try explanationResponse(content: "{\"explanation\":\"text\",\"missingEvidence\":[\"missing\"],\"manualChecks\":\"check\"}"),
            try explanationResponse(content: "{\"explanation\":\"text\",\"missingEvidence\":[\"missing\"],\"manualChecks\":[\"\"]}"),
            Data(repeating: 65, count: 128 * 1024 + 1)
        ] {
            do {
                _ = try ExplanationClient.parse(data)
                assertionFailure("Accepted invalid response")
            } catch {
                assert(!error.localizedDescription.contains("secret-service-body"))
            }
        }
    }

    func testExplanationTransport() async throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build/explanation-fixtures/\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let snapshot = try FileScanner.scan(root: root)
        let endpoint = try ExplanationEndpoint(address: "https://api.example.com/v1/chat/completions", model: "test-model")
        let request = try ExplanationRequest(context: ExplanationContext(snapshot: snapshot, entryID: 0), endpoint: endpoint)
        let response = try explanationResponse()
        ExplanationURLProtocol.configure(status: 200, data: response)
        let result = try await ExplanationClient.explain(request, apiKey: "test-secret-key", protocolClasses: [ExplanationURLProtocol.self])
        assert(result.explanation == "可能是构建产物。")
        assert(ExplanationURLProtocol.requestCount == 1)
        assert(ExplanationURLProtocol.lastAuthorization == "Bearer test-secret-key")
        assert(ExplanationURLProtocol.lastBody == request.body)
        for status in [302, 401, 429, 500] {
            ExplanationURLProtocol.configure(status: status, data: Data("secret-server-error".utf8))
            do {
                _ = try await ExplanationClient.explain(request, apiKey: "test-secret-key", protocolClasses: [ExplanationURLProtocol.self])
                assertionFailure("Accepted HTTP error")
            } catch {
                assert(!error.localizedDescription.contains("secret-server-error"))
                assert(!error.localizedDescription.contains("test-secret-key"))
                assert(ExplanationURLProtocol.requestCount == 1)
            }
        }
        ExplanationURLProtocol.configure(status: 200, data: Data(repeating: 65, count: 128 * 1024 + 1))
        do {
            _ = try await ExplanationClient.explain(request, apiKey: "", protocolClasses: [ExplanationURLProtocol.self])
            assertionFailure("Accepted oversized response")
        } catch { assert(error is ExplanationError) }
        ExplanationURLProtocol.configure(status: 200, data: response, hold: true)
        let task = Task {
            try Task.checkCancellation()
            return try await ExplanationClient.explain(request, apiKey: "test-secret-key", protocolClasses: [ExplanationURLProtocol.self])
        }
        for _ in 0..<1000 {
            if ExplanationURLProtocol.requestCount == 1 { break }
            try await Task.sleep(for: .milliseconds(1))
        }
        assert(ExplanationURLProtocol.requestCount == 1)
        task.cancel()
        do { _ = try await task.value; assertionFailure("Cancelled request completed") }
        catch { assert(error is CancellationError) }
    }

    private func explanationResponse(content: String? = nil, finish: String = "stop") throws -> Data {
        let text = content ?? "{\"explanation\":\"可能是构建产物。\",\"missingEvidence\":[\"尚未核验对应源码。\"],\"manualChecks\":[\"人工确认项目仍能重建。\"]}"
        return try JSONSerialization.data(withJSONObject: ["choices": [["finish_reason": finish, "message": ["content": text]]]])
    }
}

private final class ExplanationURLProtocol: URLProtocol, @unchecked Sendable {
    private struct State {
        var status = 200
        var data = Data()
        var count = 0
        var authorization: String?
        var body: Data?
        var hold = false
    }
    private static let lock = NSLock()
    nonisolated(unsafe) private static var state = State()
    static func configure(status: Int, data: Data, hold: Bool = false) {
        lock.withLock { state = State(status: status, data: data, hold: hold) }
    }
    static var requestCount: Int { lock.withLock { state.count } }
    static var lastAuthorization: String? { lock.withLock { state.authorization } }
    static var lastBody: Data? { lock.withLock { state.body } }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        var body = request.httpBody
        if body == nil, let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 4096)
            var data = Data()
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                data.append(contentsOf: buffer.prefix(count))
            }
            body = data
        }
        let current = Self.lock.withLock {
            Self.state.count += 1
            Self.state.authorization = request.value(forHTTPHeaderField: "Authorization")
            Self.state.body = body
            return Self.state
        }
        if current.hold { return }
        let response = HTTPURLResponse(url: request.url!, statusCode: current.status, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: current.data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
