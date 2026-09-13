import SwiftUI
import ProviderKit
import Monitoring
import StatusUI

struct AccountOrderEditor: View {
    @ObservedObject var model: PreferencesModel
    @ObservedObject var appModel: AppModel
    @ObservedObject private var loc = Localization.shared
    @Environment(\.dismiss) private var dismiss
    @State private var selectedAccountID: String?

    private var accounts: [AccountSnapshot] {
        orderedForDisplay(
            appModel.snapshots, ordering: .custom,
            customAccountOrder: model.value.customAccountOrder
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(loc("Custom order"))
                    .font(.system(size: 15, weight: .semibold))
                Text(loc("Drag accounts to change their order."))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if accounts.isEmpty {
                Text(loc("No accounts found"))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 100)
            } else {
                List(selection: $selectedAccountID) {
                    ForEach(accounts) { account in
                        row(account)
                            .tag(account.id)
                    }
                    .onMove(perform: moveAccounts)
                }
                .listStyle(.inset)
                .frame(height: min(280, CGFloat(accounts.count) * 48 + 24))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(.quaternary, lineWidth: 1)
                }
            }

            HStack {
                Spacer()
                Button(loc("Done")) { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 380)
        .onExitCommand { dismiss() }
    }

    private func row(_ account: AccountSnapshot) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(account.displayName)
                    .font(.system(size: 12.5, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(account.provider.title)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
        .frame(height: 40)
        .contentShape(Rectangle())
        .help(account.displayName)
        .contextMenu {
            Button(loc("Move up")) { move(account, by: -1) }
                .disabled(accounts.first?.id == account.id)
            Button(loc("Move down")) { move(account, by: 1) }
                .disabled(accounts.last?.id == account.id)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: Text(loc("Move up"))) { move(account, by: -1) }
        .accessibilityAction(named: Text(loc("Move down"))) { move(account, by: 1) }
    }

    private func moveAccounts(from source: IndexSet, to destination: Int) {
        var ids = accounts.map(\.id)
        ids.move(fromOffsets: source, toOffset: destination)
        model.update { $0.setCustomAccountOrder(ids) }
    }

    private func move(_ account: AccountSnapshot, by offset: Int) {
        let rows = accounts
        guard let index = rows.firstIndex(where: { $0.id == account.id }),
              rows.indices.contains(index + offset) else { return }
        moveAccounts(from: IndexSet(integer: index), to: index + (offset > 0 ? 2 : -1))
    }
}
