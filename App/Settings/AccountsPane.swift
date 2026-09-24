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
    @State private var repairing = false
    @State private var repairNote: String?
    @State private var confirmingStartOver = false
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
                demoControl
                Divider().opacity(0.4)

                // Before the list, because when this is on screen the list is
                // empty and the emptiness is the thing being explained. It said
                // "No accounts yet" to somebody whose accounts were all still
                // there, and offered them a sign-in that could not be saved.
                if let problem {
                    VStack(alignment: .leading, spacing: 6) {
                        // This screen's own heading rather than the one the
                        // limits window draws. That window has a lock above it
                        // and a column with nothing else in it; here the
                        // sentence sits under a pane title, and "Your accounts
                        // are still here" arriving with no visible claim to
                        // correct reads as an answer to a question nobody
                        // asked.
                        Text(loc("Saved accounts could not be opened"))
                            .font(.system(size: 12.5, weight: .medium))
                        Text(problem.explanation)
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 8) {
                            // Offered for both refusals. An unlock is a question
                            // too, and the same press puts it on screen — only
                            // an item that opened and made no sense has nobody
                            // left to ask.
                            if problem.mayBeOpened {
                                Button(loc("Open saved accounts")) { Task { await open() } }
                                    .disabled(repairing)
                            }
                            Button(loc("Start over…")) { confirmingStartOver = true }
                                .disabled(repairing)
                            if repairing { ProgressView().controlSize(.small) }
                        }
                        if let repairNote {
                            Text(repairNote).font(.system(size: 11)).foregroundStyle(.red)
                        }
                    }
                    Divider().opacity(0.4)
                }

                // Not while the block above is explaining why the list is
                // empty: the two together read "Saved accounts could not be
                // opened / No accounts yet", and the second sentence is the
                // lie the first one exists to correct.
                if rows.isEmpty, problem == nil {
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
                    // Nothing can be saved while the list will not open, and a
                    // browser sign-in that ends in "there was nowhere to put
                    // it" spends a grant to tell somebody what this screen is
                    // already telling them.
                    .disabled(loginController.isRunning || problem != nil)
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
        // Asked for, and asked about. It deletes the only copy of every refresh
        // token in the item, and the sentence says what that means in the terms
        // the person is standing in rather than in the terms the keychain uses.
        .alert(loc("Start over?"), isPresented: $confirmingStartOver) {
            Button(loc("Start over"), role: .destructive) { Task { await startOver() } }
            Button(loc("Cancel"), role: .cancel) {}
        } message: {
            Text(loc("The saved accounts will be removed and each one signed in again. Nothing you signed into elsewhere is affected."))
        }
    }

    /// Why the saved list could not be read, when it could not be read.
    ///
    /// Derived from the model rather than kept here. It used to be `@State`,
    /// reloaded from three separate `onChange` hooks — which was one fact held
    /// in two places while this pane was the only place it could be read. The
    /// limits window reads it too now, and three copies of a fact are three
    /// chances for two screens to disagree about what the keychain said.
    private var problem: SavedAccountsProblem? {
        appModel.savedAccountsProblem.map { SavedAccountsProblem($0, loc) }
    }

    private func reload() async {
        rows = await appModel.accountRows()
        await appModel.refreshSavedAccountsProblem()
    }

    private func open() async { await repair { try await appModel.openSavedAccounts() } }

    private func startOver() async { await repair { try await appModel.startAccountsOver() } }

    /// Runs one repair and reports it honestly.
    ///
    /// The note is spoken only when the reason is the same afterwards as it was
    /// before. A refused attempt that nonetheless moved — the item opened, and
    /// what came out could not be understood — changes the sentence above it,
    /// and "nothing was changed" beside a changed explanation would be the one
    /// untrue line on the screen.
    private func repair(_ work: () async throws -> Void) async {
        repairing = true
        repairNote = nil
        let before = appModel.savedAccountsProblem
        var failed = false
        do {
            try await work()
        } catch {
            failed = true
        }
        repairing = false
        await reload()
        if failed, appModel.savedAccountsProblem == before {
            repairNote = loc("That did not work, and nothing was changed.")
        }
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

    /// The switch that puts sample accounts on screen, and the sentence saying
    /// that is what is on screen now.
    ///
    /// Always present, not only while demo is on: the mode exists so that
    /// somebody without a subscription can see what the app does, and a way in
    /// that disappears once you have left is not a way in. It is also what App
    /// Review is pointed at.
    private var demoControl: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(loc("Show sample data"), isOn: Binding(
                get: { appModel.isDemo },
                set: { on in model.update { $0.demoMode = on } }
            ))
            .font(.system(size: 12.5))
            if appModel.isDemo {
                Text(loc("These accounts are examples. Add one of your own to see real limits."))
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
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
