import SwiftUI

struct MapStylePicker: View {
    @Binding var radialMap: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        ZStack(alignment: .leading) {
            Capsule()
                .fill(LinearGradient(colors: [.white.opacity(0.95), .white.opacity(0.5)],
                                     startPoint: .top, endPoint: .bottom))
                .overlay(Capsule().strokeBorder(.white.opacity(0.9), lineWidth: 1))
                .shadow(color: PaperAppearance.text.opacity(0.16), radius: 3, x: 0, y: 2)
                .frame(width: 78, height: 28)
                .offset(x: radialMap ? 0 : 78)
                .animation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.78), value: radialMap)
                .allowsHitTesting(false)
            HStack(spacing: 0) {
                segment("环图", symbol: "circle.circle", radial: true)
                segment("矩形", symbol: "rectangle.split.2x2", radial: false)
            }
        }
        .padding(4)
        .background(GlassSurface(shape: Capsule()))
        .opacity(enabled ? 1 : 0.4)
        .fixedSize()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("空间图样式")
    }

    private func segment(_ title: String, symbol: String, radial: Bool) -> some View {
        Button { radialMap = radial } label: {
            Label(title, systemImage: symbol)
                .font(.system(size: 12, weight: radialMap == radial ? .semibold : .medium))
                .foregroundStyle(radialMap == radial ? PaperAppearance.text : PaperAppearance.muted)
                .frame(width: 78, height: 28)
                .contentShape(Capsule())
        }
        .buttonStyle(GlassPressStyle())
        .accessibilityAddTraits(radialMap == radial ? .isSelected : [])
        .help(radial ? "环图 · 角度表示逻辑大小，最多三层" : "矩形 · 文件夹及大于 10 MiB 的文件，面积非等比")
    }
}
