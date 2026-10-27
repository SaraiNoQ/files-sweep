import SwiftUI
import FileSweepCore

struct SunburstMap: View {
    let snapshot: ScanSnapshot
    let rootID: Int
    let selection: Int?
    let onSelect: (Int) -> Void
    let onOpen: (Int) -> Void
    let onGroup: ([Int]?) -> Void
    @State private var sectors: [SunburstSector] = []
    @State private var loadedKey: String?
    @State private var hoveredID: Int?
    @State private var previewID: Int?
    @State private var trail: [GroupScope] = []
    @Environment(\.colorSchemeContrast) private var contrast

    private struct GroupScope {
        let id = UUID()
        let generation: UUID
        let root: Int
        let parent: Int
        let members: [Int]
        let bytes: UInt64
    }
    private var group: GroupScope? {
        guard let last = trail.last, last.generation == snapshot.generation, last.root == rootID else { return nil }
        return last
    }
    private var layoutRoot: Int { group?.parent ?? rootID }
    private var totalBytes: UInt64 { group?.bytes ?? snapshot.entries[rootID].logicalBytes }
    private var key: String { "\(snapshot.generation):\(rootID):\(group?.id.uuidString ?? "root")" }

    var body: some View {
        VStack(spacing: 12) {
            if let group {
                HStack {
                    Button(action: back) { Label("上一级分组", systemImage: "chevron.left") }
                    Text("\(group.members.count) 项").font(.system(size: 12)).foregroundStyle(PaperAppearance.muted)
                    Spacer()
                    Button("返回目录") { trail.removeAll(); onGroup(nil); onSelect(rootID) }
                }
            }
            GeometryReader { geometry in
                let side = max(0, min(geometry.size.width, geometry.size.height))
                ZStack {
                    if loadedKey == key {
                        drawing(side: side)
                            .allowsHitTesting(false).accessibilityHidden(true)
                    } else {
                        ProgressView().controlSize(.small)
                    }
                    SunburstInput(key: key, sectors: loadedKey == key ? sectors : [], ready: loadedKey == key,
                        selection: selection,
                        onSelect: { id in if let sector = current(id) { select(sector) } },
                        onActivate: { id in if let sector = current(id) { activate(sector) } },
                        onHover: { hoveredID = $0 }, onPreview: { previewID = $0 }, onBack: back)
                        .accessibilityHidden(true)
                }
                .frame(width: side, height: side)
                .overlay(alignment: .topLeading) {
                    if let previewID, let sector = current(previewID) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(title(sector)).font(.system(size: 16, weight: .semibold))
                            Text("\(formatBytes(sector.logicalBytes)) · \(percentage(sector))")
                                .font(.system(size: 20, weight: .regular, design: .serif))
                            if let id = sector.entryID {
                                Text(snapshot.url(for: id).path).font(.system(size: 11))
                                    .lineLimit(3).truncationMode(.middle)
                            } else { Text("合并项目，可进入继续浏览").font(.system(size: 12)) }
                        }.padding(16).frame(maxWidth: 280, alignment: .leading)
                            .background(GlassSurface(shape: RoundedRectangle(cornerRadius: 14)))
                            .allowsHitTesting(false).accessibilityHidden(true)
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("目录空间环图")
                .accessibilityChildren {
                    Button(group != nil ? "返回上一级分组" : "返回上一级目录", action: back)
                        .disabled(group == nil && snapshot.entries[rootID].parent == nil)
                    if loadedKey == key {
                        ForEach(sectors) { sector in
                            Button(description(sector)) { select(sector) }
                                .accessibilityAddTraits(isSelected(sector) ? .isSelected : [])
                                .accessibilityAction(named: Text("在目录中查看")) { activate(sector) }
                        }
                    }
                }
                .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
            }
            if loadedKey == key, !sectors.isEmpty {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 8) {
                    ForEach(Array(sectors.filter { $0.depth == 0 }.prefix(6))) { sector in legend(sector) }
                }.frame(height: 126, alignment: .top)
            }
        }
        .task(id: key) {
            let request = key
            let parent = layoutRoot
            let members = group?.members
            let cancellation = ScanCancellation()
            let result = await withTaskCancellationHandler {
                await Task.detached(priority: .userInitiated) {
                    Sunburst.layout(snapshot, rootID: parent, scope: members, cancellation: cancellation)
                }.value
            } onCancel: { cancellation.cancel() }
            guard !Task.isCancelled, !cancellation.isCancelled, request == key else { return }
            if group == nil { trail.removeAll() }
            sectors = result; loadedKey = request; hoveredID = nil; previewID = nil
        }
        .onDisappear { onGroup(nil) }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func drawing(side: CGFloat) -> some View {
        ZStack {
            if sectors.isEmpty {
                Circle().stroke(PaperAppearance.line, lineWidth: 1)
                Text("没有可绘制的大小\n零大小项目可在目录中查看")
                    .font(.system(size: 12)).foregroundStyle(PaperAppearance.muted)
                    .multilineTextAlignment(.center).offset(y: side * 0.27)
            }
            SunburstBase(sectors: sectors, layoutKey: key, increasedContrast: contrast == .increased).equatable()
            Canvas { context, size in
                for sector in sectors where isSelected(sector) || hoveredID == sector.id {
                    let path = RingSector(start: sector.start, end: sector.end, depth: sector.depth)
                        .path(in: CGRect(origin: .zero, size: size))
                    if hoveredID == sector.id { context.fill(path, with: .color(.white.opacity(0.12))) }
                    context.stroke(path, with: .color(isSelected(sector) ? PaperAppearance.gold : PaperAppearance.text),
                                   lineWidth: isSelected(sector) ? 3 : 2)
                }
            }
            let hovered = hoveredID.flatMap { current($0) }
            VStack(spacing: 6) {
                Image(systemName: hovered == nil ? (group == nil && snapshot.entries[rootID].parent == nil ? "folder" : "arrow.up") : "folder")
                    .font(.system(size: 15)).foregroundStyle(PaperAppearance.accent)
                Text(hovered.map { title($0) } ?? group.map { "其他（\($0.members.count) 项）" } ?? snapshot.entries[rootID].name)
                    .font(.system(size: side > 380 ? 15 : 12, weight: .semibold)).lineLimit(2).truncationMode(.middle)
                Text(formatBytes(hovered?.logicalBytes ?? totalBytes))
                    .font(.system(size: side > 380 ? 24 : 18, weight: .regular, design: .serif))
                    .monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
                if let hovered { Text(percentage(hovered)).font(.system(size: 11)).foregroundStyle(PaperAppearance.muted) }
            }.padding(8).frame(width: side * 0.29, height: side * 0.29)
                .background(GlassSurface(shape: Circle()))
        }
    }

    private func legend(_ sector: SunburstSector) -> some View {
        Button { select(sector) } label: {
            HStack(spacing: 8) {
                Circle().fill(PaperAppearance.mapColors[sector.colorIndex % PaperAppearance.mapColors.count].fill)
                    .frame(width: 7, height: 7)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title(sector)).font(.system(size: 12, weight: .medium)).lineLimit(1).truncationMode(.middle)
                    Text("\(formatBytes(sector.logicalBytes)) · \(percentage(sector))")
                        .font(.system(size: 11)).monospacedDigit().foregroundStyle(PaperAppearance.muted)
                }
                Spacer(minLength: 0)
            }.padding(.horizontal, 8).padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                .foregroundStyle(isSelected(sector) ? PaperAppearance.accent : PaperAppearance.text)
                .background(RoundedRectangle(cornerRadius: 10).fill(isSelected(sector) ? Color(nsColor: PaperAppearance.selection) : .clear))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(isSelected(sector) ? PaperAppearance.accent : .clear))
        }.buttonStyle(GlassPressStyle()).help(description(sector))
            .accessibilityAddTraits(isSelected(sector) ? .isSelected : [])
            .accessibilityAction(named: Text("在目录中查看")) { activate(sector) }
    }

    private func current(_ id: Int) -> SunburstSector? {
        guard loadedKey == key else { return nil }
        return sectors.first { $0.id == id }
    }
    private func isSelected(_ sector: SunburstSector) -> Bool { sector.entryID != nil && sector.entryID == selection }

    private func select(_ sector: SunburstSector) {
        guard loadedKey == key else { return }
        previewID = nil
        if let id = sector.entryID {
            guard snapshot.entries.indices.contains(id) else { return }
            onSelect(id)
        } else if !sector.memberIDs.isEmpty {
            hoveredID = nil; previewID = nil
            trail.append(GroupScope(generation: snapshot.generation, root: rootID, parent: sector.parentID,
                                    members: sector.memberIDs, bytes: sector.logicalBytes))
            onGroup(sector.memberIDs)
            if let first = sector.memberIDs.first { onSelect(first) }
        }
    }
    private func activate(_ sector: SunburstSector) {
        guard loadedKey == key else { return }
        guard let id = sector.entryID else { select(sector); return }
        guard snapshot.entries.indices.contains(id) else { return }
        if snapshot.entries[id].kind == .directory { onOpen(id) }
        else { onSelect(id); previewID = sector.id }
    }
    private func back() {
        guard loadedKey == key else { return }
        hoveredID = nil; previewID = nil
        if group != nil {
            trail.removeLast(); onGroup(group?.members)
            onSelect(group?.members.first ?? rootID)
        } else if let parent = snapshot.entries[rootID].parent { onOpen(parent) }
    }
    private func title(_ sector: SunburstSector) -> String {
        sector.entryID.map { snapshot.entries[$0].name } ?? "其他（\(sector.itemCount) 项）"
    }
    private func percentage(_ sector: SunburstSector) -> String {
        guard totalBytes > 0 else { return "0%" }
        return (Double(sector.logicalBytes) / Double(totalBytes)).formatted(.percent.precision(.fractionLength(1)))
    }
    private func description(_ sector: SunburstSector) -> String {
        "\(title(sector))，\(formatBytes(sector.logicalBytes))，占当前范围 \(percentage(sector))"
    }
}

private struct SunburstBase: View, Equatable {
    let sectors: [SunburstSector]
    let layoutKey: String
    let increasedContrast: Bool

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.layoutKey == rhs.layoutKey && lhs.increasedContrast == rhs.increasedContrast
    }

    var body: some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size)
            let end = CGPoint(x: size.width, y: size.height)
            let glaze = GraphicsContext.Shading.linearGradient(
                Gradient(colors: [.white.opacity(0.12), .clear, .black.opacity(0.08)]), startPoint: .zero, endPoint: end)
            let edge = GraphicsContext.Shading.linearGradient(
                Gradient(colors: [.white.opacity(0.65), .clear]), startPoint: .zero, endPoint: end)
            for sector in sectors {
                let path = RingSector(start: sector.start, end: sector.end, depth: sector.depth).path(in: rect)
                let color = PaperAppearance.mapColors[sector.colorIndex % PaperAppearance.mapColors.count].fill
                context.fill(path, with: .color(color.opacity(sector.entryID == nil ? 0.45 : 1 - Double(sector.depth) * 0.15)))
                context.fill(path, with: glaze)
                context.stroke(path, with: .color(PaperAppearance.paper), lineWidth: 1.5)
                context.stroke(path, with: edge, lineWidth: 0.8)
                if increasedContrast { context.stroke(path, with: .color(PaperAppearance.text), lineWidth: 1) }
            }
        }
    }
}

private struct RingSector: Shape {
    let start: Double
    let end: Double
    let depth: Int
    func path(in rect: CGRect) -> Path {
        guard end > start else { return Path() }
        let radius = min(rect.width, rect.height) / 2
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let from = Angle.degrees(start * 360 - 90)
        let to = Angle.degrees(end * 360 - 90)
        var path = Path()
        path.addArc(center: center, radius: radius * Sunburst.outerRadius(depth: depth), startAngle: from, endAngle: to, clockwise: false)
        path.addArc(center: center, radius: radius * Sunburst.innerRadius(depth: depth), startAngle: to, endAngle: from, clockwise: true)
        path.closeSubpath()
        return path
    }
}
