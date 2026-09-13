import SwiftUI
import StatusUI

enum SettingsSection: String, CaseIterable, Identifiable {
    case accounts, statistics, appearance, notifications, polling, updates, services,
         contribute, about

    var id: String { rawValue }

    /// A translation key. The label itself comes from the catalogue — a section
    /// holds no ready text, otherwise the list would not follow the language.
    var titleKey: String {
        switch self {
        case .accounts:      "Accounts"
        case .statistics:    "Statistics"
        case .appearance:    "Appearance"
        case .notifications: "Notifications"
        case .polling:       "Polling and launch"
        case .updates:       "Updates"
        case .services:      "Services"
        case .contribute:    "Contribute"
        case .about:         "About"
        }
    }

    /// Stroked symbols, not coloured plates: colour already encodes load in the
    /// limits window, and a second colour language weakens both.
    var symbol: String {
        switch self {
        case .accounts:      "person.2"
        case .statistics:    "chart.xyaxis.line"
        case .appearance:    "circle.lefthalf.filled"
        case .notifications: "bell"
        // An arrow going round is what polling looks like; an arrow coming
        // down is what an update is. The old screen held the first symbol
        // under the second name.
        case .polling:       "arrow.clockwise"
        case .updates:       "arrow.down.circle"
        case .services:      "square.grid.2x2"
        // Not a heart: the page asks for work, not for affection.
        case .contribute:    "chevron.left.forwardslash.chevron.right"
        case .about:         "info.circle"
        }
    }
}

struct SettingsIcon: View {
    let section: SettingsSection

    init(_ section: SettingsSection) { self.section = section }

    var body: some View {
        Image(systemName: section.symbol)
            .font(.system(size: 13, weight: .regular))
            .frame(width: 18, height: 18)
    }
}
