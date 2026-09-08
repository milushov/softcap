import Foundation

/// A remaining interval broken into units.
///
/// The model does not assemble a string itself: unit order, abbreviations and
/// plural forms depend on the language — Russian writes "5 д 23 ч", Arabic reads
/// its units right to left, and the forms for 1, 2 and 5 differ. Composing the
/// label is the app layer's job.
public struct RemainingTime: Sendable, Hashable {
    public let days: Int
    public let hours: Int
    public let minutes: Int

    /// `nil` when the deadline has passed — showing "minus three minutes" is
    /// meaningless.
    public init?(_ interval: TimeInterval) {
        guard interval >= 0 else { return nil }
        let total = Int(interval)
        days = total / 86_400
        hours = (total % 86_400) / 3_600
        minutes = (total % 3_600) / 60
    }

    /// Which units to show: more than two is noise, and anything smaller than
    /// the leading unit stops mattering. With days left, minutes are irrelevant.
    public var significantUnits: (major: Unit, minor: Unit?) {
        if days > 0 { return (.days(days), .hours(hours)) }
        if hours > 0 { return (.hours(hours), .minutes(minutes)) }
        return (.minutes(minutes), nil)
    }

    public enum Unit: Sendable, Hashable {
        case days(Int), hours(Int), minutes(Int)

        public var value: Int {
            switch self {
            case .days(let v), .hours(let v), .minutes(let v): v
            }
        }
    }
}
