import SwiftUI
import BabyLogKit

private struct InterfaceStyleKey: EnvironmentKey {
    static let defaultValue = InterfaceStyle.classic
}

extension EnvironmentValues {
    var interfaceStyle: InterfaceStyle {
        get { self[InterfaceStyleKey.self] }
        set { self[InterfaceStyleKey.self] = newValue }
    }
}
