import SwiftUI
import UIKit
import BabyLogKit

/// Applies the stored appearance to the window immediately.
/// Light and dark stay as chosen. Follow-system keeps a window that is not forced, so a device change still arrives.
/// The one in-memory copy of appearance and style. Settings and the window read this object,
/// so a tap updates the page that is already open instead of only the stored checkmark.
@MainActor
final class ChromeBox: ObservableObject {
    static let shared = ChromeBox()

    @Published private(set) var selection: ChromeSelection
    /// The device appearance. Light and dark choices do not overwrite it.
    @Published private(set) var systemStyle: UIUserInterfaceStyle

    private init() {
        selection = ChromeSelection.load(from: .standard)
        let style = UIScreen.main.traitCollection.userInterfaceStyle
        systemStyle = style == .dark ? .dark : .light
        WindowChrome.apply(mode: selection.mode, system: systemStyle)
    }

    var mode: AppearanceMode { selection.mode }
    var style: InterfaceStyle { selection.style }

    /// Always a concrete scheme, so the modifier stays in place and the open page is not rebuilt.
    var colorScheme: ColorScheme {
        switch selection.mode {
        case .light: return .light
        case .dark: return .dark
        case .system: return systemStyle == .dark ? .dark : .light
        }
    }

    func noteSystem(_ style: UIUserInterfaceStyle) {
        guard style == .light || style == .dark, style != systemStyle else { return }
        systemStyle = style
    }

    func setMode(_ mode: AppearanceMode) {
        selection = selection.choosingMode(mode)
        selection.save(to: .standard)
        WindowChrome.apply(mode: selection.mode, system: systemStyle)
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
            .onAppear {
                SystemStyleRelay.install()
                WindowChrome.apply(mode: chrome.mode, system: chrome.systemStyle)
            }
            .onChange(of: chrome.mode) { _, mode in
                WindowChrome.apply(mode: mode, system: chrome.systemStyle)
            }
            .onChange(of: chrome.systemStyle) { _, style in
                guard chrome.mode == .system else { return }
                WindowChrome.apply(mode: .system, system: style)
            }
    }
}

/// A one-point window that is never forced to light or dark.
/// The app window is forced, so it cannot hear a later system change.
enum SystemStyleRelay {
    private static var window: UIWindow?

    static func install() {
        guard window == nil,
              let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else { return }
        let relay = RelayWindow(windowScene: scene)
        relay.frame = CGRect(x: -2, y: -2, width: 1, height: 1)
        relay.windowLevel = .normal - 1
        relay.overrideUserInterfaceStyle = .unspecified
        relay.rootViewController = StyleRelayController()
        relay.isHidden = false
        window = relay
    }

    static func owns(_ window: UIWindow) -> Bool {
        window === self.window
    }

    /// The app window is forced. This one must stay unset or it only echoes that force.
    static func release() {
        window?.overrideUserInterfaceStyle = .unspecified
    }
}

private final class RelayWindow: UIWindow {
    override var canBecomeKey: Bool { false }
}

private final class StyleRelayController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (controller: StyleRelayController, _: UITraitCollection) in
            let style = controller.traitCollection.userInterfaceStyle
            DispatchQueue.main.async {
                ChromeBox.shared.noteSystem(style)
            }
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        ChromeBox.shared.noteSystem(traitCollection.userInterfaceStyle)
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
        // Follow-system leaves the scene unset so the relay window still hears the device.
        let sceneStyle: UIUserInterfaceStyle = mode == .system ? .unspecified : painted
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        for scene in scenes {
            scene.traitOverrides.userInterfaceStyle = sceneStyle
            for window in scene.windows where !SystemStyleRelay.owns(window) {
                window.overrideUserInterfaceStyle = painted
                if let root = window.rootViewController {
                    stamp(painted, on: root)
                }
            }
        }
        SystemStyleRelay.release()
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
