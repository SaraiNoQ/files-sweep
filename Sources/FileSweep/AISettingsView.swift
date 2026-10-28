import AppKit
import SwiftUI

struct AISettingsView: View {
    @ObservedObject private var settings: AISettings
    @State private var address = ""
    @State private var model = ""
    @State private var apiKey = ""
    @State private var enabled = false
    @State private var configurationError: String?
    @State private var saved = false

    init(settings: AISettings = .shared) { self.settings = settings }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("AI 辅助").font(PaperTypography.dialogTitle)
            Form {
                Toggle("启用 AI 辅助", isOn: draft($enabled))
                TextField("完整接口地址", text: Binding(get: { address }, set: {
                    address = $0; apiKey = ""; saved = false; configurationError = nil
                }), prompt: Text("https://服务地址/v1/chat/completions"))
                TextField("模型", text: draft($model), prompt: Text("服务提供的模型 ID"))
                SecureField("API 密钥", text: draft($apiKey))
            }.textFieldStyle(.roundedBorder)
            VStack(alignment: .leading, spacing: 8) {
                Text("使用兼容 Chat Completions 的接口。云端须用 HTTPS；本机模型可用 localhost 或回环 IP。密钥保存在 macOS 钥匙串，接口地址变化时请重新填写。")
                Text("启用后，点击“AI 辅助判断”即向此服务发送类型、大小区间等脱敏线索，不发送原始路径、个人文件名或内容。请求可能产生费用，数据保留政策由此服务决定。")
            }.font(PaperTypography.metadata).lineSpacing(3).foregroundStyle(PaperAppearance.muted)
                .fixedSize(horizontal: false, vertical: true)
            if let configurationError {
                Text(configurationError).foregroundStyle(PaperAppearance.accent)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 12) {
                Button("移除当前密钥并关闭 AI", action: removeKey)
                Spacer()
                if saved { Text("已保存").font(PaperTypography.metadata).foregroundStyle(PaperAppearance.muted) }
                Button("保存设置", action: save).buttonStyle(PaperButtonStyle(prominent: true))
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24).frame(width: 580)
        .foregroundStyle(PaperAppearance.text).tint(PaperAppearance.accent)
        .buttonStyle(PaperButtonStyle()).background(GlassSurface(shape: Rectangle()))
        .preferredColorScheme(.light)
        .onAppear(perform: load)
        .onDisappear { apiKey = "" }
    }

    private func draft<Value>(_ value: Binding<Value>) -> Binding<Value> {
        Binding(get: { value.wrappedValue }, set: {
            value.wrappedValue = $0; saved = false; configurationError = nil
        })
    }

    private func load() {
        address = settings.address; model = settings.model; enabled = settings.enabled
        saved = false; configurationError = nil
        do { apiKey = try settings.apiKey() }
        catch { apiKey = ""; configurationError = error.localizedDescription }
    }

    private func save() {
        do {
            try settings.save(address: address, model: model, apiKey: apiKey, enabled: enabled)
            saved = true; configurationError = nil
        } catch { saved = false; configurationError = error.localizedDescription }
    }

    private func removeKey() {
        do {
            try settings.removeKey()
            apiKey = ""; enabled = false; saved = false; configurationError = nil
        } catch { configurationError = error.localizedDescription }
    }
}

struct AISettingsLink: View {
    var body: some View {
        if #available(macOS 14.0, *) {
            SettingsLink { Text("AI 设置…") }
        } else {
            Button("AI 设置…") {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }
        }
    }
}
