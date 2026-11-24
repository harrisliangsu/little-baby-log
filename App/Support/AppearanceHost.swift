import SwiftUI
import UIKit
import BabyLogKit

/// Applies the stored appearance to the window immediately.
/// The value is the three-way setting itself. A background timer does not overwrite it.
/// The one in-memory copy of appearance and style. Settings and the window read this object,
/// so a tap updates the page that is already open instead of only the stored checkmark.
@MainActor
final class ChromeBox: ObservableObject {
    static let shared = ChromeBox()

    @Published private(set) var selection: ChromeSelection

    private init() {
        selection = ChromeSelection.load(from: .standard)
        WindowChrome.apply(mode: selection.mode)
    }

    var mode: AppearanceMode { selection.mode }
    var style: InterfaceStyle { selection.style }

    func setMode(_ mode: AppearanceMode) {
        selection = selection.choosingMode(mode)
        selection.save(to: .standard)
        WindowChrome.apply(mode: selection.mode)
    }

    func setStyle(_ style: InterfaceStyle) {
        selection = selection.choosingStyle(style)
        selection.save(to: .standard)
    }
}

struct AppearanceHost: ViewModifier {
    @ObservedObject private var chrome = ChromeBox.shared
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var interfaceStyle: InterfaceStyle { chrome.style }

    private var colorScheme: ColorScheme? {
        switch chrome.mode.resolved() {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    func body(content: Content) -> some View {
        let base = content
            .environment(\.appTheme, .standard)
            .environment(\.interfaceStyle, interfaceStyle)
        return applied(base)
    }

    /// Setting `preferredColorScheme(nil)` leaves the previous light or dark scheme in place.
    /// Follow-system removes the modifier so the open page tracks the system again.
    @ViewBuilder
    private func applied<V: View>(_ content: V) -> some View {
        if let colorScheme {
            painted(content.preferredColorScheme(colorScheme))
        } else {
            painted(content)
        }
    }

    private func painted<V: View>(_ content: V) -> some View {
        content
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
            .onAppear { WindowChrome.apply(mode: chrome.mode) }
            .onChange(of: chrome.mode) { _, mode in WindowChrome.apply(mode: mode) }
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
            scene.traitOverrides.userInterfaceStyle = style
            for window in scene.windows {
                window.overrideUserInterfaceStyle = style
                if let root = window.rootViewController {
                    stamp(style, on: root)
                }
            }
        }
    }

    /// The open settings page and any sheet keep their own controller.
    /// The window value alone does not repaint those.
    private static func stamp(_ style: UIUserInterfaceStyle, on controller: UIViewController) {
        controller.overrideUserInterfaceStyle = style
        controller.children.forEach { stamp(style, on: $0) }
        if let presented = controller.presentedViewController {
            stamp(style, on: presented)
        }
    }
}

extension View {
    func appearanceHost() -> some View {
        modifier(AppearanceHost())
    }
}
