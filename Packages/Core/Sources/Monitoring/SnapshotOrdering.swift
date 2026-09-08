import Foundation
import ProviderKit
import Preferences

/// Row order in the window. Failed accounts always sink to the bottom whatever
/// the choice: there is nothing to say about them, and keeping them at the top
/// would spend the best position on an empty row.
public func orderedForDisplay(
    _ snapshots: [AccountSnapshot], ordering: Ordering = .leastLoadedFirst
) -> [AccountSnapshot] {
    snapshots.sorted { lhs, rhs in
        let lhsFailed = lhs.failure != nil
        let rhsFailed = rhs.failure != nil
        if lhsFailed != rhsFailed { return !lhsFailed }

        switch ordering {
        case .leastLoadedFirst:
            if lhs.peakPercent != rhs.peakPercent { return lhs.peakPercent < rhs.peakPercent }
        case .byName:
            break
        }
        return lhs.displayName.localizedCompare(rhs.displayName) == .orderedAscending
    }
}
