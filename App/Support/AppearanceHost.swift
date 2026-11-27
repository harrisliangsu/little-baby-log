import SwiftUI
import UIKit
import BabyLogKit

extension Notification.Name {
    /// Posted when the person picks 浅色, 深色, or 跟随系统. The window listens and updates immediately.
    static let lblAppearanceModeChanged = Notification.Name("lbl.appearanceMode.changed")
}

extension AppearanceMode {
    /// `nil` means follow the device. A concrete value is only for an explicit light or dark choice.
    var colorScheme: ColorScheme? {
        switch self {
        case .light: return .light
        case .dark: return .dark
        case .system: return nil
        }
    }
}

/// The one in-memory copy of appearance and style. Settings and the window read this object,
/// so a tap updates the checkmark on the page that is already open.
@MainActor
final class ChromeBox: ObservableObject {
    static let shared = ChromeBox()

    @Published private(set) var selection: ChromeSelection
    /// Device appearance, including after the app returns to the foreground.
    @Published private(set) var systemStyle: UIUserInterfaceStyle

    private init() {
        selection = ChromeSelection.load(from: .standard)
        systemStyle = ScreenStyle.current()
    }

    var mode: AppearanceMode { selection.mode }
    var style: InterfaceStyle { selection.style }

    func noteSystem(_ style: UIUserInterfaceStyle) {
        let resolved: UIUserInterfaceStyle = style == .dark ? .dark : .light
        guard resolved != systemStyle else { return }
        systemStyle = resolved
    }

    func setMode(_ mode: AppearanceMode) {
        selection = selection.choosingMode(mode)
        selection.save(to: .standard)
        if mode == .system {
            noteSystem(ScreenStyle.current())
        }
        NotificationCenter.default.post(name: .lblAppearanceModeChanged, object: mode)
    }

    func setStyle(_ style: InterfaceStyle) {
        selection = selection.choosingStyle(style)
        selection.save(to: .standard)
    }
}

/// The device's light or dark setting, not a style this app has forced on a window.
enum ScreenStyle {
    static func current() -> UIUserInterfaceStyle {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        for scene in scenes {
            let style = scene.screen.traitCollection.userInterfaceStyle
            if style == .light || style == .dark { return style }
        }
        return UIScreen.main.traitCollection.userInterfaceStyle == .dark ? .dark : .light
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
            .background {
                DeviceStyleReader { style in
                    chrome.noteSystem(style)
                }
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
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

/// A sheet keeps its own hosting controller. The window preference updates pages already
/// on the stack; the sheet content has to ask for the same scheme or it stays on the old one.
struct AdoptedAppearance: ViewModifier {
    @ObservedObject private var chrome = ChromeBox.shared

    func body(content: Content) -> some View {
        content.preferredColorScheme(chrome.mode.colorScheme)
    }
}

extension View {
    func appearanceHost() -> some View {
        modifier(AppearanceHost())
    }

    func adoptedAppearance() -> some View {
        modifier(AdoptedAppearance())
    }
}

/// Reports device appearance changes while 跟随系统 is in effect, including a change
/// that happened while the app was in the background.
private struct DeviceStyleReader: UIViewControllerRepresentable {
    var onChange: (UIUserInterfaceStyle) -> Void

    func makeUIViewController(context: Context) -> Reader {
        let reader = Reader()
        reader.onChange = onChange
        return reader
    }

    func updateUIViewController(_ controller: Reader, context: Context) {
        controller.onChange = onChange
    }

    final class Reader: UIViewController {
        var onChange: ((UIUserInterfaceStyle) -> Void)?

        override func viewDidLoad() {
            super.viewDidLoad()
            view.isUserInteractionEnabled = false
            view.backgroundColor = .clear
            registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (reader: Reader, _) in
                reader.report()
            }
        }

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            report()
        }

        private func report() {
            onChange?(ScreenStyle.current())
        }
    }
}
