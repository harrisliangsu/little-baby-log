import BabyLogKit
import SwiftUI

enum L10n {
    static var language: AppLanguage {
        let raw = UserDefaults.standard.string(forKey: AppLanguage.storageKey) ?? AppLanguage.storedDefault.rawValue
        return AppLanguage(rawValue: raw) ?? .zhHans
    }

    static var resolved: ResolvedLanguage { language.resolved() }
}

private struct UILanguageKey: EnvironmentKey {
    static let defaultValue = ResolvedLanguage.zh
}

extension EnvironmentValues {
    var uiLanguage: ResolvedLanguage {
        get { self[UILanguageKey.self] }
        set { self[UILanguageKey.self] = newValue }
    }
}
