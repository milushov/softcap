import Foundation
import SwiftUI
import Diagnostics
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
        applyTheme()
        applyReporting()
    }

    func update(_ change: (inout Preferences) -> Void) {
        var draft = value
        change(&draft)
        value = draft.normalized()
        applyLanguage()
        applyTheme()
        applyReporting()
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
        // The settings window's title is written by macOS in the system's
        // language; the app writes its own instead, and has to write it again
        // here — a window already open keeps the title it was given.
        SettingsWindow.retitle()
    }

    /// Light or dark, applied here and only here — the same lesson as the
    /// language, learned twice.
    ///
    /// It used to live on the settings scene, as `.onChange(of:)` over
    /// `preferences.value.appearance`. That fires when the scene's body is
    /// re-evaluated, and nothing re-evaluates it when the value changes: the
    /// scene observes the app delegate, and it is this object that publishes. So
    /// the choice was written to disk and applied at the *next* launch, by
    /// `applicationDidFinishLaunching` — which is why switching appeared to do
    /// nothing while the settings window plainly remembered the answer.
    private func applyTheme() {
        applyAppearance(value.appearance)
    }

    /// The reporting switch is followed here for the same reason the language
    /// is: the owner of the settings is the only one that knows the current
    /// value, and somebody who turns reports off expects the next failure to go
    /// unreported rather than the next launch.
    ///
    /// Safe in a debug build, where nothing ever calls `start` and the shared
    /// instance therefore has no reporter to enable.
    private func applyReporting() {
        let wanted = value.sendsErrorReports
        Task { await Diagnostics.shared.setEnabled(wanted) }
    }
}
