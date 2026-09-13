import SwiftUI
import Preferences
import StatusUI

struct AppearancePane: View {
    @ObservedObject var model: PreferencesModel
    @ObservedObject var appModel: AppModel
    @ObservedObject var loc = Localization.shared
    @State private var showsAccountOrder = false

    var body: some View {
        Pane(title: loc("Appearance"),
             subtitle: loc("Language, light or dark, and how the menu bar and account rows look.")) {
            Form {
                Picker(loc("Language"), selection: languageBinding) {
                    Text(loc("System")).tag(AppLanguage.system)
                    Divider()
                    ForEach(AppLanguage.allCases.filter { $0 != .system }) { language in
                        Text(language.endonym).tag(language)
                    }
                }

                Picker(loc("Appearance"), selection: binding(\.appearance)) {
                    ForEach(Appearance.allCases, id: \.self) { Text(loc.title($0)).tag($0) }
                }
                .pickerStyle(.segmented)

                Picker(loc("In the menu bar"), selection: binding(\.menuBarContent)) {
                    ForEach(MenuBarContent.allCases, id: \.self) { Text(loc.title($0)).tag($0) }
                }
                .pickerStyle(.segmented)

                Picker(loc("Primary window"), selection: binding(\.primaryWindow)) {
                    ForEach(PrimaryWindow.allCases, id: \.self) { Text(loc.title($0)).tag($0) }
                }

                Toggle(loc("Minimal window"), isOn: binding(\.minimalWindow))

                Picker(loc("Row layout"), selection: binding(\.rowLayout)) {
                    ForEach(RowLayout.allCases, id: \.self) { Text(loc.title($0)).tag($0) }
                }
                // A row layout describes the full window, and the minimal one
                // does not have one. Disabled rather than hidden: a setting
                // that vanishes reads as a bug, a grey one explains itself.
                .disabled(model.value.minimalWindow)

                Picker(loc("Order"), selection: orderingBinding) {
                    ForEach(Ordering.allCases, id: \.self) { Text(loc.title($0)).tag($0) }
                }

                if model.value.ordering == .custom {
                    HStack {
                        Spacer()
                        Button(loc("Arrange accounts…")) { showsAccountOrder = true }
                    }
                }

                Toggle(loc("Show snapshot age"), isOn: binding(\.showSnapshotAge))
            }
            .formStyle(.grouped)
            .alignedWithTheHeading()
        }
        .sheet(isPresented: $showsAccountOrder) {
            AccountOrderEditor(model: model, appModel: appModel)
        }
        // The window comes out while this screen is open. Every control here
        // changes something a person cannot see from here — the appearance, what
        // the menu bar says, whether the rows are the compact ones — and the
        // window that would show it closes itself the moment this one is
        // clicked. Asking for it on the way in and letting it go on the way out
        // covers leaving for another screen and closing settings alike.
        .onAppear { appModel.askForAppearancePreview() }
        .onDisappear { appModel.releaseAppearancePreview() }
    }

    private var orderingBinding: Binding<Ordering> {
        Binding(
            get: { model.value.ordering },
            set: { ordering in
                model.update {
                    if ordering == .custom, $0.customAccountOrder.isEmpty {
                        $0.setCustomAccountOrder(appModel.snapshots.map(\.id))
                    }
                    $0.ordering = ordering
                }
                showsAccountOrder = ordering == .custom
            }
        )
    }

    /// The language is stored as a code while the enum lives in the interface
    /// layer, so this binding translates between the two.
    private var languageBinding: Binding<AppLanguage> {
        Binding(
            get: { AppLanguage(code: model.value.languageCode) },
            set: { language in
                model.update { $0.languageCode = language == .system ? nil : language.rawValue }
            }
        )
    }

    private func binding<T>(_ path: WritableKeyPath<Preferences, T>) -> Binding<T> {
        Binding(
            get: { model.value[keyPath: path] },
            set: { newValue in model.update { $0[keyPath: path] = newValue } }
        )
    }
}
