import Foundation
import ProviderKit

/// The one way a failure becomes a report.
///
/// An actor because it is written once at launch and read from wherever
/// something went wrong, which on this app means the main actor, a polling task,
/// and the update installer — three places that have no ordering between them.
///
/// Everything is off until `start` is called with `enabled: true`, and the flag
/// is re-read rather than cached at launch: the setting can be switched off
/// while the app is running, and the next report has to notice. `report` on a
/// stopped instance does nothing at all — it does not queue, so turning
/// reporting off does not leave a spool of events waiting to be sent the moment
/// somebody turns it back on.
public actor Diagnostics {
    public static let shared = Diagnostics()

    private var reporter: (any ErrorReporting)?
    private var release = "unknown"
    private var environment = "production"
    private var enabled = false

    public init() {}

    // MARK: - the destination that ships

    /// The collector this app reports to.
    ///
    /// `sentry.softcap.app` rather than the host the same server answers to for
    /// the author's other projects: this repository is public, and a hostname
    /// committed here is published with it. The name is the only part of the
    /// arrangement a reader of the source should have to learn about.
    ///
    /// `NothingElseLeavesYourMac` knows about this host. Adding another means
    /// naming it there, which is the point of that list.
    public static let shipped = Destination(
        endpoint: URL(string: "https://sentry.softcap.app/api/29/store/")!,
        key: "a857d91eefd64e4489804d85c92ff43f"
    )

    // MARK: - lifecycle

    public func start(
        reporter: any ErrorReporting,
        release: String,
        environment: String = "production",
        enabled: Bool
    ) {
        self.reporter = reporter
        self.release = release
        self.environment = environment
        self.enabled = enabled
    }

    /// Follows the setting while the app is running.
    public func setEnabled(_ on: Bool) { enabled = on }

    public var isEnabled: Bool { enabled && reporter != nil }

    // MARK: - reporting

    @discardableResult
    public func report(
        _ level: DiagnosticLevel,
        category: String,
        message: String,
        failureType: String? = nil
    ) async -> Bool {
        guard enabled, let reporter else { return false }
        let event = DiagnosticEvent(
            level: level,
            category: category,
            message: message,
            failureType: failureType,
            release: release,
            environment: environment
        )
        return await reporter.send(event)
    }

    /// The shape almost every call site has: something threw, and the catch
    /// block already knows which part of the app it was in.
    ///
    /// Takes a `ProviderFailure` rather than `any Error` because this is an
    /// actor and `any Error` is not `Sendable` — a general version would not
    /// cross the boundary under Swift 6 without every call site wrapping its
    /// error first, which is the wrapping this method exists to save.
    /// `ProviderFailure` is `Sendable`, and is what the layers that fail here
    /// throw. Anything else goes through `report(_:category:message:)` with a
    /// type name the caller has already turned into a string.
    ///
    /// The `diagnostic` is carried rather than the kind alone: it is written in
    /// English for the log and says what actually failed, where the kind by
    /// itself would collapse every network problem in the app into one entry.
    @discardableResult
    public func report(_ failure: ProviderFailure, category: String) async -> Bool {
        await report(
            .error,
            category: category,
            message: failure.diagnostic,
            failureType: "ProviderFailure.\(failure.kind)"
        )
    }
}
