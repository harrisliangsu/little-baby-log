import CloudKit
import Foundation

/// A sync or sharing failure in plain language, with the technical text kept alongside so a tester can still send it.
///
/// CloudKit errors arrive wrapped in several layers (Core Data's "mirroring delegate" error around a `CKError`,
/// partial failures, underlying errors). `classify` looks through all of them for the most useful cause.
public struct CloudSyncProblem: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        /// No iCloud account on this phone (or it is temporarily signed out).
        case notSignedIn
        /// iCloud is restricted on this phone (Screen Time, a managed device).
        case restricted
        /// No internet connection.
        case offline
        /// The person's iCloud storage is full.
        case storageFull
        /// iCloud asked us to slow down or is briefly unavailable.
        case busy
        /// This build has iCloud turned off.
        case syncOff
        /// The server rejected the write. Production has no record types until a development build initializes them.
        case schemaNotReady
        /// Anything else. The details tell the story.
        case other
    }

    public var kind: Kind
    /// What to show the person.
    public var message: String
    /// The raw error text and codes, for the "Details" disclosure.
    public var technicalDetails: String

    public init(kind: Kind, message: String, technicalDetails: String) {
        self.kind = kind
        self.message = message
        self.technicalDetails = technicalDetails
    }

    public static func message(for kind: Kind, language: ResolvedLanguage = .en) -> String {
        switch (kind, language) {
        case (.notSignedIn, .zh): return "请登录 iCloud。"
        case (.notSignedIn, .en): return "Sign in to iCloud in Settings to share."
        case (.restricted, .zh): return "iCloud 受限。"
        case (.restricted, .en): return "iCloud is restricted on this phone, so sharing isn't available."
        case (.offline, .zh): return "没有网络。记录仍在这台手机。"
        case (.offline, .en): return "You're offline. Connect to the internet and try again."
        case (.storageFull, .zh): return "iCloud 空间已满。记录仍在这台手机。"
        case (.storageFull, .en): return "Your iCloud storage is full. Free up space or get more storage in Settings, then try again."
        case (.busy, .zh): return "过几分钟再试。记录仍在这台手机。"
        case (.busy, .en): return "iCloud is busy right now. Try again in a few minutes."
        case (.syncOff, .zh): return "iCloud 同步已关闭。"
        case (.syncOff, .en): return "iCloud sync is turned off in this build."
        case (.schemaNotReady, .zh): return "iCloud 还不能同步。记录仍在这台手机。"
        case (.schemaNotReady, .en): return "iCloud can't sync yet. Records on this phone are still here."
        case (.other, .zh): return "iCloud 这会儿同步不了。记录仍在这台手机。"
        case (.other, .en): return "iCloud sync isn't working right now."
        }
    }

    public static func classify(_ error: Error, language: ResolvedLanguage = .en) -> CloudSyncProblem {
        var kinds: [Kind] = []
        var lines: [String] = []
        var seen = Set<ObjectIdentifier>()
        walk(error as NSError, depth: 0, seen: &seen, kinds: &kinds, lines: &lines)
        if case .cloudSyncDisabled? = error as? SharingError { kinds.append(.syncOff) }

        let kind = kinds.min(by: { priority($0) < priority($1) }) ?? .other
        var details = lines.joined(separator: "\n")
        if details.count > 3000 { details = String(details.prefix(3000)) + "…" }
        return CloudSyncProblem(kind: kind, message: message(for: kind, language: language), technicalDetails: details)
    }

    // MARK: Walking the error chain

    private static func priority(_ kind: Kind) -> Int {
        switch kind {
        case .syncOff: return 0
        case .notSignedIn: return 1
        case .restricted: return 2
        case .storageFull: return 3
        case .offline: return 4
        case .busy: return 5
        case .schemaNotReady: return 6
        case .other: return 7
        }
    }

    private static func walk(
        _ error: NSError,
        depth: Int,
        seen: inout Set<ObjectIdentifier>,
        kinds: inout [Kind],
        lines: inout [String]
    ) {
        guard depth < 6, seen.insert(ObjectIdentifier(error)).inserted else { return }
        let indent = String(repeating: "  ", count: depth)
        lines.append("\(indent)\(error.localizedDescription) [\(error.domain) \(error.code)]")
        if let kind = kind(of: error) { kinds.append(kind) }
        if mentionsMissingSchema(error) { kinds.append(.schemaNotReady) }

        var nested: [NSError] = []
        if let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError { nested.append(underlying) }
        if let many = error.userInfo["NSUnderlyingErrors"] as? [NSError] { nested += many }
        if let partial = error.userInfo[CKPartialErrorsByItemIDKey] as? [AnyHashable: Error] {
            nested += partial.values.prefix(5).map { $0 as NSError }
        }
        for child in nested {
            walk(child, depth: depth + 1, seen: &seen, kinds: &kinds, lines: &lines)
        }
    }

    private static func kind(of error: NSError) -> Kind? {
        switch error.domain {
        case CKError.errorDomain:
            switch CKError.Code(rawValue: error.code) {
            case .notAuthenticated, .accountTemporarilyUnavailable: return .notSignedIn
            case .managedAccountRestricted: return .restricted
            case .quotaExceeded: return .storageFull
            case .networkUnavailable, .networkFailure: return .offline
            case .serviceUnavailable, .requestRateLimited, .zoneBusy: return .busy
            case .serverRejectedRequest: return .schemaNotReady
            default: return nil
            }
        case NSURLErrorDomain:
            switch error.code {
            case NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost, NSURLErrorDataNotAllowed,
                 NSURLErrorInternationalRoamingOff, NSURLErrorCannotConnectToHost, NSURLErrorTimedOut:
                return .offline
            default:
                return nil
            }
        default:
            return nil
        }
    }

    private static func mentionsMissingSchema(_ error: NSError) -> Bool {
        let text = error.localizedDescription
        return text.localizedCaseInsensitiveContains("production schema")
            || text.localizedCaseInsensitiveContains("cannot create new type")
            || text.localizedCaseInsensitiveContains("failed to modify some record zones")
    }
}
