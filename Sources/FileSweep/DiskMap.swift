import SwiftUI
import FileSweepCore

struct DiskMap: View {
    let snapshot: ScanSnapshot
    let rootID: Int
    let selection: Int?
    let onSelect: (Int) -> Void
    let onOpen: (Int) -> Void
    @State private var weights: [(id: Int, bytes: UInt64)] = []
    @State private var loadedRoot: Int?
    @State private var loadedGeneration: UUID?
    @State private var groupTrail: [Range<Int>] = []
    @State private var regions: [MapRegion] = []
    @State private var renderedKey: LayoutKey?
    @State private var hoveredIndex: Int?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast

    private struct LayoutKey: Equatable {
        let root: Int
        let generation: UUID?
        let range: Range<Int>
        let size: CGSize
        let insideGroup: Bool
    }

    var body: some View {
        let loaded: Bool = loadedRoot == rootID && loadedGeneration == snapshot.generation
        let range: Range<Int> = loaded ? (groupTrail.last ?? (0..<weights.count)) : (0..<0)
        VStack(alignment: .leading, spacing: 8) {
            if loaded && !groupTrail.isEmpty {
                HStack(spacing: 10) {
                    Button { groupTrail.removeLast() } label: {
                        Label("上一级分组", systemImage: "chevron.left")
                    }
                    Text("合并项目 · \(range.count) 项").font(.system(size: 13, weight: .medium))
                    Spacer()
                    Button("返回目录") { groupTrail.removeAll() }
                }.frame(height: 32)
            }
            GeometryReader { geometry in
                regionCanvas(size: geometry.size, range: range, loaded: loaded)
            }
        }
        .task(id: "\(snapshot.generation.uuidString):\(rootID)") { await loadWeights() }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func loadWeights() async {
        let values: [(id: Int, bytes: UInt64)] = await Task.detached(priority: .userInitiated) {
            var result: [(id: Int, bytes: UInt64)] = []
            for id in snapshot.children(of: rootID) {
                let entry = snapshot.entries[id]
                if Treemap.includes(kind: entry.kind, bytes: entry.logicalBytes) {
                    result.append((id: id, bytes: entry.logicalBytes))
                }
            }
            result.sort { a, b in a.bytes == b.bytes ? a.id < b.id : a.bytes < b.bytes }
            return result
        }.value
        guard !Task.isCancelled else { return }
        groupTrail.removeAll(); hoveredIndex = nil; renderedKey = nil
        weights = values; loadedRoot = rootID; loadedGeneration = snapshot.generation
    }

    private func regionCanvas(size: CGSize, range: Range<Int>, loaded: Bool) -> some View {
        let key = LayoutKey(root: rootID, generation: loaded ? loadedGeneration : nil, range: range,
                            size: size, insideGroup: !groupTrail.isEmpty)
        return ZStack(alignment: .topLeading) {
            if loaded && renderedKey == key {
                ForEach(regions) { region in
                    tile(region, in: range)
                        .frame(width: max(0, region.rect.width - 4), height: max(0, region.rect.height - 4))
                        .position(x: region.rect.midX, y: region.rect.midY)
                }
                if regions.isEmpty {
                    Text(weights.isEmpty ? "没有符合条件的项目" : "空间不足，请增大窗口")
                        .font(.callout).foregroundStyle(PaperAppearance.muted)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: key) {
            guard loaded else { return }
            let values = weights[range]
            let result = await Task.detached(priority: .userInitiated) {
                Treemap.readableLayout(values, in: CGRect(origin: .zero, size: key.size), insideGroup: key.insideGroup)
            }.value
            guard !Task.isCancelled else { return }
            regions = result; renderedKey = key
        }
    }

    private func tile(_ region: MapRegion, in scope: Range<Int>) -> some View {
        let grouped = region.itemRange.count > 1
        let id = weights[region.itemRange.lowerBound].id
        let selected = !grouped && id == selection
        let title = grouped
            ? (groupTrail.isEmpty ? "较小的 \(region.itemRange.count) 项" : "项目 \(region.itemRange.lowerBound - scope.lowerBound + 1)–\(region.itemRange.upperBound - scope.lowerBound)")
            : snapshot.entries[id].name
        let prominent = region.rect.width > 240 && region.rect.height > 130
        let palette = PaperAppearance.mapColors[(weights.count - region.itemRange.lowerBound - 1) % PaperAppearance.mapColors.count]
        let foreground = grouped ? PaperAppearance.text : palette.text
        let shape = RoundedRectangle(cornerRadius: prominent ? 16 : 10)
        return Button {
            if grouped { groupTrail.append(region.itemRange) }
            else { onSelect(id) }
        } label: {
            VStack(alignment: .leading, spacing: prominent ? 10 : 6) {
                HStack(spacing: 6) {
                    Image(systemName: grouped ? "square.stack" : snapshot.entries[id].kind == .directory ? "folder" : "doc")
                        .font(.system(size: prominent ? 15 : 12))
                    Text(title).font(.system(size: prominent ? 16 : 13, weight: .medium))
                        .lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 0)
                    if grouped { Image(systemName: "chevron.right").font(.system(size: 11, weight: .medium)) }
                }
                Text(formatBytes(region.logicalBytes))
                    .font(.system(size: prominent ? 32 : 14, weight: .regular, design: prominent ? .serif : .default))
                    .monospacedDigit().lineLimit(1).minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                if prominent {
                    HStack {
                        if !grouped && snapshot.entries[id].incomplete {
                            Label("统计不完整", systemImage: "exclamationmark.triangle")
                                .font(.system(size: 11))
                        }
                        Spacer()
                        if grouped || snapshot.entries[id].kind == .directory {
                            Image(systemName: "arrow.right").font(.system(size: 15))
                        }
                    }.foregroundStyle(foreground.opacity(0.85))
                }
            }
            .padding(prominent ? 18 : 12).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .foregroundStyle(foreground)
            .background {
                shape.fill(grouped ? Color(nsColor: PaperAppearance.selection) : palette.fill)
                    .overlay(shape.fill(LinearGradient(colors: [.white.opacity(0.06), .clear, .black.opacity(0.06)],
                                                       startPoint: .topLeading, endPoint: .bottomTrailing)))
                    .overlay(shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.7), .white.opacity(0.08)],
                                                              startPoint: .topLeading, endPoint: .bottomTrailing)))
            }
            .overlay(shape.strokeBorder(selected ? PaperAppearance.gold
                : hoveredIndex == region.itemRange.lowerBound || contrast == .increased ? foreground : .clear,
                lineWidth: selected ? 3 : 1))
            .overlay(shape.inset(by: 4).strokeBorder(selected ? foreground : .clear, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(GlassPressStyle())
        .help(grouped ? "查看合并的 \(region.itemRange.count) 项" : snapshot.url(for: id).path)
        .onHover { hoveredIndex = $0 ? region.itemRange.lowerBound : nil }
        .simultaneousGesture(TapGesture(count: 2).onEnded { if !grouped { onOpen(id) } })
        .accessibilityLabel("\(title)，\(formatBytes(region.logicalBytes))")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: selected)
    }
}
