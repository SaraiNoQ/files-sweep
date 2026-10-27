import SwiftUI
import FileSweepCore

struct FileInspector: View {
    let snapshot: ScanSnapshot
    let selectedID: Int?
    let finding: DeveloperFinding?
    let onReveal: () -> Void
    let onOpen: (Int) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let id = selectedID, snapshot.entries.indices.contains(id) {
                        let entry = snapshot.entries[id]
                        VStack(alignment: .leading, spacing: 12) {
                            if let finding {
                                HStack {
                                    Spacer()
                                    Label(finding.isProtected ? "受保护" : "待核验",
                                          systemImage: finding.isProtected ? "lock.shield" : "questionmark.shield")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(finding.isProtected ? PaperAppearance.text : PaperAppearance.accent)
                                }
                            }
                            Text(entry.name).font(.system(size: 24, weight: .semibold))
                                .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                        }
                        let relativePath = snapshot.root.lastPathComponent + snapshot.url(for: id).path.dropFirst(snapshot.root.path.count)
                        Text(relativePath).font(.system(size: 11))
                            .foregroundStyle(PaperAppearance.muted).textSelection(.enabled)
                            .lineLimit(2).truncationMode(.middle).help(snapshot.url(for: id).path)
                        HStack(alignment: .lastTextBaseline, spacing: 20) {
                            VStack(alignment: .leading, spacing: 5) {
                                Text("逻辑大小").font(.system(size: 11)).foregroundStyle(PaperAppearance.muted)
                                Text(formatBytes(entry.logicalBytes))
                                    .font(.system(size: 34, weight: .regular, design: .serif))
                                    .lineLimit(1).minimumScaleFactor(0.7)
                            }
                            Spacer(minLength: 0)
                            VStack(alignment: .trailing, spacing: 5) {
                                Text("分配空间").font(.system(size: 11)).foregroundStyle(PaperAppearance.muted)
                                Text(formatBytes(entry.allocatedBytes)).font(.system(size: 13))
                            }
                        }.monospacedDigit()
                        Rectangle().fill(PaperAppearance.line).frame(height: 1)
                        if let finding {
                            Text("\(finding.ecosystem.rawValue) · \(finding.title)")
                                .font(.system(size: 13, weight: .medium))
                            evidenceSection("识别依据", lines: finding.evidence)
                            if finding.isProtected { evidenceSection("保护原因", lines: finding.protectionReasons) }
                            evidenceSection("仍需确认", lines: finding.cautions)
                            Link("规则参考", destination: finding.reference).font(.caption)
                        } else {
                            Label("用途未确认", systemImage: "questionmark.shield")
                                .font(.system(size: 13, weight: .medium))
                            Text("尚无足够依据将此项目归类为开发缓存。")
                                .font(.system(size: 13)).foregroundStyle(PaperAppearance.muted)
                        }
                        if entry.incomplete {
                            Label("统计不完整", systemImage: "exclamationmark.triangle").font(.caption)
                        }
                    } else {
                        Text("选择一个项目").font(.callout).foregroundStyle(PaperAppearance.muted)
                    }
                }
                .padding(24).frame(maxWidth: .infinity, alignment: .leading)
                .background(TransparentScrollbars()).id(selectedID).transition(.opacity)
            }
            if let id = selectedID, snapshot.entries.indices.contains(id) {
                HStack(spacing: 10) {
                    if snapshot.entries[id].kind == .directory {
                        Button { onOpen(id) } label: {
                            HStack {
                                Text("进入目录")
                                Spacer()
                                Image(systemName: "arrow.right")
                            }
                        }.buttonStyle(PaperButtonStyle(prominent: true))
                        Button(action: onReveal) { Image(systemName: "arrow.up.forward.square") }
                            .help("在 Finder 中显示").accessibilityLabel("在 Finder 中显示")
                    } else {
                        Button(action: onReveal) {
                            Label("在 Finder 中显示", systemImage: "arrow.up.forward.square")
                                .frame(maxWidth: .infinity)
                        }.buttonStyle(PaperButtonStyle(prominent: true))
                    }
                }.padding(.horizontal, 24).padding(.bottom, 16).padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: selectedID)
        .background(GlassSurface(shape: RoundedRectangle(cornerRadius: 18))).padding(8)
    }

    private func evidenceSection(_ title: String, lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.system(size: 12, weight: .medium)).foregroundStyle(PaperAppearance.muted)
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                Text(line).font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
