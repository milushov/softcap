import Foundation

/// The day an account's subscription is paid.
///
/// No provider exposes a billing date through the usage endpoints, so the
/// person enters it. It is a day of the month, optionally pinned to one month
/// for a yearly plan.
public struct BillingSchedule: Codable, Sendable, Hashable {

    public enum Period: Codable, Sendable, Hashable {
        case monthly
        /// Paid once a year, in this month (1–12).
        case yearly(month: Int)
    }

    /// 1–31. A day the month does not have falls on the month's last day.
    public var dayOfMonth: Int
    public var period: Period

    public init(dayOfMonth: Int, period: Period = .monthly) {
        self.dayOfMonth = min(max(dayOfMonth, 1), 31)
        if case .yearly(let month) = period {
            self.period = .yearly(month: min(max(month, 1), 12))
        } else {
            self.period = period
        }
    }

    /// The payment days that fall in `[start, end]`, oldest first, each at the
    /// start of its day in `calendar`.
    public func payments(
        from start: Date, to end: Date, calendar: Calendar = .current
    ) -> [Date] {
        guard start <= end else { return [] }
        let first = calendar.dateComponents([.year, .month], from: start)
        let last = calendar.dateComponents([.year, .month], from: end)
        guard var year = first.year, var month = first.month,
              let lastYear = last.year, let lastMonth = last.month
        else { return [] }

        var out: [Date] = []
        while (year, month) <= (lastYear, lastMonth) {
            if case .yearly(let paidIn) = period, paidIn != month {
                // not this month
            } else if let day = date(year: year, month: month, calendar: calendar),
                      day >= start, day <= end {
                out.append(day)
            }
            month += 1
            if month > 12 { month = 1; year += 1 }
        }
        return out
    }

    private func date(year: Int, month: Int, calendar: Calendar) -> Date? {
        var parts = DateComponents(year: year, month: month, day: 1)
        guard let first = calendar.date(from: parts),
              let length = calendar.range(of: .day, in: .month, for: first)?.count
        else { return nil }
        parts.day = min(dayOfMonth, length)
        return calendar.date(from: parts)
    }
}
