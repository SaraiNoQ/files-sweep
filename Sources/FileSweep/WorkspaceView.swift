import AppKit
import SwiftUI
import FileSweepCore

struct WorkspaceView: View {
    @StateObject private var model = Workspace()
    @State private var showIssues = false
    @State private var radialMap = true
    @State private var ringGroupIDs: [Int]?
    @FocusState private var searchFocused: Bool
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        VStack(spacing: 0) {
            if let snapshot = model.snapshot, !snapshot.entries.isEmpty {
                if radialMap {
                    HSplitView {
                        spaceMap(snapshot)
                            .frame(minWidth: 500, idealWidth: 700, maxWidth: .infinity, maxHeight: .infinity)
                        VSplitView {
                            inspector(snapshot).frame(minHeight: 210, idealHeight: 280, maxHeight: .infinity)
                            browser(snapshot).frame(minHeight: 230, idealHeight: 320, maxHeight: .infinity)
                        }.frame(minWidth: 360, idealWidth: 420, maxWidth: .infinity)
                    }.frame(maxWidth: .infinity, maxHeight: .infinity).disabled(model.analyzing)
                } else {
                    VSplitView {
                        spaceMap(snapshot)
                            .frame(minHeight: 280, idealHeight: 340, maxHeight: .infinity)
                        GeometryReader { geometry in
                            HStack(spacing: 0) {
                                browser(snapshot).frame(width: geometry.size.width * 0.57)
                                Rectangle().fill(PaperAppearance.line).frame(width: 1).padding(.vertical, 22)
                                inspector(snapshot)
                            }
                        }.frame(minHeight: 230, idealHeight: 320, maxHeight: .infinity)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity).disabled(model.analyzing)
                }
            } else {
                VStack(spacing: 18) {
                    seal.font(.system(size: 36, weight: .regular, design: .serif))
                    Text(model.scanning ? "正在扫描" : "从一个文件夹开始")
                        .font(.system(size: 25, weight: .semibold))
                    if model.scanning { ProgressView() }
                    else {
                        Button("选择文件夹…", action: model.chooseFolder)
                            .buttonStyle(PaperButtonStyle(prominent: true))
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(GlassSurface(shape: RoundedRectangle(cornerRadius: 18))).padding(8)
            }
            statusBar
        }
        .frame(minWidth: 1000, maxWidth: .infinity, minHeight: 620, maxHeight: .infinity)
        .background(LinearGradient(colors: [PaperAppearance.paper, Color(nsColor: PaperAppearance.selection), PaperAppearance.paper],
                                  startPoint: .topLeading, endPoint: .bottomTrailing))
        .foregroundStyle(PaperAppearance.text)
        .tint(PaperAppearance.accent).buttonStyle(PaperButtonStyle()).preferredColorScheme(.light)
        .toolbar { workspaceToolbar }
        .toolbarBackground(reduceTransparency ? AnyShapeStyle(PaperAppearance.paper) : AnyShapeStyle(.ultraThinMaterial), for: .windowToolbar)
        .toolbarBackground(.visible, for: .windowToolbar)
        .onChange(of: model.query) { _ in model.search(scope: ringGroupIDs) }
        .onDisappear { model.shutdown() }
        .focusedSceneValue(\.workspace, model)
        .onChange(of: model.developerOnly) { _ in model.search(scope: ringGroupIDs) }
        .onChange(of: model.ecosystem) { _ in model.search(scope: ringGroupIDs) }
        .onChange(of: model.focusID) { _ in ringGroupIDs = nil; model.search(scope: nil) }
        .onChange(of: model.snapshot?.generation) { _ in ringGroupIDs = nil; model.search(scope: nil) }
        .onChange(of: radialMap) { _ in ringGroupIDs = nil; model.search(scope: nil) }
        .sheet(isPresented: $showIssues) { issueSheet }
        .alert("无法完成操作", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("好") { model.error = nil }
        } message: { Text(model.error ?? "") }
    }

    private func inspector(_ snapshot: ScanSnapshot) -> some View {
        FileInspector(snapshot: snapshot, selectedID: model.selectedID,
                      finding: model.selectedFinding, onReveal: model.reveal, onOpen: model.openDirectory)
    }

    @ToolbarContentBuilder
    private var workspaceToolbar: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            HStack(spacing: 14) {
                Button(action: model.chooseFolder) { Image(systemName: "folder.badge.plus") }
                    .disabled(model.isBusy).help("选择文件夹（⌘O）").accessibilityLabel("选择文件夹")
            }
            .foregroundStyle(PaperAppearance.text).buttonStyle(PaperButtonStyle())
        }
        ToolbarItem(placement: .navigation) {
            HStack(spacing: 14) {
                if model.scanning || model.updating {
                    Button(action: model.stop) { Image(systemName: "stop") }
                        .help("停止").accessibilityLabel("停止")
                } else {
                    Button { if let root = model.snapshot?.root { model.scan(root) } } label: {
                        Image(systemName: "arrow.clockwise")
                    }.disabled(model.snapshot == nil || model.transferring)
                        .help("重新扫描").accessibilityLabel("重新扫描")
                }
                Button { model.setMonitoring(!model.monitoring) } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .foregroundStyle(model.monitoring ? PaperAppearance.accent : PaperAppearance.muted)
                }
                .disabled(model.snapshot == nil || model.snapshot?.isHistorical == true || model.scanning || model.transferring)
                .help(model.snapshot?.isHistorical == true ? "历史记录需先重新扫描" : model.monitoring ? "暂停自动更新" : "开启自动更新")
                .accessibilityLabel("自动更新").accessibilityValue(model.monitoring ? "开启" : "关闭")
                Menu {
                    Button("保存当前扫描…", action: model.saveArchive).disabled(model.snapshot?.entries.isEmpty != false)
                    Button("打开扫描记录…", action: model.openArchive)
                } label: { Image(systemName: "clock.arrow.circlepath") }
                    .menuStyle(.borderlessButton).fixedSize().disabled(model.isBusy)
                    .padding(.horizontal, 10).frame(height: 32)
                    .background(GlassSurface(shape: RoundedRectangle(cornerRadius: 10)))
                    .help("扫描记录").accessibilityLabel("扫描记录")
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(PaperAppearance.muted)
                    TextField("搜索文件名", text: $model.query).textFieldStyle(.plain)
                        .focused($searchFocused)
                        .disabled(model.snapshot == nil || model.scanning || model.transferring)
                    if !model.query.isEmpty {
                        Button { model.query = "" } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.plain).accessibilityLabel("清除搜索")
                    }
                }
                .font(.system(size: 13)).padding(.horizontal, 12).frame(width: 240, height: 34)
                .background(GlassSurface(shape: RoundedRectangle(cornerRadius: 12)))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(searchFocused ? PaperAppearance.accent : .clear,
                                                                      lineWidth: searchFocused ? 1.5 : 1))
            }
            .foregroundStyle(PaperAppearance.text).buttonStyle(PaperButtonStyle())
        }
        ToolbarItem(placement: .automatic) { Spacer() }
        ToolbarItem(placement: .primaryAction) {
            MapStylePicker(radialMap: $radialMap)
                .disabled(model.snapshot?.entries.isEmpty != false || model.analyzing)
        }
    }

    private var seal: some View {
        Text("扫").foregroundStyle(PaperAppearance.paper)
            .padding(4).background(GlassSurface(shape: RoundedRectangle(cornerRadius: 6), tint: PaperAppearance.accent))
            .rotationEffect(.degrees(-5)).accessibilityHidden(true)
    }

    private var statusBar: some View {
        VStack(spacing: 0) {
            Rectangle().fill(PaperAppearance.line).frame(height: 1)
            HStack(spacing: 12) {
                if model.analyzing || model.transferring || model.updating { ProgressView().controlSize(.mini) }
                Text(model.status).lineLimit(1).help(model.status)
                if (model.snapshot?.issueCount ?? 0) > 0 {
                    Button("\(model.snapshot?.issueCount ?? 0) 个读取问题") { showIssues = true }
                        .buttonStyle(.plain).underline()
                }
                Spacer(minLength: 8)
                Text("逻辑大小不等于可回收空间").fixedSize()
            }.font(.system(size: 11)).foregroundStyle(PaperAppearance.muted)
                .padding(.horizontal, 24).frame(height: 34)
        }.background(GlassSurface(shape: Rectangle()))
    }

    private func browser(_ snapshot: ScanSnapshot) -> some View {
        let groupIDs = radialMap ? ringGroupIDs : nil
        let results = model.searchResults
        return VStack(spacing: 10) {
            HStack(spacing: 6) {
                scopeButton("全部文件", developerOnly: false)
                scopeButton("开发产物", developerOnly: true)
                if model.developerOnly {
                    Menu {
                        Button("全部语言") { model.ecosystem = nil }
                        ForEach(DeveloperEcosystem.allCases, id: \.self) { ecosystem in
                            Button(ecosystem.rawValue) { model.ecosystem = ecosystem }
                        }
                    } label: { Text(model.ecosystem?.rawValue ?? "全部语言") }
                        .menuStyle(.borderlessButton).fixedSize().padding(.horizontal, 10).frame(height: 30)
                        .background(GlassSurface(shape: RoundedRectangle(cornerRadius: 10)))
                        .accessibilityLabel("语言筛选")
                }
                Spacer()
                if model.searching { ProgressView().controlSize(.mini) }
                if let results {
                    Text((groupIDs != nil ? "分组 · " : "") + (model.matchCount > results.count ? "\(model.matchCount) 项 · 显示前 \(results.count) 项" : "\(results.count) 项"))
                        .font(.caption).foregroundStyle(PaperAppearance.muted)
                }
            }.frame(height: 36)
            HStack {
                Text("名称")
                Spacer()
                Text("逻辑大小")
            }.font(.system(size: 11)).foregroundStyle(PaperAppearance.muted)
                .padding(.leading, 26).padding(.trailing, 32)
            ZStack {
                FileOutline(snapshot: snapshot, searchResults: results,
                            findings: model.developerReport?.findings ?? [:], revision: model.revision,
                            rootID: radialMap ? model.focusID : 0,
                            selection: model.selectedID, onSelect: { model.selectedID = $0 }, onOpen: model.openDirectory)
                    .opacity(model.searching ? 0.55 : 1).allowsHitTesting(!model.searching)
                if !model.searching, let results, results.isEmpty {
                    Text(model.query.isEmpty ? "未识别到开发产物" : "没有匹配项目")
                        .font(.callout).foregroundStyle(PaperAppearance.muted)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(GlassSurface(shape: RoundedRectangle(cornerRadius: 12)))
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }.padding(.horizontal, 24).padding(.top, 16).padding(.bottom, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(GlassSurface(shape: RoundedRectangle(cornerRadius: 18))).padding(8)
    }

    private func scopeButton(_ title: String, developerOnly: Bool) -> some View {
        Button { model.developerOnly = developerOnly } label: {
            Text(title).font(.system(size: 13, weight: model.developerOnly == developerOnly ? .semibold : .regular))
                .foregroundStyle(model.developerOnly == developerOnly ? PaperAppearance.text : PaperAppearance.muted)
        }.buttonStyle(PaperButtonStyle(selected: model.developerOnly == developerOnly))
            .accessibilityAddTraits(model.developerOnly == developerOnly ? .isSelected : [])
    }

    private func spaceMap(_ snapshot: ScanSnapshot) -> some View {
        let focus = snapshot.entries.indices.contains(model.focusID) ? model.focusID : 0
        return VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Button { model.openDirectory(snapshot.entries[focus].parent ?? 0) } label: {
                    Image(systemName: "chevron.left")
                }.help("上一级目录").accessibilityLabel("上一级目录").disabled(focus == 0)
                VStack(alignment: .leading, spacing: 5) {
                    if focus != 0 {
                        Text(snapshot.root.lastPathComponent + snapshot.url(for: focus).deletingLastPathComponent().path.dropFirst(snapshot.root.path.count))
                            .font(.system(size: 11)).foregroundStyle(PaperAppearance.muted)
                            .lineLimit(1).truncationMode(.middle)
                    }
                    Text(snapshot.entries[focus].name).font(.system(size: radialMap ? 22 : 27, weight: .semibold))
                        .lineLimit(1).truncationMode(.middle).help(snapshot.url(for: focus).path)
                }
                if !radialMap {
                    Text(formatBytes(snapshot.entries[focus].logicalBytes))
                        .font(.system(size: 25, weight: .regular, design: .serif))
                        .monospacedDigit().foregroundStyle(PaperAppearance.muted)
                }
                Spacer(minLength: 0)
            }
            if radialMap {
                SunburstMap(snapshot: snapshot, rootID: focus, selection: model.selectedID,
                            onSelect: { model.selectedID = $0 }, onOpen: model.openDirectory,
                            onGroup: { ringGroupIDs = $0; model.search(scope: $0) })
            } else {
                DiskMap(snapshot: snapshot, rootID: focus, selection: model.selectedID,
                        onSelect: { model.selectedID = $0 }, onOpen: model.openDirectory)
            }
        }.padding(.horizontal, 24).padding(.top, 20).padding(.bottom, 14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(GlassSurface(shape: RoundedRectangle(cornerRadius: 18))).padding(8)
    }

    private var issueSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("读取问题").font(.title2)
            Text("共 \(model.snapshot?.issueCount ?? 0) 项，最多保留前 100 条。")
            ScrollView {
                ForEach(Array((model.snapshot?.issues ?? []).enumerated()), id: \.offset) { _, issue in
                    VStack(alignment: .leading) {
                        Text(issue.path).textSelection(.enabled)
                        Text(issue.message).foregroundStyle(PaperAppearance.muted)
                    }.padding(.bottom, 10)
                }
            }.frame(height: 300)
            HStack { Spacer(); Button("完成") { showIssues = false }.keyboardShortcut(.defaultAction) }
        }.padding(24).frame(width: 600).background(GlassSurface(shape: Rectangle()))
    }
}
