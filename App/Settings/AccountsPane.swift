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
             subtitle: loc("Add Claude Code or OpenAI Codex accounts through your browser.")) {
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
                            if row.state == .needsLogin {
                                Button(loc("Sign in…")) {
                                    loginController.start(
                                        provider: row.provider, from: .settings, for: row.id)
                                }
                                .disabled(loginController.isRunning)
                            }
                            Button(loc("Forget…")) { pendingForget = row }
                        }
                        Divider()
                    }
                }

                HStack(spacing: 8) {
                    Menu(loc("Add account…")) {
                        ForEach(LoginController.providers, id: \.self) { provider in
                            Button(provider == .claude ? "Claude Code" : "OpenAI Codex") {
                                manualCode = ""
                                loginController.start(provider: provider, from: .settings)
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

                // Only for a sign-in this screen started. The limits window
                // has a field of its own now, gated the same way from the other
                // side: without both halves, a sign-in begun in that window and
                // sent back for a pasted code would put two fields on two
                // screens, bound to two different strings, each offering to
                // spend the one grant.
                if loginController.manualCodeExpected,
                   loginController.request?.origin == .settings {
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

                if let message = loginController.message {
                    Text(message)
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }

                if let accountError {
                    Text(accountError).font(.system(size: 11)).foregroundStyle(.red)
                }

                Text(loc("Every account holds its own credential and refreshes on its own."))
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
                message: Text(loc("Saved credentials will be deleted. Nothing you signed into elsewhere is affected.")),
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
        case .refreshed:   loc("refreshed")
        case .needsLogin:  loc("sign-in needed")
        }
    }

    private func caption(for row: AccountRow) -> String {
        switch row.state {
        case .refreshed:   String(format: loc("%@ · saved account"), row.provider.title)
        case .needsLogin:  String(format: loc("%@ · sign-in required"), row.provider.title)
        }
    }

    private func tint(for state: CredentialStore.AccountState) -> Color {
        switch state {
        case .refreshed:   .blue
        case .needsLogin:  .red
        }
    }
}
