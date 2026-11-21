import SwiftUI

/// iOS 26 Liquid Glass, with a material fallback and a solid fill when Reduce Transparency is on.
struct GlassChrome: ViewModifier {
    var solid: Color
    var reduceTransparency: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceTransparency {
            content.background(solid, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        } else if #available(iOS 26.0, *) {
            content.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        } else {
            content.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }
}

extension View {
    func glassChrome(solid: Color, reduceTransparency: Bool) -> some View {
        modifier(GlassChrome(solid: solid, reduceTransparency: reduceTransparency))
    }
}
