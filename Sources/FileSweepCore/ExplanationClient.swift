import Foundation

public enum ExplanationError: Error, LocalizedError {
    case endpoint, model, key, requestLimit, responseLimit, invalidResponse, redirected, transport
    case service(Int)

    public var errorDescription: String? {
        switch self {
        case .endpoint: return "请输入完整的 HTTPS Chat Completions 地址；HTTP 仅允许 localhost、127.0.0.1 或 [::1]，地址不能含账号、查询参数或片段。"
        case .model: return "请输入有效的模型名称（最多 200 字节，不能含控制字符）。"
        case .key: return "API 密钥格式无效，请检查是否含空格或换行。"
        case .requestLimit: return "本次脱敏请求超过大小限制，未发送。"
        case .responseLimit: return "服务响应超过大小限制，已停止接收。"
        case .invalidResponse: return "服务未返回完整、有效的结构化解释，请检查模型是否支持 JSON 输出。"
        case .redirected: return "服务要求重定向，已阻止发送。请在设置中填写最终服务地址后重试。"
        case .transport: return "无法连接 AI 服务或请求已超时，请检查服务地址与网络。"
        case .service(let status):
            switch status {
            case 401, 403: return "AI 服务拒绝访问，请检查密钥和模型权限。"
            case 429: return "AI 服务请求受限或额度不足，请稍后手动重试。"
            default: return "AI 服务请求失败（HTTP \(status)），请检查服务与模型配置。"
            }
        }
    }
}

public struct ExplanationEndpoint: Sendable {
    public let url: URL
    public let model: String

    public init(address: String, model: String) throws {
        let address = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard address.utf8.count <= 2048, !address.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
              let components = URLComponents(string: address), let url = components.url,
              let host = components.host?.lowercased(), !host.isEmpty,
              components.user == nil, components.password == nil, components.query == nil, components.fragment == nil,
              components.port.map({ (1...65535).contains($0) }) ?? true,
              components.scheme?.lowercased() == "https" ||
                (components.scheme?.lowercased() == "http" && ["localhost", "127.0.0.1", "[::1]"].contains(host))
        else { throw ExplanationError.endpoint }
        let model = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty, model.utf8.count <= 200,
              !model.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
        else { throw ExplanationError.model }
        self.url = url
        self.model = model
    }
}

public struct ExplanationRequest: Sendable {
    public let endpoint: ExplanationEndpoint
    public let body: Data
    public var preview: String { String(decoding: body, as: UTF8.self) }

    public init(context: ExplanationContext, endpoint: ExplanationEndpoint) throws {
        self.endpoint = endpoint
        let payload = RequestBody(model: endpoint.model, messages: [
            Message(role: "system", content: Self.instructions),
            Message(role: "user", content: try context.preview())
        ])
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        body = try encoder.encode(payload)
        guard body.count <= 32 * 1024 else { throw ExplanationError.requestLimit }
    }

    private struct Message: Encodable { let role: String; let content: String }
    private struct RequestBody: Encodable {
        let model: String
        let messages: [Message]
        let store = false
        let stream = false
        let response_format = ["type": "json_object"]
        let max_completion_tokens = 1600
    }
    private static let instructions = """
    你在只读文件分析工具中，帮助普通用户看懂一个文件或文件夹的用途，以及删除前需要自己确认的事。只依据用户消息中的脱敏元数据，不编造文件内容或用途。
    元数据固定来自用户打开解释时的扫描快照，后续变化不会更新此上下文；只解释该快照，不声称已核验当前文件系统状态。
    名称和后缀都只是线索。不得将未知项认定为缓存或可删除，不得降低本地保护等级。历史、过期或不完整扫描不能证明当前状态。
    你不知道文件内容、是否正被使用、Git 是否跟踪、源码是否存在、能否重新下载或生成。没有依据就直说“还不能判断”或“尚未确认”，不要猜测。文件大小不等于可回收空间。
    不提供删除许可、清理承诺、命令、脚本或可执行 HTML；不索要路径、个人名称、文件内容、凭据或更多目录树，不建议自动访问任何位置。

    界面会固定显示“这是什么”“删除前还缺什么信息”“建议怎么检查”三个部分。只输出一个 JSON 对象，恰有 explanation、missingEvidence、manualChecks 三个字段，不要输出标题、Markdown、代码围栏或额外字段。
    explanation：对应“这是什么”。写 2 至 3 个短句，共不超过 180 字。先说可能做什么，再说有依据的依赖或删除影响；用途不明就明确说不能判断，不能为了凑句子补充猜测。
    missingEvidence：对应“删除前还缺什么信息”。写 1 至 3 条非空短句，每条不超过 60 字，只列会影响判断的未知事项，不重复已有依据。
    manualChecks：对应“建议怎么检查”。写 1 至 3 条非空短句，每条不超过 60 字，给出普通用户能完成的具体检查；和上面的未知事项对应，不用“综合评估”“谨慎操作”等空话。
    用日常中文，不复述英文枚举值、规则 ID、item-N 别名或 JSON 字段名。必要的技术词随句解释。不要在每段重复只读、快照、保护状态或 AI 免责声明，界面已有这些提示；仍须遵守上述边界。

    下例只示范格式和语气，不是当前项目的证据，不能照抄成当前项目的结论：
    {"explanation":"仅凭现有信息，还不能判断这一项的具体用途。也无法确认它是否能重新生成。","missingEvidence":["它属于哪个软件或项目。","是否还有程序依赖它。"],"manualChecks":["先确认来源软件或项目，再查看其中是否仍在使用这一项。","检查是否有可用备份；没有备份时先保留。"]}
    """
}

public struct AIExplanation: Decodable, Sendable {
    public let explanation: String
    public let missingEvidence: [String]
    public let manualChecks: [String]

    public init(explanation: String, missingEvidence: [String], manualChecks: [String]) {
        self.explanation = explanation
        self.missingEvidence = missingEvidence
        self.manualChecks = manualChecks
    }
}

public enum ExplanationClient {
    public static func explain(_ request: ExplanationRequest, apiKey: String) async throws -> AIExplanation {
        try await explain(request, apiKey: apiKey, protocolClasses: nil)
    }

    // URLProtocol is a deterministic transport seam for the check executable.
    public static func explain(_ request: ExplanationRequest, apiKey: String,
                               protocolClasses: [AnyClass]?) async throws -> AIExplanation {
        guard apiKey.utf8.count <= 4096,
              apiKey.unicodeScalars.allSatisfy({ $0.value > 32 && $0.value < 127 })
        else { throw ExplanationError.key }
        try Task.checkCancellation()
        var urlRequest = URLRequest(url: request.endpoint.url)
        urlRequest.httpMethod = "POST"
        urlRequest.httpBody = request.body
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        if !apiKey.isEmpty { urlRequest.setValue("Bearer " + apiKey, forHTTPHeaderField: "Authorization") }
        urlRequest.timeoutInterval = 60
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 60
        configuration.protocolClasses = protocolClasses
        let delegate = NoRedirects()
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        do {
            let (bytes, response) = try await session.bytes(for: urlRequest)
            guard let response = response as? HTTPURLResponse else { throw ExplanationError.invalidResponse }
            if (300..<400).contains(response.statusCode) { throw ExplanationError.redirected }
            guard response.statusCode == 200 else { throw ExplanationError.service(response.statusCode) }
            guard response.expectedContentLength <= 128 * 1024 else { throw ExplanationError.responseLimit }
            var data = Data()
            for try await byte in bytes {
                try Task.checkCancellation()
                guard data.count < 128 * 1024 else { throw ExplanationError.responseLimit }
                data.append(byte)
            }
            return try parse(data)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch let error as ExplanationError {
            throw error
        } catch {
            throw ExplanationError.transport
        }
    }

    public static func parse(_ data: Data) throws -> AIExplanation {
        guard data.count <= 128 * 1024 else { throw ExplanationError.responseLimit }
        struct Response: Decodable {
            struct Choice: Decodable {
                struct Message: Decodable { let content: String?; let refusal: String? }
                let message: Message
                let finish_reason: String
            }
            let choices: [Choice]
        }
        do {
            let response = try JSONDecoder().decode(Response.self, from: data)
            guard response.choices.count == 1, let choice = response.choices.first,
                  choice.finish_reason == "stop", choice.message.refusal == nil,
                  let text = choice.message.content, text.utf8.count <= 16 * 1024,
                  let json = text.data(using: .utf8),
                  let object = try JSONSerialization.jsonObject(with: json) as? [String: Any],
                  Set(object.keys) == ["explanation", "missingEvidence", "manualChecks"]
            else { throw ExplanationError.invalidResponse }
            let result = try JSONDecoder().decode(AIExplanation.self, from: json)
            func valid(_ text: String, max: Int) -> Bool {
                !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && text.count <= max &&
                !text.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) && $0 != "\n" && $0 != "\t" }
            }
            guard valid(result.explanation, max: 4000),
                  [result.missingEvidence, result.manualChecks].allSatisfy({ items in
                      (1...8).contains(items.count) && items.allSatisfy { valid($0, max: 500) }
                  }) else { throw ExplanationError.invalidResponse }
            return result
        } catch let error as ExplanationError {
            throw error
        } catch {
            throw ExplanationError.invalidResponse
        }
    }
}

private final class NoRedirects: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
