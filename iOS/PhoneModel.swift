import Foundation
import SwiftUI
import ProviderKit
import ClaudeProvider
import Credentials
import Monitoring
import Preferences
import StatusUI
import WidgetKit

/// The phone's state.
///
/// Claude is queried directly: the token travels through the iCloud keychain, so
/// the phone needs no Mac to be awake. Codex cannot work that way — its data
/// lives in local files on the Mac — so on iOS it is absent rather than shown as
/// an empty row pretending to be a limit.
@MainActor
final class PhoneModel: ObservableObject {
    @Published fileprivate(set) var snapshots: [AccountSnapshot] = []
    @Published private(set) var isRefreshing = false
    @Published fileprivate(set) var lastUpdated: Date?

    private let store: CredentialStore
    private let preferencesStore: PreferencesStore
    private(set) var preferences: Preferences = .defaults

    init(
        store: CredentialStore = CredentialStore(
            keychain: SystemKeychain(), refresher: AnthropicTokenRefresher()
        ),
        preferencesStore: PreferencesStore = PreferencesStore(storage: UserDefaultsStorage())
    ) {
        self.store = store
        self.preferencesStore = preferencesStore
    }

    func start() async {
        await store.load()
        preferences = await preferencesStore.load()
        Localization.shared.use(AppLanguage(code: preferences.languageCode))
        await refresh()
    }

    /// Coming back to the app after it was suspended.
    ///
    /// Separate from `refresh()` so it can decline: the setting is the one the
    /// Mac uses for waking from sleep, and the first activation happens while
    /// `start()` is already polling — refreshing again there would be two polls
    /// for one launch.
    func refreshOnReturn() async {
        guard preferences.refreshAfterWake, lastUpdated != nil else { return }
        await refresh()
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        let refs = await store.knownRefs()
            .filter { !preferences.hiddenAccounts.contains($0.id) }
        let poller = UsagePoller(providers: [
            ClaudeUsageProvider(tokens: store, knownAccounts: refs)
        ])

        snapshots = orderedForDisplay(await poller.refresh(), ordering: preferences.ordering)
        lastUpdated = Date()
        publishToWidget()
    }

    /// Hands the snapshot to the widget through the shared group container and
    /// asks the system to redraw. The widget is a separate process and never
    /// reaches the network itself.
    private func publishToWidget() {
        SharedStore.write(SharedSnapshot(
            accounts: snapshots,
            capturedAt: Date(),
            rowLayout: preferences.rowLayout,
            showSnapshotAge: preferences.showSnapshotAge,
            languageCode: preferences.languageCode,
            pollingEvery: preferences.backgroundInterval
        ))
        WidgetCenter.shared.reloadAllTimelines()
    }
}

extension PhoneModel {
    /// A model filled with ready data, for previews. Bypasses the keychain and
    /// the network: a preview must render without either.
    static func preview(accounts: [AccountSnapshot]) -> PhoneModel {
        let model = PhoneModel()
        model.snapshots = accounts
        model.lastUpdated = Date()
        return model
    }
}
