import Foundation
import ProviderKit

/// Where reports are sent, and the key that identifies the project to the
/// collector.
///
/// The key is not a secret. It authorises writing an event and nothing else —
/// it cannot read one back, and it ships inside every copy of the app, so
/// treating it as confidential would be a fiction. What it does buy anyone who
/// finds it is the ability to post junk, which is why the project it points at
/// has a throttle set on the far end rather than a guard on this one.
public struct Destination: Sendable, Equatable {
    public let endpoint: URL
    public let key: String

    public init(endpoint: URL, key: String) {
        self.endpoint = endpoint
        self.key = key
    }
}

/// Somewhere a report can go. A protocol so the tests never reach the network,
/// for the same reason `HTTPClient` is one.
public protocol ErrorReporting: Sendable {
    /// Answers whether the report was accepted. Callers ignore it; the tests do
    /// not, and a silent `Void` would make a broken transport indistinguishable
    /// from a working one.
    @discardableResult
    func send(_ event: DiagnosticEvent) async -> Bool
}

/// Posts an event to a Sentry-compatible collector.
///
/// It builds no `URLRequest` of its own. `NothingElseLeavesYourMac` holds that
/// exactly one file in this project turns a URL into traffic, and the whole
/// value of that rule is that the list of hosts beside it is complete — a
/// reporter that opened its own socket would be the first thing to make that
/// list a guess. So this goes through `HTTPClient` like every provider does.
public struct CollectorReporter: ErrorReporting {
    private let http: any HTTPClient
    private let destination: Destination
    private let client: String

    public init(http: any HTTPClient, destination: Destination, client: String) {
        self.http = http
        self.destination = destination
        self.client = client
    }

    @discardableResult
    public func send(_ event: DiagnosticEvent) async -> Bool {
        guard let body = try? event.encoded() else { return false }

        // The collector takes its credentials in a header of its own rather than
        // in `Authorization`, and wants the protocol version named explicitly.
        let auth = [
            "Sentry sentry_version=7",
            "sentry_client=\(client)",
            "sentry_key=\(destination.key)",
        ].joined(separator: ", ")

        do {
            let (_, status) = try await http.post(
                destination.endpoint,
                headers: ["Content-Type": "application/json", "X-Sentry-Auth": auth],
                body: body
            )
            return (200..<300).contains(status)
        } catch {
            // A report that cannot be delivered is dropped, not retried and not
            // surfaced. The app was already in the middle of handling a failure
            // when it got here; turning a telemetry outage into a second visible
            // problem would be the tail wagging the dog.
            return false
        }
    }
}
