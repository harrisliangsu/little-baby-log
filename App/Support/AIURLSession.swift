import Foundation
import BabyLogKit

/// Direct URLSession. A redirect to a different host is dropped so a key cannot follow it.
final class LockedHostTransport: NSObject, URLSessionTaskDelegate, AITransport {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let session = URLSession(configuration: .ephemeral, delegate: self, delegateQueue: nil)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AIClientError.http(-1) }
        return (data, http)
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        let original = task.originalRequest?.url?.host?.lowercased()
        let next = request.url?.host?.lowercased()
        completionHandler(original == next ? request : nil)
    }
}
