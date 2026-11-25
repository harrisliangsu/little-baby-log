import SwiftUI
import UIKit
import BabyLogKit

/// Applies the stored appearance to the window immediately.
/// Light and dark set the window. Follow-system clears that override and copies later device changes into the color scheme.
/// The listener does not write the window again. Writing the trait just read spins the main thread.
/// The one in-memory copy of appearance and style. Settings and the window read this object,
/// so a tap updates the page that is already open instead of only the stored checkmark.
@MainActor
final class ChromeBox: ObservableObject {
    static let shared = ChromeBox()

    @Published private(set) var selection: ChromeSelection
    /// The device appearance. Explicit light and dark do not change it.
    @Published private(set) var systemStyle: UIUserInterfaceStyle

    private init() {
        selection = ChromeSelection.load(from: .standard)
        let style = UIScreen.main.traitCollection.userInterfaceStyle
        systemStyle = style == .dark ? .dark : .light
        WindowChrome.apply(mode: selection.mode)
    }

    var mode: AppearanceMode { selection.mode }
    var style: InterfaceStyle { selection.style }

    /// Always a concrete scheme, so the modifier stays put and the open page is not rebuilt.
    /// Follow-system uses the device style the window reports after its override is cleared.
    var colorScheme: ColorScheme {
        switch selection.mode {
        case .light: return .light
        case .dark: return .dark
        case .system: return systemStyle == .dark ? .dark : .light
        }
    }

    func noteSystem(_ style: UIUserInterfaceStyle) {
        guard selection.mode == .system else { return }
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
    }
}

@MainActor
enum WindowChrome {
    private static var listeners: [ObjectIdentifier: any UITraitChangeRegistration] = [:]

    static func apply(mode: AppearanceMode) {
        let style: UIUserInterfaceStyle
        switch mode {
        case .light: style = .light
        case .dark: style = .dark
        case .system: style = .unspecified
        }
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        for scene in scenes {
            listen(scene)
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

    /// The scene stays unforced, so a later device change still arrives here.
    /// The callback only stores the style. It does not write the window.
    private static func listen(_ scene: UIWindowScene) {
        let id = ObjectIdentifier(scene)
        guard listeners[id] == nil else { return }
        listeners[id] = scene.registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (scene: UIWindowScene, _: UITraitCollection) in
            let style = scene.traitCollection.userInterfaceStyle
            DispatchQueue.main.async {
                ChromeBox.shared.noteSystem(style)
            }
        }
    }
}

extension View {
    func appearanceHost() -> some View {
        modifier(AppearanceHost())
    }
}
