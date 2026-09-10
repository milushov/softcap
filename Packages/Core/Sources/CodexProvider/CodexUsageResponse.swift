import Foundation
import ProviderKit

public struct CodexUsageResponse: Sendable {
    public let planType: String?
    public let windows: [LimitWindow]

    /// This is the quota read endpoint, not a model inference request.
    public static func parse(_ data: Data, now: Date = Date()) throws -> Self {
        let response: Response
        do {
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            response = try decoder.decode(Response.self, from: data)
        } catch {
            throw ProviderFailure(kind: .malformed, diagnostic: "codex usage response is invalid")
        }
        var windows: [LimitWindow] = []
        for (window, fallbackID) in [(response.rateLimit.primaryWindow, "session"),
                                     (response.rateLimit.secondaryWindow, "weekly")] {
            guard let window else { continue }
            guard window.usedPercent.isFinite, (0...100).contains(window.usedPercent) else {
                throw ProviderFailure(kind: .malformed, diagnostic: "codex usage window is invalid")
            }
            // As with local rollouts, primary may be the weekly window for a
            // plan with only one limit. Its duration determines the label.
            let id = window.limitWindowSeconds.map { $0 < 86_400 ? "session" : "weekly" }
                ?? fallbackID
            let reset = window.resetAt.map { Date(timeIntervalSince1970: $0) }
                ?? window.resetAfterSeconds.map { now.addingTimeInterval($0) }
            windows.append(LimitWindow(id: id, percent: window.usedPercent, resetsAt: reset))
        }
        guard !windows.isEmpty else {
            throw ProviderFailure(kind: .noData, diagnostic: "codex usage has no quota windows")
        }
        return Self(planType: response.planType, windows: windows)
    }

    private struct Response: Decodable {
        let planType: String?
        let rateLimit: Limits
    }

    private struct Limits: Decodable {
        let primaryWindow: Window?
        let secondaryWindow: Window?
    }

    private struct Window: Decodable {
        let usedPercent: Double
        let limitWindowSeconds: Double?
        let resetAt: Double?
        let resetAfterSeconds: Double?
    }
}
