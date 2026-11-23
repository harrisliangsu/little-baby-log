import SwiftUI
import UIKit
import BabyLogKit

/// Applies the stored appearance to the window immediately.
/// The value is the three-way setting itself. A background timer does not overwrite it.
struct AppearanceHost: ViewModifier {
    @AppStorage(Prefs.appearanceMode) private var mode: AppearanceMode = Prefs.defaultAppearanceMode
    @AppStorage(InterfaceStyle.storageKey) private var styleRaw = InterfaceStyle.classic.rawValue
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var interfaceStyle: InterfaceStyle {
        InterfaceStyle(rawValue: styleRaw) ?? .classic
    }

    private var colorScheme: ColorScheme? {
        switch mode.resolved() {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    func body(content: Content) -> some View {
        content
            .environment(\.appTheme, .standard)
            .environment(\.interfaceStyle, interfaceStyle)
            .preferredColorScheme(colorScheme)
            .background {
                if interfaceStyle == .liquidGlass, !reduceTransparency {
                    LinearGradient(
                        colors: [Color.accentColor.opacity(0.28), Color.purple.opacity(0.18)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .ignoresSafeArea()
                }
            }
            .background(alignment: .topLeading) {
                Text(interfaceStyle.rawValue)
                    .frame(width: 1, height: 1)
                    .accessibilityIdentifier("style-applied")
                    .accessibilityLabel(interfaceStyle.rawValue)
                    .allowsHitTesting(false)
            }
            .onAppear { applyWindow() }
            .onChange(of: mode) { _, _ in applyWindow() }
            .onChange(of: styleRaw) { _, _ in applyWindow() }
    }

    private func applyWindow() {
        WindowChrome.apply(mode: mode)
    }
}

enum WindowChrome {
    static func apply(mode: AppearanceMode) {
        let style: UIUserInterfaceStyle
        switch mode {
        case .light: style = .light
        case .dark: style = .dark
        case .system: style = .unspecified
        }
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        for scene in scenes {
            scene.windows.forEach { $0.overrideUserInterfaceStyle = style }
        }
    }
}

extension View {
    func appearanceHost() -> some View {
        modifier(AppearanceHost())
    }
}
