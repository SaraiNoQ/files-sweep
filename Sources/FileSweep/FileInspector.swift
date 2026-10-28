import SwiftUI
import FileSweepCore

struct FileInspector: View {
    let snapshot: ScanSnapshot
    let selectedID: Int?
    let finding: DeveloperFinding?
    let onReveal: () -> Void
    let onOpen: (Int) -> Void
    let onExplain: () -> Void
    var canExplain = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geometry in
                PaperScrollView(selectionID: selectedID) {
                    VStack(alignment: .leading, spacing: 16) {
                        if let id = selectedID, snapshot.entries.indices.contains(id) {
                            let entry = snapshot.entries[id]
                            let relativePath = snapshot.root.lastPathComponent + snapshot.url(for: id).path.dropFirst(snapshot.root.path.count)
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                    Text(entry.name).font(PaperTypography.objectTitle)
                                        .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                                    Spacer(minLength: 8)
                                    if let finding {
                                        Label(finding.isProtected ? "受保护" : "待核验",
                                              systemImage: finding.isProtected ? "lock.shield" : "questionmark.shield")
                                            .font(PaperTypography.label).fixedSize()
                                            .foregroundStyle(finding.isProtected ? PaperAppearance.text : PaperAppearance.accent)
                                    }
                                }
                                Text(relativePath).font(PaperTypography.metadata)
                                    .foregroundStyle(PaperAppearance.muted).textSelection(.enabled)
                                    .lineLimit(2).truncationMode(.middle).help(snapshot.url(for: id).path)
                            }
                            HStack(alignment: .lastTextBaseline, spacing: 16) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("逻辑大小").font(PaperTypography.metadata).foregroundStyle(PaperAppearance.muted)
                                    Text(formatBytes(entry.logicalBytes))
                                        .font(.system(size: 34, weight: .regular, design: .serif))
                                        .lineLimit(1).minimumScaleFactor(0.7)
                                }
                                Spacer(minLength: 0)
                                VStack(alignment: .trailing, spacing: 4) {
                                    Text("分配空间").font(PaperTypography.metadata).foregroundStyle(PaperAppearance.muted)
                                    Text(formatBytes(entry.allocatedBytes)).font(PaperTypography.body)
                                }
                            }.monospacedDigit()
                            Rectangle().fill(PaperAppearance.line).frame(height: 1)
                            if let finding {
                                Text("\(finding.ecosystem.rawValue) · \(finding.title)")
                                    .font(PaperTypography.sectionTitle)
                                evidenceSection("识别依据", lines: finding.evidence)
                                if finding.isProtected { evidenceSection("保护原因", lines: finding.protectionReasons) }
                                evidenceSection("仍需确认", lines: finding.cautions)
                                Link("规则参考", destination: finding.reference).font(PaperTypography.metadata)
                            } else {
                                Label("用途未确认", systemImage: "questionmark.shield")
                                    .font(PaperTypography.sectionTitle)
                                Text("尚无足够依据将此项目归类为开发缓存。")
                                    .font(PaperTypography.body).lineSpacing(3).foregroundStyle(PaperAppearance.muted)
                            }
                            if entry.incomplete {
                                Label("统计不完整", systemImage: "exclamationmark.triangle").font(PaperTypography.metadata)
                            }
                        } else {
                            Text("选择一个项目").font(.callout).foregroundStyle(PaperAppearance.muted)
                        }
                    }
                    .padding(24).frame(width: geometry.size.width, alignment: .leading)
                    .id(selectedID).transition(.opacity)
                }
            }
            if let id = selectedID, snapshot.entries.indices.contains(id) {
                HStack(spacing: 8) {
                    if snapshot.entries[id].kind == .directory {
                        Button { onOpen(id) } label: {
                            HStack {
                                Text("进入目录")
                                Spacer()
                                Image(systemName: "arrow.right")
                            }
                        }.buttonStyle(PaperButtonStyle(prominent: true))
                        Button("AI 辅助判断", action: onExplain).disabled(!canExplain).fixedSize()
                        Button(action: onReveal) { Image(systemName: "arrow.up.forward.square") }
                            .help("在 Finder 中显示").accessibilityLabel("在 Finder 中显示")
                    } else {
                        Button(action: onReveal) {
                            Label("在 Finder 中显示", systemImage: "arrow.up.forward.square")
                                .frame(maxWidth: .infinity)
                        }.buttonStyle(PaperButtonStyle(prominent: true))
                        Button("AI 辅助判断", action: onExplain).disabled(!canExplain).fixedSize()
                    }
                }.padding(.horizontal, 24).padding(.bottom, 16).padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: selectedID)
        .background(GlassSurface(shape: RoundedRectangle(cornerRadius: 18))).padding(8)
    }

    private func evidenceSection(_ title: String, lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(PaperTypography.sectionTitle)
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                Text(line).font(PaperTypography.body).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
