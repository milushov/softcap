import SwiftUI
import Preferences
import StatusUI

struct AppearancePane: View {
    @ObservedObject var model: PreferencesModel
    @ObservedObject var loc = Localization.shared

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

                Picker(loc("Row layout"), selection: binding(\.rowLayout)) {
                    ForEach(RowLayout.allCases, id: \.self) { Text(loc.title($0)).tag($0) }
                }

                Picker(loc("Order"), selection: binding(\.ordering)) {
                    ForEach(Ordering.allCases, id: \.self) { Text(loc.title($0)).tag($0) }
                }

                Toggle(loc("Show snapshot age"), isOn: binding(\.showSnapshotAge))
            }
            .formStyle(.grouped)
            .alignedWithTheHeading()
        }
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
