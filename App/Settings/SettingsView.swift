import SwiftUI
import Preferences
import StatusUI

struct SettingsView: View {
    @ObservedObject var model: PreferencesModel
    @ObservedObject var appModel: AppModel
    @ObservedObject var updates: UpdateModel

    @ObservedObject private var loc = Localization.shared

    var body: some View {
        // Built from an `HStack` rather than `NavigationSplitView`: inside a
        // `Settings` scene the latter renders an empty window — no list, no
        // content. Verified through the accessibility element tree.
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                sidebar
                Divider()
                detail
            }
            Divider().opacity(0.5)
            footer
        }
        .frame(width: 720, height: 470)
        // The chosen language decides how a date and a time are written, not
        // only which words are used. Left alone, SwiftUI formats them in the
        // system's language while every label around them follows the setting —
        // so the badge said `28 Aug` in one language and the clock beside it
        // read in another.
        .environment(\.locale, loc.activeLocale)
        .environment(\.layoutDirection, loc.layoutDirection ?? .leftToRight)
        .id(loc.language)
        .task { await model.load() }
    }

    /// The App Store build has no Updates screen: those builds are updated by
    /// TestFlight and the store, not by the app.
    private var visibleSections: [SettingsSection] {
        #if APPSTORE
        SettingsSection.allCases.filter { $0 != .updates }
        #else
        SettingsSection.allCases
        #endif
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 1) {
            ForEach(visibleSections) { section in
                Button {
                    appModel.settingsSection = section
                } label: {
                    HStack(spacing: 8) {
                        SettingsIcon(section)
                            .foregroundStyle(appModel.settingsSection == section ? .white : .secondary)
                        Text(loc(section.titleKey))
                            .font(.system(size: 12.5))
                            .foregroundStyle(appModel.settingsSection == section ? .white : .primary)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(appModel.settingsSection == section ? Color.accentColor : .clear)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .frame(width: 186)
        .background(.quaternary.opacity(0.35))
    }

    /// Quiet, right aligned, and on every screen — which is what makes it the
    /// place people find this, rather than the sidebar entry beside seven
    /// others. It says which version this is whether or not there is a newer
    /// one, because that is the question asked more often.
    private var footer: some View {
        HStack(spacing: 6) {
            Spacer()
            #if !APPSTORE
            Button(footerTitle) { appModel.settingsSection = .updates }
                .buttonStyle(.plain)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
            Text(verbatim: "·").font(.system(size: 11.5)).foregroundStyle(.secondary)
            #endif
            Text(updates.versionText)
                .font(.system(size: 11.5))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    private var footerTitle: String {
        guard let newer = updates.availableVersion else { return loc("Check for updates") }
        return String(format: loc("Update to %@"), newer.description)
    }

    private var detail: some View {
        ScrollView {
            Group {
                switch appModel.settingsSection {
                case .accounts:      AccountsPane(model: model, appModel: appModel)
                case .statistics:    StatisticsPane(model: model, appModel: appModel)
                case .appearance:    AppearancePane(model: model, appModel: appModel)
                case .notifications: NotificationsPane(model: model, appModel: appModel)
                case .polling:       PollingPane(model: model)
                case .updates:       UpdatesPane(updates: updates, model: model)
                case .services:      ServicesPane(model: model)
                case .about:         AboutPane(model: model, appModel: appModel)
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(20)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if appModel.settingsSection == .accounts {
                SignInSuccessBanner(login: appModel.login)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// A shared section wrapper: title, explanation and content.
/// Extracted so the eight screens do not drift apart in padding and sizing.
struct Pane<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(.system(size: 15, weight: .semibold))
            Text(subtitle)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .padding(.top, 3).padding(.bottom, 16)
            content
            Spacer(minLength: 0)
        }
    }
}

extension View {
    /// Cancels the inset a grouped `Form` adds to its own rows.
    ///
    /// Six of the eight screens are built from a `Form`; the other two are not,
    /// and their content lines up with the screen's heading because the detail
    /// area's padding is the only thing between them. The six did not: the
    /// `Form` added twenty points of its own, so every box sat indented from the
    /// title above it while Accounts and Statistics did not. Nobody notices one
    /// screen at a time, and it is obvious the moment two are compared.
    ///
    /// Cancelling rather than moving the heading across: the content is what the
    /// screen is, and the wider boxes are the ones the window has room for.
    func alignedWithTheHeading() -> some View {
        padding(.horizontal, -groupedFormInset)
    }
}

/// What a grouped `Form` insets its rows by on macOS, on top of whatever padding
/// it is given.
///
/// Measured rather than assumed: on a screenshot of the Notifications screen the
/// heading sat 207.5 pt from the window's edge and the first row's box at
/// 227.5 pt. A number guessed here would misalign every screen by the amount it
/// was wrong, in the direction nobody would think to look.
private let groupedFormInset: CGFloat = 20
