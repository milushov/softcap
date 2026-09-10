import Foundation

/// How severe a report is. The names are the ones the receiving end understands;
/// they are not shown to anybody.
public enum DiagnosticLevel: String, Sendable {
    case warning
    case error
    case fatal
}

/// One thing that went wrong, in the shape the collector accepts.
///
/// Deliberately small. A crash reporter can send a screenshot, the view
/// hierarchy, every network request of the last minute and the machine's IP, and
/// the one this app talks to would store all of it. None of that is needed to
/// tell why a token refresh failed, and each of them is a way for something
/// private to leave a stranger's Mac — so the event carries a level, a category,
/// a sentence, and the failure's type. Nothing about the person, and nothing
/// about the screen.
public struct DiagnosticEvent: Sendable, Equatable {
    public let id: String
    public let level: DiagnosticLevel
    public let category: String
    public let message: String
    public let failureType: String?
    public let release: String
    public let environment: String
    public let timestamp: Date

    /// Every string is scrubbed on the way in, not on the way out.
    ///
    /// Doing it here means there is no path to the wire that skips it: a caller
    /// that assembles an event has already lost the chance to send a raw one.
    public init(
        id: String = Self.freshID(),
        level: DiagnosticLevel,
        category: String,
        message: String,
        failureType: String? = nil,
        release: String,
        environment: String,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.level = level
        self.category = Scrubber.clean(category)
        self.message = Scrubber.clean(message)
        self.failureType = failureType.map(Scrubber.clean)
        self.release = Scrubber.clean(release)
        self.environment = environment
        self.timestamp = timestamp
    }

    /// Thirty-two hex characters, no dashes — the identifier format the
    /// collector expects. A `UUID` string carries dashes and is rejected.
    public static func freshID() -> String {
        UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    }

    /// A format style rather than an `ISO8601DateFormatter`: the formatter is a
    /// class, is not `Sendable`, and cannot be held in a `static let` under
    /// Swift 6 without a lock around it. The style is a value and needs none.
    private static let stamp = Date.ISO8601FormatStyle(includingFractionalSeconds: false)

    /// The JSON body. Built by hand rather than through `Codable`: the payload
    /// is nested, half of it is optional, and the shape belongs to somebody
    /// else's API — a hand-written dictionary is the version you can read
    /// against their documentation.
    public func payload() -> [String: Any] {
        var body: [String: Any] = [
            "event_id": id,
            "timestamp": Self.stamp.format(timestamp),
            "platform": "cocoa",
            "level": level.rawValue,
            "logger": category,
            "release": release,
            "environment": environment,
            "message": ["formatted": message],
        ]
        if let failureType {
            body["exception"] = ["values": [["type": failureType, "value": message]]]
        }
        return body
    }

    public func encoded() throws -> Data {
        try JSONSerialization.data(withJSONObject: payload(), options: [.sortedKeys])
    }
}
