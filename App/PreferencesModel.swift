import Foundation
import SwiftUI
import Preferences
import StatusUI

/// A SwiftUI wrapper over `PreferencesStore`: holds the current value and saves
/// every change immediately, without an Apply button — the macOS convention.
@MainActor
final class PreferencesModel: ObservableObject {
    @Published private(set) var value: Preferences = .defaults

    private let store: PreferencesStore

    init(store: PreferencesStore = PreferencesStore(storage: UserDefaultsStorage())) {
        self.store = store
    }

    func load() async {
        value = await store.load()
        applyLanguage()
    }

    func update(_ change: (inout Preferences) -> Void) {
        var draft = value
        change(&draft)
        value = draft.normalized()
        applyLanguage()
        let snapshot = value
        Task { await store.save(snapshot) }
    }

    /// The language is applied here and only here.
    ///
    /// It used to be done by both the app delegate and the settings scene. The
    /// scene is created before the settings finish loading, so it overrode the
    /// delegate with the default — the log showed an alternating
    /// "ar → system → ar → system" while the screen stayed English. The owner of
    /// the settings is the only one who knows the current value.
    private func applyLanguage() {
        Localization.shared.use(AppLanguage(code: value.languageCode))
    }
}
