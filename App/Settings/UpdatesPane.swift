import SwiftUI
import AppKit
import ProviderKit
import Preferences
import StatusUI
import Updates

/// Everything an update does, on one screen.
///
/// There is no sheet and no second window. A menu bar app that opens a window
/// to tell you something is one that interrupts, and this one was built not to.
/// It also means closing the window part-way through an install cannot cancel
/// it: the work belongs to `UpdateModel`, which outlives this view.
struct UpdatesPane: View {
    @ObservedObject var updates: UpdateModel
    @ObservedObject var model: PreferencesModel

    @ObservedObject private var loc = Localization.shared

    var body: some View {
        Pane(title: loc("Updates"),
             subtitle: loc("Where new versions come from, and when to look for one.")) {
            Form {
                Section {
                    LabeledContent(loc("Version"), value: updates.versionText)
                    LabeledContent(loc("Last checked"), value: lastChecked)
                }

                Section { state }

                Section {
                    Toggle(loc("Check automatically"), isOn: Binding(
                        get: { model.value.checksForUpdates },
                        set: { new in model.update { $0.checksForUpdates = new } }
                    ))
                    Text(loc("Once a day, and never without saying so here first."))
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .formStyle(.grouped)
            .alignedWithTheHeading()
        }
    }

    // MARK: - the one section that changes

    @ViewBuilder
    private var state: some View {
        switch updates.state {
        case .idle:
            HStack {
                // Only a check that finished records its moment, so the absence
                // of one is exactly the case where nothing can be claimed. This
                // said "No new version has been found." either way, and an
                // offline launch put that sentence directly above "Last checked:
                // never" — an answer above a row saying nobody asked.
                Text(updates.lastChecked == nil
                     ? loc("Not checked yet.")
                     : loc("No new version has been found."))
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                Spacer()
                checkButton
            }

        case .upToDate:
            HStack {
                Text(loc("This is the latest version."))
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                Spacer()
                checkButton
            }

        case .checking:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(loc("Checking…")).font(.system(size: 12)).foregroundStyle(.secondary)
            }

        case .available(let release):
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(String(format: loc("Version %@ is available."),
                                release.version.description))
                        .font(.system(size: 12.5, weight: .medium))
                    Spacer()
                    Button(String(format: loc("Update to %@"), release.version.description)) {
                        Task { await updates.install() }
                    }
                    .keyboardShortcut(.defaultAction)
                }
                if !release.notes.isEmpty { notes(release.notes) }
            }

        case .installing(let phase):
            VStack(alignment: .leading, spacing: 8) {
                Text(title(for: phase)).font(.system(size: 12))
                progress(for: phase)
                Text(loc("The app will restart on its own when this finishes."))
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

        case .failed(let failure):
            VStack(alignment: .leading, spacing: 8) {
                Text(sentence(for: failure.kind))
                    .font(.system(size: 12))
                    .foregroundStyle(Severity.hot.tint)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    checkButton
                    // A way out that does not depend on the updater working.
                    Button(loc("Open the release page")) {
                        NSWorkspace.shared.open(updates.pageToOpen)
                    }
                }
            }
        }
    }

    private var checkButton: some View {
        Button(loc("Check for updates")) {
            Task { await updates.check(now: Date()) }
        }
    }

    /// The release body as its author wrote it. Markdown, and text that came
    /// over the network.
    ///
    /// Rendered as text and nothing else — but that took work.
    /// `.inlineOnlyPreservingWhitespace` drops block elements and keeps inline
    /// ones, links included, and `Text` renders a link run as a control that
    /// routes through `openURL`. A release note is the one place remote text
    /// becomes interface, so the links are stripped rather than trusted, and
    /// what is left is the words they were written on.
    private func notes(_ body: String) -> some View {
        ScrollView {
            Text(attributed(body))
                .font(.system(size: 11.5))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: 150)
    }

    private func attributed(_ body: String) -> AttributedString {
        guard var text = try? AttributedString(
            markdown: body,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) else { return AttributedString(body) }

        for run in text.runs where run.link != nil {
            text[run.range].link = nil
        }
        return text
    }

    @ViewBuilder
    private func progress(for phase: UpdateInstaller.Phase) -> some View {
        if case .downloading(let fraction) = phase {
            ProgressView(value: fraction)
        } else {
            ProgressView().progressViewStyle(.linear)
        }
    }

    private func title(for phase: UpdateInstaller.Phase) -> String {
        switch phase {
        case .downloading: loc("Downloading…")
        case .verifying:   loc("Checking what arrived…")
        case .installing:  loc("Installing…")
        }
    }

    /// The interface builds the sentence; the model carries the identifier.
    private func sentence(for kind: UpdateFailure.Kind) -> String {
        switch kind {
        case .network:
            loc("GitHub could not be reached. Check the connection and try again.")
        case .malformedRelease:
            loc("The newest release has no build to download.")
        case .checksumMismatch:
            loc("What arrived is not what the release published, so it was discarded.")
        case .signatureChanged:
            loc("The download is signed by somebody else, so it was discarded.")
        case .notWritable:
            loc("Softcap could not be replaced where it is installed. Move it to Applications, or download it yourself.")
        case .unpackFailed:
            loc("The download could not be opened.")
        }
    }

    /// The moment, written in the chosen language.
    ///
    /// `formatted(date:time:)` builds the string here rather than letting
    /// SwiftUI build it, so `\.locale` from the environment never reaches it and
    /// it used `Locale.autoupdatingCurrent` instead. That is the bug
    /// `SettingsView` carries a comment about — "the badge said `28 Aug` in one
    /// language and the clock beside it read in another" — reintroduced three
    /// rows below the label that fixed it. The locale is named outright.
    private var lastChecked: String {
        guard let moment = updates.lastChecked else { return loc("never") }
        return moment.formatted(
            Date.FormatStyle(date: .abbreviated, time: .shortened, locale: loc.activeLocale))
    }
}
