import SwiftUI

/// Glass belongs on bars and small controls. Content cards stay solid so text stays readable.
struct ControlChrome: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        if reduceTransparency {
            content
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color(.secondarySystemBackground), in: Capsule())
        } else if #available(iOS 26.0, *) {
            content
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .glassEffect(.regular, in: Capsule())
        } else {
            content
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial, in: Capsule())
        }
    }
}

extension View {
    /// Leaves iOS 26 navigation and tab bars on the system glass. Older systems get a material bar,
    /// and Reduce Transparency keeps the system opaque bars.
    func systemBarChrome() -> some View {
        modifier(SystemBarChrome())
    }

    func controlChrome() -> some View {
        modifier(ControlChrome())
    }
}

private struct SystemBarChrome: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        if reduceTransparency {
            content
        } else if #available(iOS 26.0, *) {
            content
        } else {
            content.toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        }
    }
}
