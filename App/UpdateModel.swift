import Foundation
import AppKit
import os
import ProviderKit
import ClaudeProvider
import Diagnostics
import Preferences
import Updates

/// What the app knows about a newer version, and what it is doing about it.
///
/// Held for the life of the app rather than by a view: a download that outlives
/// the settings window is the point. Closing the window part-way through does
/// not cancel it — the app comes back on its own when it is done.
@MainActor
final class UpdateModel: ObservableObject {

    /// Where a newer version is looked for, and what is done about one.
    ///
    /// The copy from GitHub reads GitHub's release feed and installs what it
    /// finds. The copy from the App Store reads the store's record and only
    /// says so: the store installs its own releases — and not while the app is
    /// running, which for a menu bar app means never, unless somebody is told.
    /// Decided when the app is built, because the two are different programs
    /// with one codebase, not one program with a setting.
    enum Channel { case github, appStore }

    #if APPSTORE
    static let channel = Channel.appStore
    #else
    static let channel = Channel.github
    #endif

    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available(Release)
        case installing(UpdateInstaller.Phase)
        case failed(UpdateFailure)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var lastChecked: Date?

    /// Fed by whoever owns the settings, the same way `AppModel` is.
    ///
    /// `@Published` for the reason written beside that one: a settings copy
    /// that announces nothing is a setting that does not apply. No view reads
    /// this one today; the next one to do so should not have to find that out.
    @Published var preferences: Preferences = .defaults {
        didSet { lastChecked = preferences.lastUpdateCheck }
    }

    /// Called when a check finishes, so the moment is stored where it survives a
    /// restart. The model does not own the settings store.
    var recordCheck: ((Date) -> Void)?

    private static let log = Logger(subsystem: "app.softcap.Softcap", category: "updates")

    private let http: any HTTPClient
    private let downloader: any FileDownloader
    private var tick: Timer?

    /// Whether a request is out. See `check(now:announcing:)`.
    private var inFlight = false

    /// When this last *asked*, as opposed to when it last got an answer.
    /// Not persisted: it bounds what one run of the app does, and a fresh
    /// launch asking once is the behaviour that was always wanted.
    private var lastAsked: Date?
    private var wakeObserver: (any NSObjectProtocol)?

    init(
        http: any HTTPClient = URLSessionHTTPClient(),
        downloader: any FileDownloader = URLSessionFileDownloader()
    ) {
        self.http = http
        self.downloader = downloader
    }

    // MARK: - what is running

    /// The version this build reports. `nil` only if the bundle carries no
    /// version string at all, which no built app does — but a bundle that lies
    /// about its version is exactly what this feature had to fix first, so the
    /// absence is handled rather than forced.
    var runningVersion: ReleaseVersion? {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String)
            .flatMap(ReleaseVersion.init)
    }

    var versionText: String { runningVersion?.description ?? "—" }

    var releasePage: URL {
        switch Self.channel {
        case .github:   Repository.releases
        case .appStore: Storefront.inStore
        }
    }

    /// Where the escape hatch goes: the page of the release that was being
    /// installed, when there is one, and the newest otherwise.
    ///
    /// `Release.page` was decoded and never read while the button always opened
    /// `/releases/latest` — so an install of 0.1.47 that failed could send
    /// somebody to 0.1.48 to download it by hand.
    var pageToOpen: URL {
        // The store's record names its web page; the Update button is in the
        // App Store app, so that is where the store copy sends a person.
        if Self.channel == .appStore { return releasePage }
        if case .available(let release) = state { return release.page }
        if case .installing = state { return releasePage }
        return offered?.page ?? releasePage
    }

    /// The release last found, kept across a failed install so the escape hatch
    /// still knows which one it was.
    private var offered: Release?

    /// The version to offer, when there is one. Read by the menu and the footer,
    /// which is the whole of how loudly a found update announces itself.
    var availableVersion: ReleaseVersion? {
        if case .available(let release) = state { return release.version }
        return nil
    }

    var isInstalling: Bool {
        if case .installing = state { return true }
        return false
    }

    // MARK: - checking

    /// Keeps the daily check happening.
    ///
    /// `checkIfDue` had exactly one call site — the launch — so a menu bar app
    /// that starts at login and never quits checked once, ever, while the
    /// README, the landing page and the decision log all said once a day.
    /// `UpdateSchedule` was written, tested and then never asked again.
    ///
    /// The tick is hourly and the schedule decides; a machine that was asleep
    /// for two days is caught by the wake notification rather than by waiting
    /// for the next hour to come round.
    func startChecking() {
        let hourly = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in await self?.checkIfDue(now: Date()) }
        }
        RunLoop.main.add(hourly, forMode: .common)
        tick = hourly

        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in await self?.checkIfDue(now: Date()) }
        }

        Task { await checkIfDue(now: Date()) }
    }

    /// The quiet check: at launch, and a day apart after that.
    func checkIfDue(now: Date) async {
        await checkQuietly(now: now, when: UpdateSchedule.isDue)
    }

    /// The check that happens because somebody opened the screen showing the
    /// answer, and the answer is old.
    ///
    /// The Updates screen offered 0.1.3 for the rest of a day in which seven
    /// further releases were published. Nothing was wrong: the check had run at
    /// 09:57 UTC, was correct then, and the next one was not due for another
    /// seventeen hours. A screen whose only job is to say whether there is a newer version
    /// should not be reading out this morning's answer to somebody looking at it
    /// now.
    ///
    /// Still governed by the switch. Having the screen open is not the same as
    /// pressing the button on it, and the app's promise is that nothing reaches
    /// GitHub while automatic checking is off.
    func checkIfStale(now: Date) async {
        await checkQuietly(now: now, when: UpdateSchedule.isStale)
    }

    /// The one gate every check nobody asked for passes through.
    ///
    /// The switch is read here and in no other place. It was written out twice
    /// the day the second quiet check was added, which is how a promise made in
    /// ten languages comes to rest on somebody remembering to copy a line: a
    /// third entry point copies it a third time, and the one that forgets
    /// reaches GitHub for a person who turned this off.
    ///
    /// The moment compared against is the last time this asked, not the last
    /// time it succeeded. `lastUpdateCheck` is only stamped by a check that
    /// finished, so a machine that is offline — or a client GitHub is rate
    /// limiting — would find every attempt overdue and ask again on every pane
    /// switch, forever. The floor has to hold for the case that repeats.
    private func checkQuietly(now: Date, when isTime: (Date?, Date) -> Bool) async {
        guard preferences.checksForUpdates else { return }
        let asked = [lastAsked, preferences.lastUpdateCheck].compactMap { $0 }.max()
        guard isTime(asked, now) else { return }
        await check(now: now, announcing: false)
    }

    /// The check somebody asked for. Says "this is the latest version" where the
    /// quiet one says nothing.
    func check(now: Date) async {
        await check(now: now, announcing: true)
    }

    /// What the menu item does: show what is already known, and only ask again
    /// when there is nothing to show.
    ///
    /// It used to ask unconditionally, which threw away a release the daily
    /// check had already found and, with no guard on a second press, ran two
    /// checks at once.
    func checkUnlessSomethingIsAlreadyOffered(now: Date) async {
        switch state {
        case .available, .checking, .installing: return
        case .idle, .upToDate, .failed:          await check(now: now)
        }
    }

    private func check(now: Date, announcing: Bool) async {
        // One at a time. Nothing held a token for a check in flight, and the
        // quiet one never sets `.checking`, so it was invisible to the only
        // guard there was: one click on the menu item opened the window — whose
        // pane asks — and then asked again beside it, two requests deep.
        guard !inFlight, !isInstalling else { return }
        inFlight = true
        defer { inFlight = false }

        lastAsked = now
        if announcing { state = .checking }

        guard let running = runningVersion else {
            // Not .malformedRelease: nothing is wrong with the release, and
            // "The newest release has no build to download." blamed the wrong
            // side of a comparison this app could not make.
            Self.log.error("this bundle carries no version, so nothing can be compared")
            report(UpdateFailure(kind: .unpackFailed, diagnostic: "no version in this bundle"),
                   announcing: announcing)
            return
        }

        do {
            let found: Release?
            switch Self.channel {
            case .github:
                let url = ReleaseFeed.latestURL(owner: Repository.owner, repository: Repository.name)
                let (data, status) = try await http.get(url, headers: [
                    "Accept": "application/vnd.github+json",
                ])
                // A 404 carries two answers at once: nothing has been published,
                // and the repository is not one this caller can see. An
                // unauthenticated request cannot tell them apart and the screen
                // says the same thing either way — so the status goes to the
                // log, where somebody wondering why a check never finds anything
                // can read it. It was a private repository the first time this
                // mattered.
                if status == 404 {
                    Self.log.info("releases: 404, so nothing published or nothing visible")
                }
                found = try ReleaseFeed.update(from: data, status: status, running: running)
            case .appStore:
                let (data, status) = try await http.get(Storefront.lookup, headers: [:])
                found = try StoreListing.update(from: data, status: status, running: running)
            }
            recordCheck?(now)
            lastChecked = now
            settle(on: found, announcing: announcing)
        } catch let failure as UpdateFailure {
            report(failure, announcing: announcing)
        } catch let failure as ProviderFailure {
            report(UpdateFailure(kind: .network, diagnostic: failure.diagnostic),
                   announcing: announcing)
        } catch {
            report(UpdateFailure(kind: .network, diagnostic: "\(type(of: error))"),
                   announcing: announcing)
        }
    }

    /// What a finished check is allowed to write.
    ///
    /// A quiet check may improve the screen and may never weaken it. Every
    /// sentence this app can show is an answer of some strength — a version to
    /// install, "This is the latest version.", "No new version has been
    /// found." — and a check nobody asked for arriving at a weaker one is not
    /// news, it is a screen changing by itself while somebody reads it.
    ///
    /// The 404 is why this is not only about failures. `ReleaseFeed` maps it to
    /// "nothing newer", on the success path, and the comment above says why it
    /// is ambiguous: a release mid-publish and a repository this caller cannot
    /// see are the same answer. Taking an offer off the screen for it, and
    /// stamping the moment so that neither schedule asks again, left the app
    /// privately still holding the release whose page the escape hatch opens.
    private func settle(on found: Release?, announcing: Bool) {
        // An install that began while this request was in flight owns the
        // screen: `install()` can only start from `.available`, which is the
        // state a quiet check leaves up while it asks.
        if case .installing = state { return }

        if let found {
            Self.log.info("a newer release: \(found.version.description, privacy: .public)")
            offered = found
            state = .available(found)
            return
        }

        if announcing { state = .upToDate }
    }

    /// A check nobody asked for keeps its failure in the log. The one somebody
    /// pressed a button for puts it on screen — a button that does nothing
    /// visible reads as broken.
    private func report(_ failure: UpdateFailure, announcing: Bool) {
        // Navigating away is not an outage. SwiftUI cancels a `.task` when its
        // view goes, `URLSession` turns that into `URLError -999`, and one door
        // down it is a `ProviderFailure` that reads exactly like a dropped
        // connection — so leaving the Updates pane quickly would log an error,
        // post a report to the author, and rewrite the screen on the way out.
        // `PollScheduler` carries a comment about this same mistake, made once
        // already against the accounts list.
        guard !Task.isCancelled else { return }

        Self.log.error("update check failed: \(failure.diagnostic, privacy: .public)")
        // Every failed check funnels through here, announced or not, which makes
        // it the one place worth describing rather than three.
        let diagnostic = failure.diagnostic
        let kind = "UpdateFailure.\(failure.kind)"
        Task {
            await Diagnostics.shared.report(
                .error, category: "updates", message: diagnostic, failureType: kind)
        }
        // A quiet check says nothing when it fails, and that includes saying
        // nothing on the screen. It used to fall through to idle either way,
        // which was nearly invisible while quiet checks came only from a timer:
        // there was rarely anything to lose. With the screen asking while it is open, a
        // dropped connection would replace "Version 0.1.10 is available" with
        // "No new version has been found." — and the first guard written for it
        // named `.available` alone, leaving an honest red "GitHub could not be
        // reached" to be overwritten by a confident false claim that it had.
        guard announcing else { return }
        state = .failed(failure)
    }

    // MARK: - installing

    func install() async {
        guard case .available(let release) = state else { return }
        // The store copy never shows the button that calls this; the guard is
        // for the day something else does. `UpdateInstaller` would refuse the
        // release anyway — it has nothing to download — but "the App Store
        // installs it" is the sentence to end on, not "no build to download".
        guard Self.channel == .github else { return }

        let bundle = Bundle.main.bundleURL
        let installer = UpdateInstaller(downloader: downloader, http: http)
        state = .installing(.downloading(0))

        do {
            try await installer.install(release, replacing: bundle) { phase in
                Task { @MainActor [weak self] in self?.state = .installing(phase) }
            }
        } catch let failure as UpdateFailure {
            Self.log.error("install failed: \(failure.diagnostic, privacy: .public)")
            let diagnostic = failure.diagnostic
            let kind = "UpdateFailure.\(failure.kind)"
            Task {
                await Diagnostics.shared.report(
                    .error, category: "updates.install", message: diagnostic, failureType: kind)
            }
            state = .failed(failure)
            return
        } catch {
            state = .failed(UpdateFailure(kind: .unpackFailed, diagnostic: "\(type(of: error))"))
            return
        }

        guard UpdateInstaller.restart(bundle) else {
            // Installed, but nothing is waiting to bring it back. Quitting here
            // would leave the new version in place and the app simply gone,
            // which is the one outcome worse than not restarting.
            Self.log.error("installed \(release.version.description, privacy: .public), but the relaunch would not start")
            state = .failed(UpdateFailure(kind: .unpackFailed, diagnostic: "relaunch would not start"))
            return
        }

        Self.log.info("installed \(release.version.description, privacy: .public), restarting")
        NSApp.terminate(nil)
    }
}
