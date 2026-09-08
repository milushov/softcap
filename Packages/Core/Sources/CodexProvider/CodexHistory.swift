import Foundation
import ProviderKit

/// Recovers the readings Codex wrote before this app was watching.
///
/// Codex records a rate-limit event into its session file every time it works,
/// and those files go back weeks. Claude has nothing of the sort — its API
/// answers with the present moment only — so the two lines on the chart start
/// out very differently: Codex arrives with its past, Claude begins today.
///
/// Producing samples rather than snapshots keeps this out of the poller: this is
/// history, not a reading, and it is imported once rather than watched.
public enum CodexHistoryImporter {

    /// Every reading in the session files, as samples for one account.
    ///
    /// Duplicates across files are left in: `UsageHistory.merge` drops them by
    /// timestamp, and deciding that twice would be two places to get it wrong.
    public static func samples(
        fromFiles files: [[String]], accountID: String
    ) -> [UsageSample] {
        files.flatMap { lines in
            RolloutParser.allEvents(inLines: lines).flatMap { event in
                event.windows.map { window in
                    UsageSample(
                        at: event.capturedAt, accountID: accountID,
                        windowID: window.id, percent: window.percent
                    )
                }
            }
        }
        // A file with an unparsable timestamp yields the epoch, which would
        // stretch the chart's axis back to 1970.
        .filter { $0.at.timeIntervalSince1970 > 1 }
        .sorted { $0.at < $1.at }
    }
}
