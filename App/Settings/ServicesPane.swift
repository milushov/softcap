import SwiftUI
import ProviderKit
import Preferences
import StatusUI

struct ServicesPane: View {
    @ObservedObject var model: PreferencesModel
    @ObservedObject private var loc = Localization.shared

    private static let planned: [ProviderID] = [.cursor, .gemini, .glm]

    var body: some View {
        Pane(title: loc("Services"),
             subtitle: loc("Where data comes from. A disabled service is not polled.")) {
            Form {
                Section {
                    Toggle(ProviderID.claude.productName, isOn: enabled(.claude))
                    Text(loc("Live data from the API."))
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }

                Section {
                    Toggle(ProviderID.codex.productName, isOn: enabled(.codex))
                    Text(loc("Live data from the API."))
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }

                Section {
                    Toggle(ProviderID.copilot.productName, isOn: enabled(.copilot))
                    Text(loc("Live data from the API."))
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }

                Section(loc("Later")) {
                    ForEach(Self.planned, id: \.self) { provider in
                        HStack {
                            // The product name, as the site, the FAQ in ten
                            // languages and the README all give it. `title` is
                            // Core's short caption for a row twenty points
                            // high; it happened to equal the product name for
                            // Cursor and Gemini, and GLM is the first planned
                            // service where the two differ — so this screen
                            // said "GLM" while everything else said "GLM
                            // Coding Plan", and `productName` sat unread.
                            Text(provider.productName)
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
}
