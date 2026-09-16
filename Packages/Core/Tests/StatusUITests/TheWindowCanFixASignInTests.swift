import Testing
import Foundation
import ProviderKit
@testable import StatusUI

/// A dead token used to be reported in one place and repaired in another.
///
/// The limits window said `Sign-in required` and stopped there; the button that
/// does something about it was on the Accounts screen, which is a different
/// window away from the row raising the complaint. So the window named a
/// problem it could not fix, every five minutes, for as long as the account
/// stayed broken.
///
/// The row carries the offer itself now. What is held here is the shape of that
/// offer rather than the pixels: which failure earns a button, which surfaces
/// may draw one, which row the spinner belongs to, and where the answer goes
/// when the browser comes back.
///
/// Read out of the source for the reason `AnOfferOnScreenCanBeAskedAgain` gives:
/// these are views, the package tests are the only tests this project has, and a
/// scan cannot prove a screen behaves — it can prove the claim is still written.
/// Each expectation is phrased against a slice of one declaration, never a whole
/// file, so a mutant that deletes the behaviour cannot stay green on the
/// strength of a comment somewhere else in it. And each is asked through a
/// helper taking only the phrase, for the reason `HowToAskADocument` gives:
/// otherwise a failure prints the slice it searched and the sentence explaining
/// what to do arrives under a screenful of Swift.
@Suite struct TheWindowCanFixASignIn {

    // MARK: - which failure earns a button

    /// The network being unreachable and a response nobody can parse are
    /// sentences and nothing more. A button on either would offer a sign-in
    /// against a problem a sign-in does not touch, and the person would come
    /// back from the browser to the same row, having spent a grant to learn
    /// nothing.
    @Test func onlyADeadTokenIsOfferedAWayOut() throws {
        #expect(try Self.fullRow(names: "failure.kind == .needsLogin"), """
            the full row no longer asks which failure it is looking at — every \
            failure then offers a sign-in, including the ones a sign-in cannot \
            repair
            """)
        #expect(try Self.fullRow(names: "SignInPrompt("), """
            the full row no longer draws the offer
            """)
        #expect(try Self.minimalRow(names: "failure.kind == .needsLogin"), """
            the minimal row no longer asks which failure it is looking at
            """)
        #expect(try Self.minimalRow(names: "SignInPrompt("), """
            the minimal row no longer draws the offer
            """)
    }

    /// The offer is a parameter, and the row is drawn by four surfaces. Three of
    /// them are pictures — two widgets and a phone screen reading a snapshot the
    /// Mac wrote — and a button in a picture is a picture of a button.
    @Test func noSurfaceWithoutABrowserDrawsAButton() throws {
        for path in Self.surfacesWithoutABrowser {
            #expect(try !Self.surface(path, mentions: "signIn:"), """
                \(path) passes a sign-in offer — that surface has no browser to \
                send anybody to, and the button would do nothing when pressed
                """)
        }
    }

    // MARK: - the window that does have a browser

    /// Both shapes of it, not one. The minimal window is a setting away, and a
    /// repair that exists in one shape of the same window is a repair half the
    /// people who need it never meet.
    @Test func bothShapesOfTheWindowOfferIt() throws {
        #expect(try Self.window("full", names: "signIn: signIn(for: snapshot)"), """
            the full window draws rows without the offer
            """)
        #expect(try Self.window("minimal", names: "signIn: signIn(for: snapshot)"), """
            the minimal window draws rows without the offer — the setting that \
            takes the headings off the window would take the repair off it too
            """)
    }

    /// `LoginController.providers` is the list of services whose OAuth this app
    /// implements, and `start` refuses anything outside it in silence. A button
    /// the controller will refuse does nothing when pressed, which is worse than
    /// no button: the first says the app is broken, the second says the account
    /// is.
    @Test func nothingIsOfferedThatTheControllerWouldRefuse() throws {
        #expect(try Self.offer(names: "LoginController.providers.contains(snapshot.provider)"), """
            the window offers a sign-in without asking whether this app can sign \
            in to that service at all
            """)
        #expect(try Self.offer(names: "snapshot.failure?.kind == .needsLogin"), """
            the window builds an offer for failures that are not a dead token
            """)
    }

    /// Two accounts of one service can be dead at once — that is how the window
    /// that prompted all this looked, three accounts reading and one asking to
    /// sign in. The controller runs one attempt at a time, so exactly one row
    /// may show one running.
    @Test func theSpinnerBelongsToTheRowThatAskedForIt() throws {
        #expect(try Self.offer(names: "login.request?.account == snapshot.id"), """
            the window no longer checks which row asked — every account of that \
            service then shows the sign-in as running, claiming as many attempts \
            as there are rows against a controller that allows one
            """)
        #expect(try Self.offer(names: "from: .window"), """
            the window starts sign-ins without saying where they came from, so \
            success cannot be told where to go back to
            """)
    }

    /// A sign-in normally returns through a loopback listener and this is never
    /// seen. When the port cannot be taken the provider shows the code on its
    /// own page instead, and it has to be pasted somewhere — somewhere that is
    /// not the settings screen, or the sign-in starts in the window and can be
    /// finished only on the screen the window exists to save a trip to.
    @Test func aCodeTheBrowserCouldNotDeliverCanBePastedHere() throws {
        #expect(try Self.field(names: "login.manualCodeExpected"), """
            the field no longer asks whether a code is actually wanted
            """)
        #expect(try Self.field(names: "login.submit(code:"), """
            the field takes a code and never submits it
            """)
    }

    /// `submit` refuses a code that is not the code from the page without
    /// spending the grant: the attempt stays alive and `message` says so. The
    /// row above cannot carry that sentence — it suppresses its note while this
    /// field is up — so the field has to, and it must not empty itself while
    /// saying it. Emptied unconditionally it threw away the very text that
    /// needed correcting, and changed nothing else on screen.
    @Test func aRefusedCodeIsExplainedAndNotThrownAway() throws {
        #expect(try Self.field(names: "login.message"), """
            the field prints a fixed heading and never the sentence the \
            controller wrote — a refused code then changes nothing on screen
            """)
        #expect(try Self.field(names: "if !login.manualCodeExpected { pastedCode = \"\" }"), """
            the field empties itself whatever came of the code, so correcting a \
            typo means retyping the whole thing from the page
            """)
    }

    /// Both halves of one guard. The window shows the field only for a sign-in
    /// it started; the settings screen has to refuse the mirror case, or an
    /// attempt begun in the window and sent back for a code puts a field on
    /// each screen, bound to two different strings, each offering to spend the
    /// one grant there is.
    @Test func onlyOneScreenEverAsksForTheCode() throws {
        #expect(try Self.field(names: "login.request?.origin == .window"), """
            the window offers to finish a sign-in the settings screen started
            """)
        #expect(try Self.surface("App/Settings/AccountsPane.swift",
                                 mentions: "loginController.request?.origin == .settings"), """
            the settings screen offers to finish a sign-in the limits window \
            started
            """)
        #expect(try !Self.surface("App/Settings/AccountsPane.swift",
                                  mentions: "if loginController.manualCodeExpected {"), """
            the settings screen's field is back to asking only whether a code \
            is wanted, with no question of who it is wanted from
            """)
    }

    // MARK: - where the answer goes

    /// Success used to open the settings window whatever had asked for the
    /// sign-in, which was right while settings was the only screen with the
    /// button on it. Left that way, pressing the button in a row would end by
    /// opening the screen the button exists to avoid.
    @Test func successGoesBackToWhicheverScreenAsked() throws {
        #expect(try Self.completion(names: "if origin == .settings"), """
            the sign-in's completion no longer asks which screen started it — a \
            repair made in the limits window then ends in the window it was \
            meant to replace
            """)
        #expect(try Self.completionAsksBeforeItOpens(), """
            settings is opened before anybody asks which screen started the \
            sign-in
            """)
        #expect(try Self.completion(names: "dismissSuccessNotice"), """
            a sign-in finished in the limits window leaves its success notice \
            standing — and the only thing that draws or dismisses it is a \
            banner in the settings window, which this branch is not opening. It \
            waits there, and greets whoever opens settings days later
            """)
    }

    /// The window reads four things off `LoginController` and observes none of
    /// them unless it is told to: the controller is a separate
    /// `ObservableObject` hanging off `AppModel`, and the model republishes
    /// nothing of its own. Nothing looked broken, because the countdown's
    /// one-second tick redraws the window anyway — so every transition simply
    /// arrived up to a second after the press, and the feature would have gone
    /// still the day that timer was slowed or removed.
    @Test func theWindowWatchesTheSignInRatherThanReadingIt() throws {
        #expect(try Self.surface(Self.popover, mentions: "@ObservedObject private var login: LoginController"), """
            the window reads the sign-in controller without observing it, and \
            redraws only when the countdown happens to tick
            """)
    }

    // MARK: - VoiceOver

    /// An account row collapses into one spoken element, which is what makes it
    /// readable at all — `Accessibility` explains why. A button inside a
    /// collapsed element cannot be reached, so the action is named on the
    /// element itself and arrives in the actions rotor instead.
    @Test func theOfferIsReachableWithoutAMouse() throws {
        for name in ["AccountRow", "MinimalAccountRow"] {
            #expect(try Self.row(name, mentions: ".accessibilitySignIn(signIn"), """
                \(name) draws a button VoiceOver cannot reach: the row is one \
                element by design, and nothing inside one is steppable
                """)
            #expect(try Self.row(name, mentions: "cancel: loc(\"Cancel\")"), """
                \(name) names the sign-in to VoiceOver and not the cancel — an \
                attempt can then be started from this window and not stopped, \
                which is a five-minute timeout spent watching a button that \
                cannot be reached
                """)
        }
    }

    // MARK: - the words

    /// The sentence names the service. Two are watched at once in the window
    /// this was built for, and "signing in…" over a list of four accounts says
    /// nothing about which of two browsers' worth of OAuth is being waited on.
    @MainActor
    @Test func theSentenceNamesTheServiceItIsWaitingOn() {
        let loc = Localization()
        #expect(loc.signInState(.running, provider: .claude).contains("Claude"))
        #expect(loc.signInState(.running, provider: .codex).contains("Codex"))
        #expect(loc.signInState(.saving, provider: .claude)
                != loc.signInState(.running, provider: .claude),
                "a keychain write and a wait on the browser read as the same thing")
        #expect(loc.signInState(.offered, provider: .claude) == loc.failureText(.needsLogin),
                """
                the button says one thing about a dead token and the row it sits \
                in says another
                """)
    }

    // MARK: - asking

    private static let surfacesWithoutABrowser = [
        "Widget/LimitsWidgetView.swift",
        "iOSWidget/PhoneWidgetView.swift",
        "iOS/LimitsScreen.swift",
    ]

    private static func fullRow(names phrase: String) throws -> Bool {
        try slice("public var body: some View {",
                  of: "Packages/Core/Sources/StatusUI/AccountRow.swift",
                  what: "the full row's body").contains(phrase)
    }

    /// The minimal row puts its failure branch in `line`, not in `body`.
    private static func minimalRow(names phrase: String) throws -> Bool {
        try slice("private var line: some View {",
                  of: "Packages/Core/Sources/StatusUI/MinimalAccountRow.swift",
                  what: "the minimal row's line").contains(phrase)
    }

    private static func row(_ name: String, mentions phrase: String) throws -> Bool {
        try text(at: "Packages/Core/Sources/StatusUI/\(name).swift").contains(phrase)
    }

    private static func surface(_ path: String, mentions phrase: String) throws -> Bool {
        try text(at: path).contains(phrase)
    }

    private static func window(_ shape: String, names phrase: String) throws -> Bool {
        try slice("private var \(shape): some View {", of: popover,
                  what: "the \(shape) window").contains(phrase)
    }

    private static func offer(names phrase: String) throws -> Bool {
        try slice("private func signIn(for snapshot: AccountSnapshot) -> SignInOffer? {",
                  of: popover, what: "the offer builder").contains(phrase)
    }

    private static func field(names phrase: String) throws -> Bool {
        try slice("private var pastedCodeField: some View {", of: popover,
                  what: "the pasted-code field").contains(phrase)
    }

    private static func completion(names phrase: String) throws -> Bool {
        try completionHandler().contains(phrase)
    }

    /// Order matters as much as presence: the check has to come first, or the
    /// window is opened before anything asks whether it should be.
    private static func completionAsksBeforeItOpens() throws -> Bool {
        let handler = try completionHandler()
        guard let asks = handler.range(of: "if origin == .settings"),
              let opens = handler.range(of: "SettingsWindow.open()") else { return false }
        return asks.lowerBound < opens.lowerBound
    }

    private static func completionHandler() throws -> String {
        try slice("model.login.didAddAccount = { [weak model, preferences] ref, origin in",
                  of: "App/SoftcapApp.swift", what: "the sign-in's completion handler")
    }

    // MARK: - reading

    private static let popover = "App/PopoverView.swift"

    /// One declaration, from its opening line to wherever it ends. Taken by
    /// shape rather than by line number, which a later edit would move.
    ///
    /// Two endings are looked for and the nearer one wins: a closing brace back
    /// at the body's own indent, and the start of the next declaration. Neither
    /// is enough alone — the completion handler is a closure inside a method and
    /// has no `private` after it for a dozen lines, and a `body` ending in
    /// modifiers has a brace before its last line. Taking the further of the two
    /// pulls in the declaration after it, and a check reading that would pass on
    /// somebody else's lines.
    ///
    /// A declaration that cannot be found throws rather than returning empty: a
    /// slice of nothing fails every `contains` with a message about the phrase,
    /// which sends whoever reads it looking for a phrase that is fine.
    private static func slice(_ opening: String, of path: String, what: String) throws -> String {
        let source = try text(at: path)
        guard let start = source.range(of: opening) else {
            throw ScanIsLookingInTheWrongPlace(what: what, found: 0, least: 1)
        }
        let rest = source[start.upperBound...]
        let endings = [
            rest.range(of: "\n        }\n"),
            rest.range(of: "\n    private "),
        ].compactMap(\.self)
        guard let end = endings.map(\.lowerBound).min() else { return String(rest) }
        return String(rest[..<end])
    }

    private static func text(at path: String) throws -> String {
        try String(contentsOf: repositoryRoot.appendingPathComponent(path), encoding: .utf8)
    }

    private static var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
