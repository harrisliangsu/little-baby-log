import SwiftUI
import UIKit
import BabyLogKit

/// Applies the stored appearance to the window immediately.
/// The value is the three-way setting itself. A background timer does not overwrite it.
struct AppearanceHost: ViewModifier {
    @AppStorage(Prefs.appearanceMode) private var mode: AppearanceMode = Prefs.defaultAppearanceMode
    @AppStorage(InterfaceStyle.storageKey) private var styleRaw = InterfaceStyle.classic.rawValue

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
            .onAppear { applyWindow() }
            .onChange(of: mode) { _, _ in applyWindow() }
    }

    private func applyWindow() {
        let style: UIUserInterfaceStyle
        switch colorScheme {
        case .light: style = .light
        case .dark: style = .dark
        default: style = .unspecified
        }
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows {
                window.overrideUserInterfaceStyle = style
            }
        }
    }
}

extension View {
    func appearanceHost() -> some View {
        modifier(AppearanceHost())
    }
}
