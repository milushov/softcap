import SwiftUI
import Charts
import ProviderKit
import Monitoring
import Preferences

/// Colours that stand for *which account*, kept apart from the colours that
/// stand for *how loaded* one is.
///
/// The limits window already speaks in colour: green through red is the load
/// scale. Reusing those hues to tell accounts apart would put two meanings on
/// one channel, and a blue line at 90 % would look calmer than a red one at 20.
/// So identity is cool and load is warm, and neither borrows from the other.
public enum AccountPalette {

    /// Written as hex because the landing page draws the same chart and writes
    /// them that way. They were decimal triples here and hex there, identical to
    /// the byte and connected by nothing; a test compares these two lists now,
    /// so one spelling has to serve both.
    public static let hexes = [
        "#5c8cd9",   // blue
        "#8c73cc",   // violet
        "#4da1ae",   // teal
        "#b873a6",   // mauve
        "#6b7ab8",   // indigo
    ]

    public static let colours: [Color] = hexes.map(Color.init(hex:))

    /// A colour per account, fixed by position in a stable list rather than by
    /// drawing order: a line that changed colour between redraws would be worse
    /// than no colour at all.
    public static func colour(for accountID: String, among ids: [String]) -> Color {
        guard let index = ids.firstIndex(of: accountID) else { return .secondary }
        return colours[index % colours.count]
    }
}

extension Color {
    /// `#rrggbb` only — the one form the palette is written in.
    init(hex: String) {
        let digits = hex.dropFirst()
        let value = UInt32(digits, radix: 16) ?? 0
        self.init(
            red:   Double((value >> 16) & 0xff) / 255,
            green: Double((value >> 8) & 0xff) / 255,
            blue:  Double(value & 0xff) / 255
        )
    }
}

/// Shortens names for the legend by dropping a domain they all share.
///
/// Three accounts on one mail host read as `sam.k@example.com` and
/// `sam.kim@example.com`, and in a legend's width both truncate to
/// `sam.k…example.com` — the part that tells them apart is exactly the part
/// that gets cut. Dropping the shared suffix leaves what differs.
///
/// Only a domain shared by every address is dropped: with two hosts in the list
/// the domain is what distinguishes them, and removing it would repeat the
/// mistake. Names that are not addresses at all — Codex calls its account after
/// the person — are neither shortened nor counted against the others.
public enum LegendNames {

    /// What to call an account whose name is not known.
    ///
    /// The legend used to fall back to the account's own identifier, which is
    /// `claude/` and a UUID — an internal string, on screen, in the one view
    /// built for looking at over time. It happens whenever an account is in the
    /// history but not among the accounts that answered: hidden, forgotten, or
    /// simply not polled yet this launch.
    ///
    /// The service is the honest remainder. We know which one it was; we do not
    /// know whose account it was. Brand names are not translated, so this needs
    /// no catalogue.
    public static func label(for id: String, in names: [String: String]) -> String {
        if let known = names[id] { return known }
        guard let slash = id.firstIndex(of: "/") else { return id }
        let provider = String(id[id.startIndex..<slash])
        return ProviderID(rawValue: provider)?.title ?? id
    }

    public static func shorten(_ names: [String]) -> [String] {
        let domains = names.compactMap { name -> String? in
            guard let at = name.lastIndex(of: "@") else { return nil }
            return String(name[name.index(after: at)...])
        }
        guard let shared = domains.first, domains.allSatisfy({ $0 == shared })
        else { return names }
        return names.map { name in
            guard let at = name.lastIndex(of: "@") else { return name }
            return String(name[name.startIndex..<at])
        }
    }
}

/// How far back the chart looks.
public enum UsageRange: String, CaseIterable, Identifiable, Sendable {
    case week, month

    public var id: String { rawValue }
    public var duration: TimeInterval { self == .week ? 7 * 86_400 : 30 * 86_400 }
    public var titleKey: String { self == .week ? "Week" : "Month" }
}

/// Colours for the two kinds of event drawn over a strip.
///
/// Each is its own hue, outside `AccountPalette` (cool, identity) and outside
/// the green-to-red load scale: a reset line in a blue of the palette would read
/// as one more account, and a payment dot in red as a limit being hit.
public enum ChartMarkers {
    /// A weekly reset: a neutral grey, because it is a fact about the clock and
    /// the same for every account.
    public static let resetHex = "#9a9fa8"
    /// A subscription payment: warm orange.
    public static let paymentHex = "#e8844a"

    public static let reset = Color(hex: resetHex)
    public static let payment = Color(hex: paymentHex)
}

/// Usage over time: one strip per account, stacked, on one shared time axis.
///
/// One plot with every account's line on it overlapped as soon as two accounts
/// climbed together, and told the reader which line was whose only through a
/// legend to be matched by colour. Here each account has a strip of its own,
/// labelled on the left, with its current figure and next reset on the right.
///
/// The weekly window is drawn, not the five-hour one. Over seven days the short
/// window resets thirty-three times and over a month a hundred and forty-four —
/// a comb rather than a chart. The weekly window resets once a week, so each
/// tooth is one week's allowance: its height is how much was spent and a flat
/// top is an account that ran out.
public struct UsageChart: View {
    private let segments: [UsageSegment]
    private let accountIDs: [String]
    private let names: [String: String]
    private let range: UsageRange
    private let now: Date
    private let nextResets: [String: Date]
    private let currentPercents: [String: Double]
    private let billing: [String: BillingSchedule]

    @ObservedObject private var loc: Localization

    static let nameWidth: CGFloat = 104
    static let figureWidth: CGFloat = 84
    static let stripHeight: CGFloat = 46
    static let stripSpacing: CGFloat = 10
    static let columnSpacing: CGFloat = 10

    /// - Parameters:
    ///   - nextResets: each account's next weekly reset. An account missing
    ///     here gets no reset marks and no countdown.
    ///   - currentPercents: the live weekly figure; an account missing here
    ///     shows its last recorded reading.
    ///   - billing: payment schedules by account.
    public init(
        segments: [UsageSegment],
        accountIDs: [String],
        names: [String: String],
        range: UsageRange,
        now: Date,
        nextResets: [String: Date] = [:],
        currentPercents: [String: Double] = [:],
        billing: [String: BillingSchedule] = [:],
        localization: Localization
    ) {
        self.segments = segments
        self.accountIDs = accountIDs
        self.names = names
        self.range = range
        self.now = now
        self.nextResets = nextResets
        self.currentPercents = currentPercents
        self.billing = billing
        self.loc = localization
    }

    private var domain: ClosedRange<Date> { now.addingTimeInterval(-range.duration)...now }

    private var dayStride: Int { range == .week ? 1 : 5 }

    public var body: some View {
        VStack(alignment: .leading, spacing: Self.stripSpacing) {
            ForEach(accountIDs, id: \.self) { id in
                row(for: id)
            }
            axis
        }
    }

    // MARK: Rows

    private func row(for id: String) -> some View {
        HStack(spacing: Self.columnSpacing) {
            Text(displayName(for: id))
                .font(.system(size: 11.5, weight: .medium))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: Self.nameWidth, alignment: .leading)

            strip(for: id)
                .frame(height: Self.stripHeight)

            VStack(alignment: .trailing, spacing: 2) {
                Text(figure(for: id))
                    .font(.system(size: 15, weight: .semibold))
                    .monospacedDigit()
                if let text = resetText(for: id) {
                    Text(text)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .frame(width: Self.figureWidth, alignment: .trailing)
        }
    }

    private func strip(for id: String) -> some View {
        let colour = AccountPalette.colour(for: id, among: accountIDs)
        let mine = segments.enumerated().filter { $0.element.accountID == id }
        let resets = nextResets[id].map {
            WeeklyResets.resets(known: $0, from: domain.lowerBound, to: now)
        } ?? []
        let payments = billing[id]?.payments(from: domain.lowerBound, to: now) ?? []

        return Chart {
            ForEach(mine, id: \.offset) { offset, segment in
                // Each run is its own series, so a break in recording is a
                // break in the area and the line rather than a straight guess
                // across it. The fill first, so the line is drawn over it.
                ForEach(segment.points, id: \.at) { point in
                    AreaMark(
                        x: .value(loc("Time"), point.at),
                        yStart: .value(loc("Used"), 0),
                        yEnd: .value(loc("Used"), point.percent),
                        series: .value(loc("Account"), "area-\(offset)")
                    )
                    .foregroundStyle(colour.opacity(0.18))
                    .interpolationMethod(.monotone)
                }

                ForEach(segment.points, id: \.at) { point in
                    LineMark(
                        x: .value(loc("Time"), point.at),
                        y: .value(loc("Used"), point.percent),
                        series: .value(loc("Account"), "line-\(offset)")
                    )
                    .foregroundStyle(colour)
                    .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.monotone)
                }

                // A run of one reading draws a line of zero length, which is
                // nothing at all on screen. An account that has just been added
                // has exactly that, and an invisible line reads as a missing
                // account rather than a new one.
                if segment.points.count == 1, let only = segment.points.first {
                    PointMark(
                        x: .value(loc("Time"), only.at),
                        y: .value(loc("Used"), only.percent)
                    )
                    .foregroundStyle(colour)
                    .symbolSize(28)
                }
            }

            ForEach(resets, id: \.self) { moment in
                RuleMark(x: .value(loc("Time"), moment))
                    .foregroundStyle(ChartMarkers.reset)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .accessibilityLabel(loc("Weekly limit reset"))

                // The glyph is a point with a drawn symbol rather than an
                // annotation: an annotation on a rule is placed against the
                // rule's full height and landed outside the clipped strip.
                PointMark(
                    x: .value(loc("Time"), moment),
                    y: .value(loc("Used"), 86)
                )
                .symbol {
                    Text("\u{21BA}")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(ChartMarkers.reset)
                }
                .accessibilityLabel(loc("Weekly limit reset"))
            }

            ForEach(payments, id: \.self) { moment in
                PointMark(
                    x: .value(loc("Time"), moment),
                    y: .value(loc("Used"), 7)
                )
                .foregroundStyle(ChartMarkers.payment)
                .symbol(.circle)
                .symbolSize(30)
                .accessibilityLabel(loc("Subscription payment"))
            }
        }
        .chartYScale(domain: 0...100)
        .chartYAxis(.hidden)
        .chartXScale(domain: domain)
        .chartXAxis {
            // Gridlines only: the labels are drawn once, under the last strip.
            AxisMarks(values: .stride(by: .day, count: dayStride)) { _ in
                AxisGridLine().foregroundStyle(.secondary.opacity(0.18))
            }
        }
        .chartLegend(.hidden)
        .chartPlotStyle { plot in
            plot
                .background(Color.secondary.opacity(0.07))
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .help(helpText(resets: resets.count, payments: payments))
        .accessibilityElement(children: .contain)
        // Time runs left to right even in a right-to-left interface: an axis is
        // not text, and mirroring it would make a rising line read as falling.
        .environment(\.layoutDirection, .leftToRight)
    }

    /// The shared axis. An empty chart with the same width and the same scale
    /// as the strips above it, set between spacers the width of the name and
    /// figure columns, so its days line up with their gridlines.
    private var axis: some View {
        HStack(spacing: Self.columnSpacing) {
            Color.clear.frame(width: Self.nameWidth, height: 1)
            Chart {}
                .chartXScale(domain: domain)
                .chartYAxis(.hidden)
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: dayStride)) { _ in
                        AxisValueLabel(format: loc.chartDay)
                            .font(.system(size: 9.5))
                    }
                }
                .frame(height: 18)
                .environment(\.layoutDirection, .leftToRight)
            Color.clear.frame(width: Self.figureWidth, height: 1)
        }
    }

    // MARK: Text

    private func displayName(for id: String) -> String {
        let full = accountIDs.map { LegendNames.label(for: $0, in: names) }
        let short = LegendNames.shorten(full)
        guard let index = accountIDs.firstIndex(of: id)
        else { return LegendNames.label(for: id, in: names) }
        return short[index]
    }

    private func figure(for id: String) -> String {
        if let live = currentPercents[id] { return loc.percent(live) }
        let last = segments.last(where: { $0.accountID == id })?.points.last
        return last.map { loc.percent($0.percent) } ?? "\u{2014}"
    }

    /// "Resets today" / "Resets in 3d", from the account's next weekly reset;
    /// nothing when it is unknown or already past.
    private func resetText(for id: String) -> String? {
        guard let next = nextResets[id], next > now else { return nil }
        let calendar = Calendar.current
        let days = calendar.dateComponents(
            [.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: next)
        ).day ?? 0
        if days <= 0 { return loc("Resets today") }
        return String(format: loc("Resets in %@"), String(format: loc("%lldd"), days))
    }

    private func helpText(resets: Int, payments: [Date]) -> String {
        var lines: [String] = []
        if resets > 0 { lines.append("\u{21BA} " + loc("Weekly limit reset")) }
        for moment in payments {
            lines.append("\u{25CF} " + loc("Subscription payment") + ": "
                         + moment.formatted(loc.chartDay))
        }
        return lines.joined(separator: "\n")
    }
}
