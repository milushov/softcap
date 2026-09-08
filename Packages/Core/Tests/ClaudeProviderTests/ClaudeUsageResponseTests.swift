import Testing
import Foundation
import ProviderKit
@testable import ClaudeProvider

private func data(_ s: String) -> Data { s.data(using: .utf8)! }

private let fullResponse = """
{"five_hour":{"utilization":5.0,"resets_at":"2026-08-30T14:00:00.277644+00:00"},
 "seven_day":{"utilization":23.0,"resets_at":"2026-09-05T10:00:00.277667+00:00"},
 "limits":[
   {"kind":"session","group":"session","percent":5,"severity":"normal",
    "resets_at":"2026-08-30T14:00:00.277644+00:00","scope":null,"is_active":false},
   {"kind":"weekly_all","group":"weekly","percent":23,"severity":"normal",
    "resets_at":"2026-09-05T10:00:00.277667+00:00","scope":null,"is_active":true},
   {"kind":"weekly_scoped","group":"weekly","percent":7,"severity":"normal",
    "resets_at":"2026-09-05T10:00:00.277935+00:00",
    "scope":{"model":{"id":null,"display_name":"Fable"}},"is_active":false}]}
"""

@Test func readsSessionAndWeeklyFromLimits() throws {
    let windows = try ClaudeUsageResponse.windows(from: data(fullResponse))
    #expect(windows.count == 2)

    #expect(windows[0].id == "session")
    #expect(windows[0].percent == 5)

    #expect(windows[1].id == "weekly")
    #expect(windows[1].percent == 23)
}

@Test func dropsPerModelScopedWindow() throws {
    let windows = try ClaudeUsageResponse.windows(from: data(fullResponse))
    #expect(windows.contains { $0.percent == 7 } == false)
}

@Test func parsesResetTimeWithFractionalSeconds() throws {
    let windows = try ClaudeUsageResponse.windows(from: data(fullResponse))
    #expect(windows[0].resetsAt == ClaudeTimestamp.date(from: "2026-08-30T14:00:00.277644+00:00"))
}

@Test func fallsBackToLegacyFieldsWhenLimitsIsEmpty() throws {
    let legacy = """
    {"five_hour":{"utilization":41.0,"resets_at":"2026-08-30T14:00:00.277644+00:00"},
     "seven_day":{"utilization":66.0,"resets_at":"2026-09-05T10:00:00.277667+00:00"},
     "limits":[]}
    """
    let windows = try ClaudeUsageResponse.windows(from: data(legacy))
    #expect(windows.count == 2)
    #expect(windows[0].percent == 41)
    #expect(windows[1].percent == 66)
}

@Test func toleratesUnknownKindWithoutLosingKnownOnes() throws {
    let mixed = """
    {"limits":[
      {"kind":"session","percent":9,"resets_at":"2026-08-30T14:00:00.277644+00:00","scope":null},
      {"kind":"nimbus_quill","percent":3,"resets_at":null,"scope":null}]}
    """
    let windows = try ClaudeUsageResponse.windows(from: data(mixed))
    #expect(windows.count == 1)
    #expect(windows[0].id == "session")
}

@Test func failsOnGarbage() {
    #expect(throws: ProviderFailure.self) {
        try ClaudeUsageResponse.windows(from: data("not json"))
    }
}

@Test func failsWhenNeitherLimitsNorLegacyPresent() {
    #expect(throws: ProviderFailure.self) {
        try ClaudeUsageResponse.windows(from: data(#"{"limits":[]}"#))
    }
}

// ===== resilience to changes on the service side =====

@Test func oneBrokenEntryDoesNotDiscardTheRest() throws {
    // The service has grown a window whose percent arrives as a string. The
    // other entries must still parse: one unfamiliar record is no reason to
    // lose the whole answer.
    let mixed = """
    {"limits":[
      {"kind":"session","percent":11,"resets_at":"2026-08-30T14:00:00.277644+00:00","scope":null},
      {"kind":"weekly_all","percent":"broken","resets_at":null,"scope":null}]}
    """
    let windows = try ClaudeUsageResponse.windows(from: data(mixed))
    #expect(windows.count == 1)
    #expect(windows[0].percent == 11)
}

@Test func changedScopeShapeStillHidesTheScopedWindow() throws {
    // `scope` used to be an object. Should it become a string, the entry must
    // still stay out of the list rather than arriving half-parsed.
    let changed = """
    {"limits":[
      {"kind":"session","percent":4,"resets_at":null,"scope":null},
      {"kind":"weekly_all","percent":9,"resets_at":null,"scope":"per-model"}]}
    """
    let windows = try ClaudeUsageResponse.windows(from: data(changed))
    #expect(windows.map(\.id) == ["session"])
}

@Test func brokenLimitsFallBackToLegacyFields() throws {
    // The whole limits array is spoilt but the older fields are intact — show
    // those rather than "unexpected response".
    let body = """
    {"five_hour":{"utilization":33.0,"resets_at":null},
     "seven_day":{"utilization":44.0,"resets_at":null},
     "limits":[{"kind":123}]}
    """
    let windows = try ClaudeUsageResponse.windows(from: data(body))
    #expect(windows.map(\.percent) == [33, 44])
}
