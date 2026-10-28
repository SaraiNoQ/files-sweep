import SwiftUI
import FileSweepCore

struct AIExplanationSheet: View {
    @ObservedObject var session: ExplanationSession
    @ObservedObject private var settings: AISettings
    @Environment(\.dismiss) private var dismiss
    @State private var hasAppeared = false

    init(session: ExplanationSession, settings: AISettings = .shared) {
        self.session = session
        self.settings = settings
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("AI 辅助判断").font(PaperTypography.dialogTitle)
                Spacer()
                AISettingsLink().disabled(session.invalidated || session.isLoading)
            }
            VStack(alignment: .leading, spacing: 6) {
                Label(session.localStatus, systemImage: "shield.lefthalf.filled")
                    .font(PaperTypography.body).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 12) {
                    Text("依据扫描快照 · \(session.capturedAt.formatted(date: .abbreviated, time: .shortened))")
                    Spacer(minLength: 8)
                    if let endpoint = session.responseEndpoint {
                        Text("\(endpoint.model) · \(endpoint.url.host ?? "")")
                            .lineLimit(1).truncationMode(.middle).help(endpoint.url.absoluteString)
                    }
                }.font(PaperTypography.metadata).foregroundStyle(PaperAppearance.muted)
            }
            if session.invalidated {
                Text(session.error ?? "当前项目已变化").foregroundStyle(PaperAppearance.accent)
                    .font(PaperTypography.body).multilineTextAlignment(.center)
                    .frame(maxWidth: 440).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if session.isLoading {
                VStack(spacing: 16) {
                    ProgressView()
                    Text("正在生成用途和风险建议…").font(PaperTypography.body)
                    Button("取消请求") { session.cancel() }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let response = session.response {
                GeometryReader { geometry in
                    PaperScrollView(selectionID: 0) {
                        VStack(alignment: .leading, spacing: 24) {
                            resultSection("这是什么", lines: [response.explanation])
                            resultSection("删除前还缺什么信息", lines: response.missingEvidence)
                            resultSection("建议怎么检查", lines: response.manualChecks)
                        }.padding(.vertical, 4).padding(.trailing, 8)
                            .frame(width: geometry.size.width, alignment: .leading)
                    }
                }
            } else {
                VStack(spacing: 16) {
                    if let error = session.error {
                        Text(error).font(PaperTypography.body).foregroundStyle(PaperAppearance.accent)
                            .textSelection(.enabled).multilineTextAlignment(.center).frame(maxWidth: 440)
                    }
                    if settings.enabled {
                        Button(session.error != nil ? "重试" : session.hasStarted ? "重新判断" : "开始判断") { send() }
                            .buttonStyle(PaperButtonStyle(prominent: true))
                    } else {
                        Text("AI 辅助未启用").font(PaperTypography.body).foregroundStyle(PaperAppearance.muted)
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            HStack(alignment: .bottom, spacing: 16) {
                if session.response != nil {
                    Text("AI 可能判断错误，以上仅供参考，不代表删除许可。")
                        .font(PaperTypography.metadata).foregroundStyle(PaperAppearance.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button("关闭") { session.cancel(); dismiss() }.keyboardShortcut(.cancelAction)
            }
        }
        .padding(24).frame(width: 680, height: 620)
        .foregroundStyle(PaperAppearance.text).tint(PaperAppearance.accent)
        .buttonStyle(PaperButtonStyle()).background(GlassSurface(shape: Rectangle()))
        .onAppear {
            guard !hasAppeared else { return }
            hasAppeared = true
            if settings.enabled && !session.hasStarted && session.error == nil { send() }
        }
        .onDisappear { session.cancel() }
        .onChange(of: settings.enabled) { _ in session.cancel() }
        .onChange(of: settings.address) { _ in session.cancel() }
        .onChange(of: settings.model) { _ in session.cancel() }
    }

    private func send() {
        guard settings.enabled, !session.invalidated, !session.isLoading else { return }
        do {
            let endpoint = try ExplanationEndpoint(address: settings.address, model: settings.model)
            session.start(endpoint: endpoint, apiKey: try settings.apiKey())
        }
        catch { session.error = error.localizedDescription }
    }

    private func resultSection(_ title: String, lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(PaperTypography.sectionTitle)
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                Text(line).font(PaperTypography.body).lineSpacing(4).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
