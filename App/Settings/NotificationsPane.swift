import SwiftUI
import Preferences
import StatusUI
import ProviderKit

struct NotificationsPane: View {
    @ObservedObject var model: PreferencesModel
    @ObservedObject var appModel: AppModel
    @ObservedObject var loc = Localization.shared
    @State private var draftThreshold = ""

    var body: some View {
        Pane(title: loc("Notifications"),
             subtitle: loc("An event fires when a threshold is crossed upward, not on every poll above it.")) {
            Form {
                Toggle(loc("Notify"), isOn: binding(\.notificationsEnabled))

                // The switch above says what the app will try. This says whether
                // the system will let it — two different things, and only the
                // first was ever shown. Denied, or left unanswered because the
                // prompt appeared behind other windows, the app posted
                // notifications that went nowhere and the screen looked fine.
                if model.value.notificationsEnabled && !appModel.notificationsPermitted {
                    Text(loc("macOS is not delivering notifications for Softcap. Turn them on under Notifications in System Settings."))
                        .font(.system(size: 11))
                        .foregroundStyle(Severity.hot.tint)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // Everything but the switch itself is disabled: otherwise, once
                // notifications are off, there is no way to turn them back on.
                Group {
                Section(loc("Thresholds")) {
                    HStack(spacing: 6) {
                        ForEach(model.value.thresholds, id: \.self) { level in
                            HStack(spacing: 4) {
                                Text(loc.percent(Double(level))).font(.system(size: 11.5))
                                Button {
                                    model.update { $0.thresholds.removeAll { $0 == level } }
                                } label: {
                                    Image(systemName: "xmark").font(.system(size: 8))
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(.secondary)
                                // Inside a capsule already, so the chip is
                                // small and round rather than a second pill.
                                .clickAffordance(inset: CGSize(width: 3, height: 3), radius: 7)
                            }
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(.quaternary, in: Capsule())
                        }

                        TextField("+", text: $draftThreshold)
                            .frame(width: 44)
                            .onSubmit(addThreshold)
                    }
                    if model.value.thresholds.isEmpty {
                        Text(loc("No thresholds — no load notifications."))
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }

                Toggle(loc("When free again"), isOn: binding(\.notifyOnRecovery))

                Picker(loc("Which windows"), selection: binding(\.notifyWindows)) {
                    ForEach(WindowScope.allCases, id: \.self) { Text(loc.title($0)).tag($0) }
                }
                .pickerStyle(.segmented)

                Section(loc("Quiet hours")) {
                    Toggle(loc("Do not disturb at night"), isOn: quietEnabled)
                    if let hours = model.value.quietHours {
                        HStack {
                            timeField(loc("From"), minutes: hours.startMinute) { new in
                                model.update {
                                    $0.quietHours = QuietHours(
                                        startMinute: new, endMinute: hours.endMinute)
                                }
                            }
                            timeField(loc("to"), minutes: hours.endMinute) { new in
                                model.update {
                                    $0.quietHours = QuietHours(
                                        startMinute: hours.startMinute, endMinute: new)
                                }
                            }
                        }
                    }
                }
                }
                .disabled(!model.value.notificationsEnabled)
            }
            .formStyle(.grouped)
            .alignedWithTheHeading()
        }
    }

    private func addThreshold() {
        guard let level = Int(draftThreshold.trimmingCharacters(in: .whitespaces)),
              level > 0, level <= 100
        else { draftThreshold = ""; return }
        model.update { $0.thresholds.append(level) }   // normalized() will sort
        draftThreshold = ""
    }

    private var quietEnabled: Binding<Bool> {
        Binding(
            get: { model.value.quietHours != nil },
            set: { on in
                model.update {
                    $0.quietHours = on
                        ? QuietHours(startMinute: 23 * 60, endMinute: 9 * 60)
                        : nil
                }
            }
        )
    }

    private func timeField(
        _ label: String, minutes: Int, set: @escaping (Int) -> Void
    ) -> some View {
        HStack(spacing: 5) {
            Text(label).foregroundStyle(.secondary).font(.system(size: 11.5))
            Stepper(
                value: Binding(get: { minutes }, set: set),
                in: 0...(24 * 60 - 1), step: 30
            ) {
                Text(String(format: "%02d:%02d", minutes / 60, minutes % 60))
                    .monospacedDigit()
            }
        }
        .task { await appModel.refreshNotificationAuthorization() }
    }

    private func binding<T>(_ path: WritableKeyPath<Preferences, T>) -> Binding<T> {
        Binding(
            get: { model.value[keyPath: path] },
            set: { newValue in model.update { $0[keyPath: path] = newValue } }
        )
    }
}
