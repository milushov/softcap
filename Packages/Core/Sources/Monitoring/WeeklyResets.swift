import Foundation

/// Where the weekly limit reset in the past, worked out from where it resets next.
///
/// The usage history keeps percentages only, and a fall in a percentage is
/// ambiguous: it can be a reset, or it can be a stretch with no readings that
/// ends somewhere lower. Reading resets out of the curve would mark gaps as
/// resets. The service's own answer — the next reset — is exact, and the window
/// is a week long, so the earlier ones are that moment minus whole weeks.
public enum WeeklyResets {

    public static let period: TimeInterval = 7 * 86_400

    /// Every reset in `[start, end]`, oldest first, given one known reset.
    ///
    /// `known` may lie in the future (the usual case: the *next* reset) or in
    /// the past; the series runs in both directions from it. A reset that falls
    /// exactly on an edge is included.
    public static func resets(known: Date, from start: Date, to end: Date) -> [Date] {
        guard start <= end else { return [] }
        // First index k with known + k*period >= start. Rounded up on the
        // division, so a reset exactly on `start` is kept.
        let first = Int(((start.timeIntervalSince(known)) / period).rounded(.up))
        var out: [Date] = []
        var k = first
        while true {
            let moment = known.addingTimeInterval(Double(k) * period)
            if moment > end { break }
            if moment >= start { out.append(moment) }
            k += 1
        }
        return out
    }
}
