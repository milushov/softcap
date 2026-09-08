import Testing
@testable import StatusUI

/// A legend has room for a dozen characters, and two accounts on the same mail
/// host differ in the part that a truncation eats first.
@Suite struct ShorteningLegendNames {

    @Test func aSharedDomainIsDropped() {
        let short = LegendNames.shorten([
            "alex.p@example.com", "sam.k@example.com", "sam.kim@example.com",
        ])
        #expect(short == ["alex.p", "sam.k", "sam.kim"])
    }

    /// With two hosts the domain is what tells the accounts apart, and dropping
    /// it would repeat the mistake it exists to fix.
    @Test func differingDomainsAreKept() {
        let names = ["sam@example.com", "sam@example.org"]
        #expect(LegendNames.shorten(names) == names)
    }

    /// Codex names its account after the person, not an address. Such a name
    /// must not block the addresses from being shortened — a real account list
    /// mixes the two, three mail addresses beside one person.
    @Test func aNameWithoutADomainDoesNotBlockTheOthers() {
        let short = LegendNames.shorten([
            "Tyler Durden", "sam.k@example.com", "sam.kim@example.com",
        ])
        #expect(short == ["Tyler Durden", "sam.k", "sam.kim"])
    }

    @Test func namesWithNoDomainAtAllAreUntouched() {
        let names = ["Tyler Durden", "Someone Else"]
        #expect(LegendNames.shorten(names) == names)
    }

    @Test func aSingleAccountLosesItsDomainToo() {
        #expect(LegendNames.shorten(["only@example.com"]) == ["only"])
    }

    @Test func anEmptyListIsFine() {
        #expect(LegendNames.shorten([]).isEmpty)
    }

    /// The shortened list lines up with the input, because the chart pairs it
    /// with colours by position.
    @Test func orderAndCountAreKept() {
        let names = ["b@example.com", "a@example.com", "c@example.com"]
        let short = LegendNames.shorten(names)
        #expect(short.count == names.count)
        #expect(short == ["b", "a", "c"])
    }
}
