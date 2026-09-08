import Foundation

/// Looking for a phrase in something a person wrote, as opposed to in code.
///
/// Three separate checks in this suite have been written with `contains` and
/// then refused a sentence that was only reworded: "once a minute" straddled a
/// line break when the copy was shortened, "all four sizes" began a section
/// after a rewrite, and "five minutes apart" took a capital F when a long
/// sentence was split in two. Each time the rule was "the document says this"
/// and the check was "the document says this, in these letters, on one line".
///
/// So prose is asked with `says` and code with `contains`, and which one a call
/// uses states which it is. Code keeps `contains` on purpose: `.package(` and
/// `layoutDirection, loc.layoutDirection` are not sentences, and a capital there
/// would be a different thing, not the same thing rephrased.
extension String {
    func says(_ phrase: String) -> Bool {
        range(of: phrase, options: [.caseInsensitive]) != nil
    }
}

/// A walk that comes back empty makes every check reading it pass without having
/// read anything — the same defect as a `swift test --filter` that matches no
/// suite, one layer further in. Each walk here says how little is too little.
struct ScanIsLookingInTheWrongPlace: Error, CustomStringConvertible {
    let what: String, found: Int, least: Int
    var description: String {
        "the \(what) scan found \(found), fewer than the \(least) expected — it is "
        + "looking in the wrong place, and the checks reading it would otherwise pass "
        + "without examining anything"
    }
}

/// Ask through a helper that takes only the phrase — never
/// `#expect(document.says(…))`.
///
/// The expectation macro prints the sub-expressions it can, and the receiver is
/// one of them: a landing-page check written that way failed with 29 000
/// characters of HTML ahead of the one sentence saying what to do about it. The
/// guard worked; its report was unreadable, which for a check that exists to
/// fire on somebody else's future edit is most of the way to not working.
///
/// So each suite here loads its document inside a `…Says(_:)` of its own. The
/// only sub-expression left is the phrase, and the failure reads
/// `(try Self.pageSays("No telemetry") → false)`.
enum HowToAskADocument {}
