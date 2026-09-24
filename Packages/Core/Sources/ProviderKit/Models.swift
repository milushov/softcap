import Foundation

public enum ProviderID: String, Sendable, Hashable, Codable, CaseIterable {
    case claude, codex, cursor, copilot, gemini

    /// The service caption shown in an account row.
    public var title: String {
        switch self {
        case .claude:  "Claude"
        case .codex:   "Codex"
        case .cursor:  "Cursor"
        case .copilot: "Copilot"
        case .gemini:  "Gemini"
        }
    }

    /// Whether this service issues a refresh token that has to be rotated.
    ///
    /// The store reads it to decide what an account holding no refresh token
    /// means. For a service that rotates, it means the grant has been spent and
    /// the only way forward is a new sign-in — that is the guard which stops a
    /// dead Claude account from being retried on every poll until somebody
    /// notices. For a service that does not, it is the normal resting state of
    /// a working account, and refusing it would report "sign in again" about a
    /// token that answers.
    ///
    /// `true` is the answer for anything not yet implemented, because of the
    /// two possible mistakes it is the visible one: a rotating service wrongly
    /// marked as static would go on serving a token the server has retired,
    /// which arrives as an unexplained failure, while a static service wrongly
    /// marked as rotating asks for a sign-in that plainly works.
    public var rotatesCredentials: Bool {
        switch self {
        case .claude, .codex, .cursor, .gemini: true
        // A device grant for a public GitHub client does not expire and comes
        // with nothing to rotate. GitHub can be configured to expire tokens, and
        // when it is, the reply carries a refresh token and the ordinary path
        // takes over — this flag only decides what the *absence* of one means.
        case .copilot: false
        }
    }
}

public enum Severity: Sendable, Hashable, Codable {
    case ok, warning, hot, critical

    public init(percent: Double) {
        switch percent {
        case ..<50:  self = .ok
        case ..<75:  self = .warning
        case ..<90:  self = .hot
        default:     self = .critical
        }
    }
}

public struct LimitWindow: Sendable, Hashable, Codable, Identifiable {
    /// `session`, `weekly` or `premium` — the last being a monthly allowance,
    /// named for what it counts rather than for its period because the service
    /// reports three kinds of allowance and this is the one drawn.
    ///
    /// The label is chosen by the app layer: it depends on the language, and a
    /// model has no business knowing one. Two places size themselves from the
    /// full list rather than from one row's window — `MinimalAccountRow`'s
    /// period column and `TheRowsLineUp` — so a fourth identifier is added
    /// there as well as here.
    public let id: String
    public let percent: Double   // 0…100
    public let resetsAt: Date?

    public init(id: String, percent: Double, resetsAt: Date?) {
        self.id = id
        self.percent = percent
        self.resetsAt = resetsAt
    }

    public var severity: Severity { Severity(percent: percent) }

    /// Time left until the reset, relative to the moment given.
    public func remaining(from now: Date) -> TimeInterval? {
        resetsAt.map { $0.timeIntervalSince(now) }
    }
}

public enum Freshness: Sendable, Hashable, Codable {
    case live(Date)       // fetched by request
    case snapshot(Date)   // read from a local file

    public var capturedAt: Date {
        switch self {
        case .live(let d), .snapshot(let d): d
        }
    }

    public var isStale: Bool {
        if case .snapshot = self { return true }
        return false
    }
}

public struct ProviderFailure: Sendable, Hashable, Codable, Error {
    /// `needsPermission` was here until the app stopped reading any keychain
    /// item but its own: it meant "the keychain would have to ask, and nobody is
    /// looking", which cannot happen when the only read refuses the dialog
    /// outright. A stored snapshot written by an older build may still name it —
    /// `AccountSnapshot`'s decoder takes an unreadable failure as no failure, so
    /// such a row loses its label rather than the whole row.
    public enum Kind: Sendable, Hashable, Codable {
        case needsLogin   // the token is dead, a sign-in is required
        case network      // the network is unreachable
        case noData       // the source is empty
        case malformed    // the response could not be parsed
    }

    public let kind: Kind
    /// Detail for the log, not for a person: a server status code, the name of
    /// a missing file. Interface text is built from `kind`.
    public let diagnostic: String

    public init(kind: Kind, diagnostic: String = "") {
        self.kind = kind
        self.diagnostic = diagnostic
    }
}

public struct AccountSnapshot: Sendable, Hashable, Codable, Identifiable {
    public let id: String            // "claude/<uuid>"
    public let provider: ProviderID
    public let displayName: String   // email or name
    public let planLabel: String     // "Max 20x", "Plus"
    public let windows: [LimitWindow]
    public let freshness: Freshness
    public let failure: ProviderFailure?

    public init(
        id: String, provider: ProviderID, displayName: String, planLabel: String,
        windows: [LimitWindow], freshness: Freshness, failure: ProviderFailure?
    ) {
        self.id = id
        self.provider = provider
        self.displayName = displayName
        self.planLabel = planLabel
        self.windows = windows
        self.freshness = freshness
        self.failure = failure
    }

    /// Decoded field by field, because this is what the widget reads.
    ///
    /// A row without an `id` or a provider is not a row and is refused. Anything
    /// else falls back: a name to the identifier, a plan to a dash, no windows to
    /// none, an unreadable freshness to "we do not know when". The alternative is
    /// what the synthesised decoder does — refuse the row, which in the widget's
    /// hands becomes "No accounts found", said about accounts that exist.
    public init(from decoder: any Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        id = try box.decode(String.self, forKey: .id)
        provider = try box.decode(ProviderID.self, forKey: .provider)
        displayName = ((try? box.decodeIfPresent(String.self, forKey: .displayName)) ?? nil) ?? id
        planLabel = ((try? box.decodeIfPresent(String.self, forKey: .planLabel)) ?? nil) ?? "—"
        windows = ((try? box.decodeIfPresent([LimitWindow].self, forKey: .windows)) ?? nil) ?? []
        freshness = ((try? box.decodeIfPresent(Freshness.self, forKey: .freshness)) ?? nil)
            ?? .snapshot(Date(timeIntervalSince1970: 0))
        failure = (try? box.decodeIfPresent(ProviderFailure.self, forKey: .failure)) ?? nil
    }

    /// The busiest window — colour and list position are derived from it.
    public var peakWindow: LimitWindow? {
        windows.max { $0.percent < $1.percent }
    }

    public var peakPercent: Double { peakWindow?.percent ?? 0 }
}

/// One reading of one limit window, kept so it can be drawn later.
public struct UsageSample: Codable, Sendable, Hashable {
    public let at: Date
    public let accountID: String
    public let windowID: String
    public let percent: Double

    public init(at: Date, accountID: String, windowID: String, percent: Double) {
        self.at = at
        self.accountID = accountID
        self.windowID = windowID
        self.percent = percent
    }
}
