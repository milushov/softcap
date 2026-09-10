import Foundation
import Network
import ProviderKit

/// Only the loopback interface is exposed. Header reads may arrive in pieces;
/// incomplete or oversized requests are bounded and cannot consume an attempt.
@MainActor
final class BrowserCallbackListener {
    private var listener: NWListener?

    func start(
        port: UInt16?,
        receive: @escaping @MainActor (String, NWConnection) -> Void
    ) async throws -> UInt16 {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(
            host: .ipv4(.loopback), port: port.flatMap(NWEndpoint.Port.init(rawValue:)) ?? .any)
        let listener = try NWListener(using: parameters)
        self.listener = listener
        listener.newConnectionHandler = { connection in
            Task { @MainActor in
                connection.start(queue: .main)
                Self.read(connection, accumulated: Data(), receive: receive)
                Task {
                    try? await Task.sleep(for: .seconds(10))
                    connection.cancel()
                }
            }
        }
        return try await withCheckedThrowingContinuation { continuation in
            let once = ResumeOnce()
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    guard once.claim() else { return }
                    if let port = listener.port?.rawValue, port != 0 {
                        continuation.resume(returning: port)
                    } else {
                        continuation.resume(throwing: ProviderFailure(
                            kind: .network, diagnostic: "listener ready on port zero"))
                    }
                case .failed, .cancelled:
                    guard once.claim() else { return }
                    continuation.resume(throwing: ProviderFailure(
                        kind: .network, diagnostic: "OAuth listener could not start"))
                default: break
                }
            }
            listener.start(queue: .main)
        }
    }

    func stop() {
        // Keep the handler until cancellation has resumed a pending start.
        listener?.cancel()
        listener = nil
    }

    private static func read(
        _ connection: NWConnection, accumulated: Data,
        receive: @escaping @MainActor (String, NWConnection) -> Void
    ) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192 - accumulated.count) {
            data, _, complete, error in
            Task { @MainActor in
                var buffer = accumulated
                if let data { buffer.append(data) }
                if let request = String(data: buffer, encoding: .utf8),
                   request.contains("\r\n\r\n") || request.contains("\n\n") {
                    receive(request, connection)
                } else if error != nil || complete || buffer.count >= 8192 {
                    connection.cancel()
                } else {
                    read(connection, accumulated: buffer, receive: receive)
                }
            }
        }
    }
}

private final class ResumeOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var claimed = false

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !claimed else { return false }
        claimed = true
        return true
    }
}
