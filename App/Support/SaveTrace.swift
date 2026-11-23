import Combine
import CoreData
import Foundation

/// Diagnostic chain for one save. Values are the draft and the stored row, not the accessibility label.
final class SaveTrace: ObservableObject {
    static let shared = SaveTrace()

    @Published private(set) var summary = ""
    private(set) var lastClose = "none"
    private var lines: [String] = []

    func reset() {
        lines.removeAll()
        lastClose = "none"
        summary = ""
    }

    func markClosed(_ reason: String) {
        lastClose = reason
    }

    func record(_ line: String) {
        lines.append(line)
        if lines.count > 8 { lines.removeFirst(lines.count - 8) }
        summary = lines.joined(separator: " | ")
    }

    static func babyID(_ id: UUID?) -> String {
        id.map { String($0.uuidString.prefix(8)) } ?? "nil"
    }

    static func contextID(_ context: NSManagedObjectContext) -> String {
        String(UInt(bitPattern: ObjectIdentifier(context)), radix: 16)
    }
}
