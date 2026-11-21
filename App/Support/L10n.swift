import BabyLogKit
import Foundation

enum L10n {
    static var language: AppLanguage {
        let raw = UserDefaults.standard.string(forKey: AppLanguage.storageKey) ?? AppLanguage.storedDefault.rawValue
        return AppLanguage(rawValue: raw) ?? .zhHans
    }

    static var resolved: ResolvedLanguage { language.resolved() }
}
