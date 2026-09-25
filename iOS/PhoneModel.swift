import Foundation
import SwiftUI
import ProviderKit
import ClaudeProvider
import CodexProvider
import CopilotProvider
import ZaiProvider
import Credentials
import Monitoring
import Preferences
import StatusUI
import WidgetKit

/// The phone's state.
///
/// Saved browser accounts are queried directly using the iCloud keychain.
/// Local Codex session files remain exclusive to the Mac.
@MainActor
final class PhoneModel: ObservableObject {
    @Published fileprivate(set) var snapshots: [AccountSnapshot] = []
    @Published private(set) var isRefreshing = false
    @Published fileprivate(set) var lastUpdated: Date?

    private let store: CredentialStore
    private let preferencesStore: PreferencesStore
    /// Read by the screen for the row layout and the polling interval, so it
    /// announces itself. It is assigned once, in `start()`, and a refresh
    /// follows immediately — which published it by accident of ordering rather
    /// than by intent. See `SettingsCopiesAnnounceThemselves`.
    @Published private(set) var preferences: Preferences = .defaults

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
        var providers: [any UsageProvider] = []
        if !preferences.disabledProviders.contains(.claude) {
            providers.append(ClaudeUsageProvider(tokens: store, knownAccounts: refs))
        }
        if !preferences.disabledProviders.contains(.codex) {
            providers.append(CodexLiveUsageProvider(tokens: store, knownAccounts: refs))
        }
        // Polled here like the other two, and for the same reason it can be:
        // the phone reads saved accounts and never signs one in. It has no
        // accounts of its own to read until Keychain synchronisation is opted
        // into, which `docs/authentication.md` explains is not.
        if !preferences.disabledProviders.contains(.copilot) {
            providers.append(CopilotUsageProvider(tokens: store, knownAccounts: refs))
        }
        if !preferences.disabledProviders.contains(.glm) {
            providers.append(ZaiUsageProvider(tokens: store, knownAccounts: refs))
        }
        let poller = UsagePoller(providers: providers)

        snapshots = orderedForDisplay(
            await poller.refresh(), ordering: preferences.ordering,
            customAccountOrder: preferences.customAccountOrder
        )
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
