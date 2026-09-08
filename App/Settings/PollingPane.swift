import SwiftUI
import Preferences
import StatusUI

struct PollingPane: View {
    @ObservedObject var model: PreferencesModel

    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var launchError: String?
    @State private var recording: String?
    @ObservedObject private var loc = Localization.shared

    var body: some View {
        Pane(title: loc("Polling and launch"),
             subtitle: loc("How often to fetch data and whether to start on its own.")) {
            Form {
                Section {
                    // A binding that writes through `setLaunch` rather than an
                    // `onChange`, so the state can be re-read from the system
                    // without the act of reading it looking like a change and
                    // registering the login item again.
                    Toggle(loc("Launch at login"), isOn: Binding(
                        get: { launchAtLogin },
                        set: { setLaunch($0) }
                    ))
                    if let launchError {
                        Text(launchError)
                            .font(.system(size: 11)).foregroundStyle(.orange)
                    }
                }

                Section(loc("Poll frequency")) {
                    interval(loc("While the window is open"), path: \.foregroundInterval)
                    interval(loc("In the background"), path: \.backgroundInterval)
                    Toggle(loc("Refresh after wake"), isOn: binding(\.refreshAfterWake))
                }

                Section(loc("Hot keys")) {
                    hotKeyRow(loc("Open the window"), path: \.openWindowHotKey)
                    hotKeyRow(loc("Refresh now"), path: \.refreshHotKey)
                }
            }
            .formStyle(.grouped)
            .alignedWithTheHeading()
        }
        // The login item can be switched off in System Settings while this window
        // is open, and nothing tells the app. Read once at init, the switch then
        // says the opposite of the truth — the same gap the notifications screen
        // had, and read back from the system for the same reason.
        .task { launchAtLogin = LaunchAtLogin.isEnabled }
    }

    private func hotKeyRow(
        _ title: String, path: WritableKeyPath<Preferences, HotKeyCombo?>
    ) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(model.value[keyPath: path]?.displayString ?? loc("not set"))
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(model.value[keyPath: path] == nil ? .secondary : .primary)
            Button(recording == title ? loc("Press…") : loc("Change")) {
                recording = recording == title ? nil : title
            }
            if model.value[keyPath: path] != nil {
                Button(loc("Remove")) { model.update { $0[keyPath: path] = nil } }
            }
        }
        .background(
            HotKeyRecorder(isActive: recording == title) { combo in
                model.update { $0[keyPath: path] = combo }
                recording = nil
            }
        )
    }

    private func setLaunch(_ on: Bool) {
        do {
            try LaunchAtLogin.set(on)
            launchAtLogin = on
            launchError = nil
        } catch {
            // Do not pretend it worked: put the switch back.
            launchAtLogin = LaunchAtLogin.isEnabled
            launchError = loc("Could not change launch at login. Check Login Items in System Settings.")
        }
    }

    private func interval(
        _ title: String, path: WritableKeyPath<Preferences, TimeInterval>
    ) -> some View {
        let value = model.value[keyPath: path]
        return Stepper(
            value: Binding(
                get: { value },
                set: { new in model.update { $0[keyPath: path] = new } }
            ),
            in: Preferences.intervalRange,
            step: 30
        ) {
            Text("\(title): \(label(for: value))")
        }
    }

    private func label(for seconds: TimeInterval) -> String {
        seconds < 60
            ? String(format: loc("%lld s"), Int(seconds))
            : String(format: loc("%lld min"), Int(seconds) / 60)
    }

    private func binding<T>(_ path: WritableKeyPath<Preferences, T>) -> Binding<T> {
        Binding(
            get: { model.value[keyPath: path] },
            set: { newValue in model.update { $0[keyPath: path] = newValue } }
        )
    }
}
