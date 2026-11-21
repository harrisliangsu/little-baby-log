import Foundation
import Network

/// Online state for the assistant gate. Starts optimistic until the first path update.
final class NetworkGate: @unchecked Sendable {
    static let shared = NetworkGate()

    private let monitor = NWPathMonitor()
    private let lock = NSLock()
    private var online = true
    private var started = false

    var isOnline: Bool {
        lock.lock()
        defer { lock.unlock() }
        return online
    }

    func start() {
        lock.lock()
        let already = started
        started = true
        lock.unlock()
        guard !already else { return }
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            self.lock.lock()
            self.online = path.status == .satisfied
            self.lock.unlock()
        }
        monitor.start(queue: DispatchQueue(label: "lbl.network"))
    }
}
