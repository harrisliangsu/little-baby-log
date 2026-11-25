import SwiftUI
import UIKit
import BabyLogKit

/// Applies the stored appearance to the window immediately.
/// Light and dark set the window and a concrete color scheme.
/// Follow-system reads the device style when the app becomes active again.
/// The one in-memory copy of appearance and style. Settings and the window read this object,
/// so a tap updates the page that is already open instead of only the stored checkmark.
@MainActor
final class ChromeBox: ObservableObject {
    static let shared = ChromeBox()

    @Published private(set) var selection: ChromeSelection
    /// Device appearance, refreshed when the app becomes active.
    @Published private(set) var systemStyle: UIUserInterfaceStyle

    private init() {
        selection = ChromeSelection.load(from: .standard)
        let style = UIScreen.main.traitCollection.userInterfaceStyle
        systemStyle = style == .dark ? .dark : .light
        WindowChrome.apply(mode: selection.mode)
    }

    var mode: AppearanceMode { selection.mode }
    var style: InterfaceStyle { selection.style }

    /// The modifier stays in place. Follow-system uses the device style read on the next activation.
    var colorScheme: ColorScheme {
        switch selection.mode {
        case .light: return .light
        case .dark: return .dark
        case .system: return systemStyle == .dark ? .dark : .light
        }
    }

    func noteSystem(_ style: UIUserInterfaceStyle) {
        guard mode == .system else { return }
        guard style == .light || style == .dark, style != systemStyle else { return }
        systemStyle = style
    }

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
    @Environment(\.scenePhase) private var scenePhase

    private var interfaceStyle: InterfaceStyle { chrome.style }

    func body(content: Content) -> some View {
        content
            .environment(\.appTheme, .standard)
            .environment(\.interfaceStyle, interfaceStyle)
            .preferredColorScheme(chrome.colorScheme)
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
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                chrome.noteSystem(WindowChrome.deviceStyle())
            }
            .background(alignment: .topLeading) {
                Text(chrome.systemStyle == .dark ? "dark" : "light")
                    .frame(width: 1, height: 1)
                    .accessibilityIdentifier("appearance-read")
                    .accessibilityLabel(chrome.systemStyle == .dark ? "dark" : "light")
                    .allowsHitTesting(false)
            }
    }
}

@MainActor
enum WindowChrome {
    static func deviceStyle() -> UIUserInterfaceStyle {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        for scene in scenes {
            let style = scene.screen.traitCollection.userInterfaceStyle
            if style == .dark || style == .light { return style }
        }
        return UIScreen.main.traitCollection.userInterfaceStyle == .dark ? .dark : .light
    }

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
