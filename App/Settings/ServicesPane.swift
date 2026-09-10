import SwiftUI
import AppKit
import ProviderKit
import Preferences
import StatusUI

struct ServicesPane: View {
    @ObservedObject var model: PreferencesModel
    @ObservedObject private var loc = Localization.shared

    private static let planned: [ProviderID] = [.cursor, .copilot, .gemini]

    var body: some View {
        Pane(title: loc("Services"),
             subtitle: loc("Where data comes from. A disabled service is not polled.")) {
            Form {
                Section {
                    Toggle("Claude Code", isOn: enabled(.claude))
                    Text(loc("Live data from the API."))
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }

                Section {
                    Toggle("OpenAI Codex", isOn: enabled(.codex))
                    HStack {
                        Text(model.value.codexRoot ?? "~/.codex")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Button(loc("Choose…")) { chooseCodexRoot() }
                        if model.value.codexRoot != nil {
                            Button(loc("Reset")) { model.update { $0.codexRoot = nil } }
                        }
                    }
                    Text(loc("Browser accounts use live usage data. Local accounts use snapshots from session files."))
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }

                Section(loc("Later")) {
                    ForEach(Self.planned, id: \.self) { provider in
                        HStack {
                            Text(provider.title)
                            Spacer()
                            Text(loc("later"))
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                        .foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)
            .alignedWithTheHeading()
        }
    }

    private func enabled(_ provider: ProviderID) -> Binding<Bool> {
        Binding(
            get: { !model.value.disabledProviders.contains(provider) },
            set: { on in
                model.update {
                    if on { $0.disabledProviders.remove(provider) }
                    else { $0.disabledProviders.insert(provider) }
                }
            }
        )
    }

    private func chooseCodexRoot() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = loc("Choose…")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.update { $0.codexRoot = url.path }
    }
}
