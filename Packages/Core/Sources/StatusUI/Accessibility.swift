import Foundation
import ProviderKit

/// Spoken descriptions for VoiceOver.
///
/// On screen an account is a grid of bars, tick marks and rings, and the colour
/// of the fill carries the urgency that the bare number understates. None of
/// that reaches a screen reader. Read element by element the row also falls
/// apart into fragments — "Claude", "Max 20x", "5h", "23%", "3h 39m" — which
/// arrive in the right order but say nothing about how they relate.
///
/// So each account collapses into a single element with one sentence, and
/// VoiceOver steps between accounts rather than through the pieces of one.
public extension Localization {

    /// One account, as a sentence:
    /// "Claude, name@example.com, Max 20x. Five-hour: 23% used, 3 hours 39
    /// minutes left. Weekly: 45% used, 5 days 2 hours left."
    func spokenSummary(for snapshot: AccountSnapshot, now: Date) -> String {
        var sentences = [identity(of: snapshot)]

        if let failure = snapshot.failure {
            sentences.append(failureText(failure.kind))
        } else {
            sentences.append(contentsOf: snapshot.windows.map { spoken($0, now: now) })
        }

        if snapshot.freshness.isStale, let captured = spokenCaptureDate(snapshot.freshness) {
            sentences.append(captured)
        }
        return sentences.joined(separator: ". ")
    }

    /// The remaining time in full words — "3 hours 39 minutes" — rather than the
    /// "3h 39m" the screen shows.
    ///
    /// Built by `DateComponentsFormatter` instead of the catalogue: spoken units
    /// need plural forms, and their categories differ per language (Russian has
    /// four, Arabic six). The system already knows every one of them, and a
    /// hand-written table for ten languages would be wrong somewhere.
    func spokenRemaining(_ interval: TimeInterval?) -> String? {
        guard let interval, interval > 0 else { return nil }
        let formatter = DateComponentsFormatter()
        var calendar = Calendar.current
        calendar.locale = activeLocale
        formatter.calendar = calendar
        formatter.unitsStyle = .full
        formatter.allowedUnits = [.day, .hour, .minute]
        formatter.maximumUnitCount = 2
        return formatter.string(from: interval)
    }

    /// The window's name in speech. The screen shows "5h" and "week"; spelled
    /// out those read as letters, so the settings wording is reused.
    func spokenWindowTitle(_ id: String) -> String {
        switch id {
        case "session": self("Five-hour")
        case "weekly":  self("Weekly")
        default:        id
        }
    }

    /// The menu bar item. Its label reads "0:47", which spoken back is "zero
    /// colon forty-seven" — a time of day, not a duration. And the icon's
    /// colour, the only sign of how bad things are, is silent.
    func spokenMenuBar(percent used: Double, remaining: TimeInterval?) -> String {
        let name = self("Busiest")
        // Spelled by the formatter rather than written into the sentence: the
        // sentence is a per-language template, and three of the ten catalogues
        // had the sign in the wrong place because each had to remember the rule
        // separately.
        let share = self.percent(used)
        let detail = if let left = spokenRemaining(remaining) {
            String(format: self("%1$@: %2$@ used, %3$@ left"), name, share, left)
        } else {
            String(format: self("%1$@: %2$@ used"), name, share)
        }
        return "\(self("Subscription limits")). \(detail)"
    }

    // MARK: - parts

    private func identity(of snapshot: AccountSnapshot) -> String {
        [snapshot.provider.title, snapshot.displayName, snapshot.planLabel]
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }

    private func spoken(_ window: LimitWindow, now: Date) -> String {
        let name = spokenWindowTitle(window.id)
        let share = percent(window.percent)
        guard let left = spokenRemaining(window.remaining(from: now)) else {
            return String(format: self("%1$@: %2$@ used"), name, share)
        }
        return String(format: self("%1$@: %2$@ used, %3$@ left"), name, share, left)
    }

    private func spokenCaptureDate(_ freshness: Freshness) -> String? {
        let captured = freshness.capturedAt
        guard captured > .distantPast else { return self("No data available") }
        let formatter = DateFormatter()
        formatter.locale = activeLocale
        // A spelled-out date, not the "28 Aug" the badge shows: an abbreviated
        // month is read as letters.
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        return String(format: self("Data from %@"), formatter.string(from: captured))
    }
}
