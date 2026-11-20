import Foundation

enum AppConfig {
    /// Read from Info.plist key `LBLCloudKitContainer` (`$(CLOUDKIT_CONTAINER)`).
    /// nil when empty or when the build setting was never expanded.
    static var cloudKitContainerIdentifier: String? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "LBLCloudKitContainer") as? String else {
            return nil
        }
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty || value.contains("$(") { return nil }
        return value
    }

    /// Corresponding source for this fork. Upstream remains Mo Garber's repository.
    static let sourceCodeURL = URL(string: "https://github.com/harrisliangsu/little-baby-log")!
    static let upstreamSourceCodeURL = URL(string: "https://github.com/mogarber/little-baby-log")!

    static var versionString: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}
