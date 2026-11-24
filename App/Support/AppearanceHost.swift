import SwiftUI
import UIKit
import BabyLogKit

/// Applies the stored appearance to the window immediately.
/// Light and dark stay as chosen. Follow-system is the only mode that tracks the device.
/// The one in-memory copy of appearance and style. Settings and the window read this object,
/// so a tap updates the page that is already open instead of only the stored checkmark.
@MainActor
final class ChromeBox: ObservableObject {
    static let shared = ChromeBox()

    @Published private(set) var selection: ChromeSelection
    /// The system appearance, kept even while the user has chosen light or dark.
    @Published private(set) var systemStyle: UIUserInterfaceStyle

    private var traitToken: (any UITraitChangeRegistration)?
    private var systemWatch: Timer?

    private init() {
        selection = ChromeSelection.load(from: .standard)
        systemStyle = UIScreen.main.traitCollection.userInterfaceStyle
        WindowChrome.apply(mode: selection.mode, system: systemStyle)
        traitToken = UIScreen.main.registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (screen: UIScreen, _: UITraitCollection) in
            let style = screen.traitCollection.userInterfaceStyle
            DispatchQueue.main.async {
                ChromeBox.shared.noteSystem(style)
            }
        }
        watchSystem()
    }

    var mode: AppearanceMode { selection.mode }
    var style: InterfaceStyle { selection.style }

    /// Always a concrete scheme. `preferredColorScheme(nil)` leaves the previous light or dark page in place.
    var colorScheme: ColorScheme {
        switch selection.mode {
        case .light: return .light
        case .dark: return .dark
        case .system: return systemStyle == .dark ? .dark : .light
        }
    }

    func noteSystem(_ style: UIUserInterfaceStyle) {
        guard style == .light || style == .dark else { return }
        guard style != systemStyle else { return }
        systemStyle = style
        if selection.mode == .system {
            WindowChrome.apply(mode: .system, system: style)
        }
    }

    /// Follow-system reads the device style on a short interval.
    /// A window override can hide the trait callback, and this does not change a chosen light or dark mode.
    private func watchSystem() {
        systemWatch?.invalidate()
        guard selection.mode == .system else {
            systemWatch = nil
            return
        }
        let timer = Timer(timeInterval: 0.5, repeats: true) { _ in
            DispatchQueue.main.async {
                ChromeBox.shared.noteSystem(UIScreen.main.traitCollection.userInterfaceStyle)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        systemWatch = timer
    }

    func setMode(_ mode: AppearanceMode) {
        selection = selection.choosingMode(mode)
        selection.save(to: .standard)
        WindowChrome.apply(mode: selection.mode, system: systemStyle)
        watchSystem()
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
            .onAppear { WindowChrome.apply(mode: chrome.mode, system: chrome.systemStyle) }
            .onChange(of: chrome.mode) { _, mode in
                WindowChrome.apply(mode: mode, system: chrome.systemStyle)
            }
            .onChange(of: chrome.systemStyle) { _, style in
                guard chrome.mode == .system else { return }
                WindowChrome.apply(mode: .system, system: style)
            }
    }
}

enum WindowChrome {
    static func apply(mode: AppearanceMode, system: UIUserInterfaceStyle) {
        let painted: UIUserInterfaceStyle
        switch mode {
        case .light: painted = .light
        case .dark: painted = .dark
        case .system: painted = system == .dark ? .dark : .light
        }
        // Follow-system leaves the scene itself unset so a later system change is still visible.
        let sceneStyle: UIUserInterfaceStyle = mode == .system ? .unspecified : painted
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        for scene in scenes {
            scene.traitOverrides.userInterfaceStyle = sceneStyle
            for window in scene.windows {
                window.overrideUserInterfaceStyle = painted
                if let root = window.rootViewController {
                    stamp(painted, on: root)
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
