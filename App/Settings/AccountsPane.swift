import SwiftUI
import ProviderKit
import Credentials
import Preferences
import StatusUI

struct AccountsPane: View {
    @ObservedObject var model: PreferencesModel
    @ObservedObject var appModel: AppModel

    @ObservedObject private var loginController: LoginController
    @State private var rows: [AccountRow] = []
    @State private var pendingForget: AccountRow?
    @State private var manualCode = ""
    @State private var accountError: String?
    @ObservedObject private var loc = Localization.shared

    init(model: PreferencesModel, appModel: AppModel) {
        self.model = model
        self.appModel = appModel
        _loginController = ObservedObject(wrappedValue: appModel.login)
    }

    struct AccountRow: Identifiable, Hashable {
        let id: String
        let handle: String
        let provider: ProviderID
        let displayName: String
        let state: CredentialStore.AccountState
    }

    var body: some View {
        Pane(title: loc("Accounts"),
             subtitle: loc("Add Claude Code or OpenAI Codex accounts through your browser. Local CLI accounts are also detected.")) {
            VStack(alignment: .leading, spacing: 10) {
                if rows.isEmpty {
                    Text(loc("No accounts yet"))
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                } else {
                    ForEach(rows) { row in
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(row.displayName)
                                    .font(.system(size: 12.5, weight: .medium))
                                Text(caption(for: row))
                                    .font(.system(size: 11)).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(badge(for: row.state))
                                .font(.system(size: 10, weight: .semibold))
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(tint(for: row.state).opacity(0.16),
                                            in: RoundedRectangle(cornerRadius: 4))
                                .foregroundStyle(tint(for: row.state))
                            Toggle("", isOn: visible(row)).labelsHidden()
                                .accessibilityLabel(String(format: loc("Show %@"), row.displayName))
                            if row.state == .needsLogin || row.state == .localSession {
                                Button(loc("Sign in…")) { loginController.start(provider: row.provider) }
                                    .disabled(loginController.isRunning)
                            }
                            if row.state != .localSession {
                                Button(loc("Forget…")) { pendingForget = row }
                            }
                        }
                        Divider()
                    }
                }

                HStack(spacing: 8) {
                    Menu(loc("Add account…")) {
                        ForEach(LoginController.providers, id: \.self) { provider in
                            Button(provider == .claude ? "Claude Code" : "OpenAI Codex") {
                                manualCode = ""
                                loginController.start(provider: provider)
                            }
                        }
                    }
                    .fixedSize()
                    .disabled(loginController.isRunning)
                    if loginController.isRunning {
                        ProgressView().controlSize(.small)
                        if loginController.isSavingAccount {
                            Text(loc("Saving account…"))
                                .font(.system(size: 11)).foregroundStyle(.secondary)
                        } else if let provider = loginController.provider {
                            Text(String(format: loc("Signing in to %@…"), provider.title))
                                .font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                        Button(loc("Cancel")) { loginController.cancel() }
                            .disabled(loginController.isSavingAccount)
                    }
                    Spacer()
                }

                if loginController.manualCodeExpected {
                    HStack(spacing: 6) {
                        TextField(loc("Code from the page"), text: $manualCode)
                            .frame(width: 220)
                        Button(loc("Done")) {
                            Task {
                                await loginController.submit(code: manualCode)
                                manualCode = ""
                                await reload()
                            }
                        }
                        .disabled(manualCode.isEmpty)
                    }
                }

                // The subtitle above promises that accounts signed into with
                // `/login` turn up on their own. They do not when the keychain
                // refuses to be read, and until now nothing said so — the list
                // simply stayed short.
                if appModel.cliAccessBlocked {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(loc("Claude Code's credentials cannot be read, so the account signed in there cannot be shown."))
                            .font(.system(size: 11))
                            .foregroundStyle(Severity.hot.tint)
                            .fixedSize(horizontal: false, vertical: true)

                        // The instruction used to be a sentence telling the reader
                        // to go and press Refresh in another window. The button is
                        // the same act, next to the problem it solves: a poll is
                        // not allowed to raise the keychain dialog, and this is a
                        // person asking for it, which is exactly when it should
                        // appear.
                        Button(loc("Allow access…")) {
                            Task { await appModel.refresh(.allowingAccess); await reload() }
                        }
                        .disabled(appModel.isRefreshing)
                    }
                }

                if let message = loginController.message {
                    Text(message)
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }

                if let accountError {
                    Text(accountError).font(.system(size: 11)).foregroundStyle(.red)
                }

                Text(loc("Browser accounts refresh independently. Local Codex accounts show readings from session files. Your CLI sign-ins are not changed."))
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .task { await reload() }
        .onChange(of: loginController.message) { _, _ in Task { await reload() } }
        .onChange(of: loginController.completedSignIns) { _, _ in
            Task { await reload() }
        }
        .onChange(of: appModel.lastUpdated) { _, _ in Task { await reload() } }
        .alert(item: $pendingForget) { row in
            Alert(
                title: Text(String(format: loc("Forget %@?"), row.displayName)),
                message: Text(loc("Saved credentials will be deleted. Your CLI sign-ins will not change.")),
                primaryButton: .destructive(Text(loc("Forget"))) {
                    Task { await forget(row) }
                },
                secondaryButton: .cancel(Text(loc("Cancel")))
            )
        }
    }

    private func reload() async {
        rows = await appModel.accountRows()
    }

    private func forget(_ row: AccountRow) async {
        do {
            try await appModel.forgetAccount(id: row.id)
            accountError = nil
        } catch {
            accountError = loc("Could not forget the account. Try again.")
        }
        await reload()
    }

    private func visible(_ row: AccountRow) -> Binding<Bool> {
        Binding(
            get: { !model.value.hiddenAccounts.contains(row.id) },
            set: { on in
                model.update {
                    if on { $0.hiddenAccounts.remove(row.id) }
                    else { $0.hiddenAccounts.insert(row.id) }
                }
            }
        )
    }

    private func badge(for state: CredentialStore.AccountState) -> String {
        switch state {
        case .activeInCLI: loc("active in CLI")
        case .refreshed:   loc("refreshed")
        case .needsLogin:  loc("sign-in needed")
        case .localSession: loc("local session")
        }
    }

    private func caption(for row: AccountRow) -> String {
        switch row.state {
        case .activeInCLI: loc("Claude · token read from Claude Code")
        case .refreshed:   String(format: loc("%@ · saved account"), row.provider.title)
        case .needsLogin:  String(format: loc("%@ · sign-in required"), row.provider.title)
        case .localSession: loc("Codex · local session files")
        }
    }

    private func tint(for state: CredentialStore.AccountState) -> Color {
        switch state {
        case .activeInCLI: .green
        case .refreshed:   .blue
        case .needsLogin:  .red
        case .localSession: .secondary
        }
    }
}
