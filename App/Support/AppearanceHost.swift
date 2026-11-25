import SwiftUI
import UIKit
import BabyLogKit

/// Applies the stored appearance to the window immediately.
/// Light and dark set the window. Follow-system clears that override.
/// A second window, a timer, or a flip counter is not used: writing the trait we just read spins the main thread.
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

    func body(content: Content) -> some View {
        content
            .environment(\.appTheme, .standard)
            .environment(\.interfaceStyle, interfaceStyle)
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
    /// `preferredColorScheme` is not used.
    /// A concrete value stays after Follow system is chosen, and `nil` does not remove it.
    /// The window override does: `.unspecified` follows the device again.
    static func apply(mode: AppearanceMode) {
        let style: UIUserInterfaceStyle
        switch mode {
        case .light: style = .light
        case .dark: style = .dark
        case .system: style = .unspecified
        }
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        for scene in scenes {
            for window in scene.windows {
                window.overrideUserInterfaceStyle = style
                window.traitOverrides.userInterfaceStyle = style
                if let root = window.rootViewController {
                    stamp(style, on: root)
                }
            }
        }
    }

    /// The open settings page and any sheet keep their own controller.
    /// `overrideUserInterfaceStyle = .unspecified` does not clear a trait override SwiftUI already applied.
    private static func stamp(_ style: UIUserInterfaceStyle, on controller: UIViewController) {
        controller.overrideUserInterfaceStyle = style
        controller.traitOverrides.userInterfaceStyle = style
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
