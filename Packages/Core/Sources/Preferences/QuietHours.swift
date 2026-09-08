import Foundation

/// A span of the day, expressed in minutes from midnight.
///
/// Stored as minutes rather than dates: the setting is tied to a time of day,
/// not a particular day, and it survives a change of time zone.
public struct QuietHours: Codable, Sendable, Hashable {
    public let startMinute: Int
    public let endMinute: Int

    public init(startMinute: Int, endMinute: Int) {
        self.startMinute = max(0, min(startMinute, 24 * 60 - 1))
        self.endMinute = max(0, min(endMinute, 24 * 60 - 1))
    }

    public func contains(_ date: Date, calendar: Calendar = .current) -> Bool {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        let minute = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)

        // A start later than the end means the span crosses midnight, and
        // "inside" then means "after the start OR before the end".
        if startMinute < endMinute {
            return minute >= startMinute && minute < endMinute
        }
        if startMinute > endMinute {
            return minute >= startMinute || minute < endMinute
        }
        return true   // start equals end — quiet around the clock
    }
}
