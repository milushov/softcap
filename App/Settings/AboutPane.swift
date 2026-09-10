import SwiftUI
import AppKit
import Credentials
import Preferences
import StatusUI

struct AboutPane: View {
    @ObservedObject var model: PreferencesModel
    @ObservedObject var appModel: AppModel

    @State private var confirmForgetAll = false
    @ObservedObject private var loc = Localization.shared

    /// The version, and the build number when it says something the version does
    /// not.
    ///
    /// It used to be "\(short) (\(build))" unconditionally. When the build
    /// number was briefly made equal to the marketing version this printed
    /// "0.1.47 (0.1.47)" — the same non-answer the bare "1" had been, and a
    /// disagreement with the Updates screen three rows away, which shows the
    /// version alone.
    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "—"
        guard let build = info?["CFBundleVersion"] as? String, build != short else {
            return short
        }
        return "\(short) (\(build))"
    }

    var body: some View {
        Pane(title: loc("About and data"),
             subtitle: loc("What the app stores and how to remove it.")) {
            Form {
                Section {
                    LabeledContent(loc("Version"), value: version)
                    LabeledContent(loc("Credentials"),
                                   value: "Keychain · \(CredentialStore.ownService)")
                    LabeledContent(loc("Settings"),
                                   value: "~/Library/Preferences/app.softcap.Softcap.plist")
                }

                // On this screen rather than a privacy tab of its own: the pane
                // already answers "what does this app keep, and where", and what
                // leaves the machine is the other half of that question.
                Section {
                    Toggle(loc("Send error reports"), isOn: Binding(
                        get: { model.value.sendsErrorReports },
                        set: { new in model.update { $0.sendsErrorReports = new } }
                    ))
                    Text(loc("When something fails, a description of it is sent to the author. Paths, addresses and anything token-shaped are removed first."))
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Section {
                    Button(loc("Forget all accounts…"), role: .destructive) {
                        confirmForgetAll = true
                    }
                    Text(loc("Removes only the token copies this app keeps. Your Claude Code sign-in is untouched."))
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .formStyle(.grouped)
            .alignedWithTheHeading()
        }
        .confirmationDialog(
            loc("Forget all accounts?"), isPresented: $confirmForgetAll, titleVisibility: .visible
        ) {
            Button(loc("Forget all"), role: .destructive) {
                Task { await appModel.forgetAllAccounts() }
            }
            Button(loc("Cancel"), role: .cancel) {}
        } message: {
            Text(loc("Removes only the token copies this app keeps. Your Claude Code sign-in is untouched."))
        }
    }
}
