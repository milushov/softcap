import Testing
import Foundation
@testable import Updates

@Suite struct ReleaseVersionOrdering {

    private func version(_ text: String) throws -> ReleaseVersion {
        try #require(ReleaseVersion(text), "\(text) did not parse")
    }

    /// The case the whole type exists for. Sorting these as text puts 0.1.10
    /// before 0.1.9, and the app would offer an update backwards on the tenth
    /// release after a ninth.
    @Test func tenComesAfterNine() throws {
        #expect(try version("0.1.9") < version("0.1.10"))
    }

    @Test func tagsAndBundlesSpellTheSameVersion() throws {
        #expect(try version("v0.1.42") == version("0.1.42"))
    }

    /// The bundle says 0.1 before a release has ever set the run number, and a
    /// tag would say 0.1.0. They are the same version and neither is an update
    /// to the other.
    @Test func atrailingZeroIsNotAdifferentVersion() throws {
        #expect(try version("0.1") == version("0.1.0"))
        #expect(try version("0.1.0.0") == version("0.1"))
        #expect(try !(version("0.1") < version("0.1.0")))
    }

    @Test func moreComponentsCanStillBeNewer() throws {
        #expect(try version("0.1") < version("0.1.1"))
        #expect(try version("1.0") > version("0.99.99"))
    }

    @Test func zeroIsAversion() throws {
        #expect(try version("0") == version("0.0.0"))
    }

    @Test func whatIsNotAversionIsRefused() {
        #expect(ReleaseVersion("") == nil)
        #expect(ReleaseVersion("v") == nil)
        #expect(ReleaseVersion("0.1.x") == nil)
        #expect(ReleaseVersion("0.1-beta") == nil)
        #expect(ReleaseVersion("-1.0") == nil)
        #expect(ReleaseVersion("0..1") == nil)
    }

    /// The `v` is a tag's habit, not part of the number, and the interface
    /// shows the number.
    @Test func itReadsBackWithoutTheTagPrefix() throws {
        #expect(try version("v0.1.42").description == "0.1.42")
        #expect(try version("0.1.42").description == "0.1.42")
    }

    /// Equal versions hash equally, or a `Set` of them holds both spellings.
    @Test func twoSpellingsOfOneVersionAreOneElement() throws {
        let set: Set<ReleaseVersion> = try [version("0.1"), version("0.1.0"), version("v0.1")]
        #expect(set.count == 1)
    }
}
