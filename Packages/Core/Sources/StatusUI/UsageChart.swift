import SwiftUI
import Charts
import ProviderKit
import Monitoring

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

private extension Color {
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

/// Usage over time: one line per account, on one plot.
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

    @ObservedObject private var loc: Localization

    public init(
        segments: [UsageSegment],
        accountIDs: [String],
        names: [String: String],
        range: UsageRange,
        now: Date,
        localization: Localization
    ) {
        self.segments = segments
        self.accountIDs = accountIDs
        self.names = names
        self.range = range
        self.now = now
        self.loc = localization
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            chart
            legend
        }
    }

    private var chart: some View {
        Chart {
            ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                ForEach(segment.points, id: \.at) { point in
                    LineMark(
                        x: .value(loc("Time"), point.at),
                        y: .value(loc("Used"), point.percent)
                    )
                    // Each run is its own series, so a break in recording is a
                    // break in the line rather than a straight guess across it.
                    .foregroundStyle(by: .value(loc("Account"), segment.accountID))
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
                    .foregroundStyle(by: .value(loc("Account"), segment.accountID))
                    .symbolSize(28)
                }
            }
        }
        .chartForegroundStyleScale(domain: accountIDs, range: colours)
        .chartYScale(domain: 0...100)
        .chartYAxis {
            AxisMarks(position: .leading, values: [0, 25, 50, 75, 100]) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let percent = value.as(Int.self) {
                        Text(loc.percent(Double(percent))).font(.system(size: 9.5))
                    }
                }
            }
        }
        .chartXScale(domain: now.addingTimeInterval(-range.duration)...now)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: range == .week ? 7 : 5)) { value in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                    .font(.system(size: 9.5))
            }
        }
        // The built-in legend would print the internal identifier; the legend
        // below names the account instead.
        .chartLegend(.hidden)
        // Time runs left to right even in a right-to-left interface: an axis is
        // not text, and mirroring it would make a rising line read as falling.
        .environment(\.layoutDirection, .leftToRight)
    }

    private var legend: some View {
        HStack(spacing: 14) {
            ForEach(accountIDs, id: \.self) { id in
                HStack(spacing: 5) {
                    Circle()
                        .fill(AccountPalette.colour(for: id, among: accountIDs))
                        .frame(width: 7, height: 7)
                    Text(legendName(for: id))
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func legendName(for id: String) -> String {
        let full = accountIDs.map { LegendNames.label(for: $0, in: names) }
        let short = LegendNames.shorten(full)
        guard let index = accountIDs.firstIndex(of: id)
        else { return LegendNames.label(for: id, in: names) }
        return short[index]
    }

    private var colours: [Color] {
        accountIDs.map { AccountPalette.colour(for: $0, among: accountIDs) }
    }
}
