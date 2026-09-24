import Testing
import Preferences

/// Narrowing "Notify about" silences the period it names, and nothing else.
///
/// `includes` answered `== "session"` and `== "weekly"` while those were the
/// only two identifiers there were. A third kind then fell outside both, so
/// anyone who had narrowed this setting was told nothing about a monthly
/// allowance — at any level, including a hundred percent, with nothing on
/// screen to say why. The default hides it, which is the worst place for a
/// defect like this to sit.
///
/// The trade is deliberate and runs the cheap way: somebody who chose
/// `Five-hour` to hear less now hears about a monthly limit too. An unwanted
/// notification is one they can turn off. A limit nobody told them about is the
/// thing this app is for.
@Suite struct ANarrowedSettingStillWarns {

    @Test func bothMeansEverything() {
        for id in ["session", "weekly", "premium", "something-later"] {
            #expect(WindowScope.both.includes(windowID: id))
        }
    }

    @Test func eachScopeSilencesOnlyTheOtherNamedPeriod() {
        #expect(WindowScope.session.includes(windowID: "session"))
        #expect(!WindowScope.session.includes(windowID: "weekly"))

        #expect(WindowScope.weekly.includes(windowID: "weekly"))
        #expect(!WindowScope.weekly.includes(windowID: "session"))
    }

    /// The claim this suite exists for.
    @Test(arguments: WindowScope.allCases)
    func noScopeCanSwallowAWindowKindItDoesNotName(scope: WindowScope) {
        #expect(scope.includes(windowID: "premium"), """
            "\(scope.rawValue)" drops a monthly allowance, so a threshold \
            crossing on it is never announced and nothing says so
            """)
    }
}
