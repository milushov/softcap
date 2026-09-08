import Foundation

/// A released version, as a number rather than as text.
///
/// Releases are tagged `v0.1.42` and the bundle carries `0.1.42`; both spellings
/// are the same version. Comparison is component by component and numeric,
/// because the text form sorts `0.1.10` before `0.1.9` and the app would offer
/// an update backwards on the tenth release after a ninth.
///
/// Trailing zeros are dropped on the way in, so `0.1` and `0.1.0` are one
/// version and not two — the bundle says the first before a release has set a
/// run number, and a tag would say the second.
public struct ReleaseVersion: Sendable, Hashable, Comparable, CustomStringConvertible {

    /// Significant components, most significant first, with trailing zeros
    /// removed. Never empty.
    private let components: [Int]

    /// The text it was made from, without a tag's `v`.
    public let description: String

    public init?(_ text: String) {
        let body = text.hasPrefix("v") ? String(text.dropFirst()) : text
        guard !body.isEmpty else { return nil }

        var numbers: [Int] = []
        for part in body.split(separator: ".", omittingEmptySubsequences: false) {
            // `Int("-1")` parses, and a negative component is not a version.
            // `Int("")` does not, which is what refuses `0..1`.
            guard let number = Int(part), number >= 0 else { return nil }
            numbers.append(number)
        }

        while numbers.count > 1, numbers.last == 0 { numbers.removeLast() }
        components = numbers
        description = body
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        let width = max(lhs.components.count, rhs.components.count)
        for index in 0..<width {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right { return left < right }
        }
        return false
    }

    // Written out rather than synthesised. The synthesised pair would take
    // `description` into account as well, and `0.1` would then compare equal to
    // `0.1.0` while hashing differently — a Set holding both, which is the shape
    // of bug that passes every test but the one that looks for it.
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.components == rhs.components
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(components)
    }
}
