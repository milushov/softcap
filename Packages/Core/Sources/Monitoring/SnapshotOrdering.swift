import Foundation
import ProviderKit
import Preferences

/// Automatic ordering puts failed accounts last. Custom ordering keeps the
/// chosen positions even when readings fail or usage changes; new accounts
/// follow the saved ones, sorted by name until they are arranged.
public func orderedForDisplay(
    _ snapshots: [AccountSnapshot], ordering: Ordering = .leastLoadedFirst,
    customAccountOrder: [String] = []
) -> [AccountSnapshot] {
    let positions = Dictionary(
        customAccountOrder.enumerated().map { ($0.element, $0.offset) },
        uniquingKeysWith: { first, _ in first }
    )
    return snapshots.sorted { lhs, rhs in
        if ordering == .custom {
            let left = positions[lhs.id] ?? Int.max
            let right = positions[rhs.id] ?? Int.max
            if left != right { return left < right }
        } else {
            let lhsFailed = lhs.failure != nil
            let rhsFailed = rhs.failure != nil
            if lhsFailed != rhsFailed { return !lhsFailed }
        }

        switch ordering {
        case .leastLoadedFirst:
            if lhs.peakPercent != rhs.peakPercent { return lhs.peakPercent < rhs.peakPercent }
        case .byName, .custom:
            break
        }
        let names = lhs.displayName.localizedCompare(rhs.displayName)
        if names != .orderedSame { return names == .orderedAscending }
        return lhs.id < rhs.id
    }
}
