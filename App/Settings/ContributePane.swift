import SwiftUI
import AppKit
import StatusUI

/// Where the app comes from, and how somebody can change it.
///
/// It holds no settings, which is why it is a screen rather than a section of
/// About: that one answers "what does this app keep, and where", and this one
/// answers "whose is it, and can I help". Mixing the two would bury the second
/// question under the first.
struct ContributePane: View {
    @ObservedObject private var loc = Localization.shared

    var body: some View {
        Pane(title: loc("Contribute"),
             subtitle: loc("The source is public. Read it, report what is wrong, or send a change.")) {
            Form {
                Section {
                    LabeledContent(loc("Repository"), value: Repository.label)
                    Button(loc("Open the repository")) {
                        NSWorkspace.shared.open(Repository.page)
                    }
                    Button(loc("Report a problem")) {
                        NSWorkspace.shared.open(Repository.issues)
                    }
                }

                Section {
                    Text(loc("If you write code: fork the repository, make your change, and open a pull request. The README explains how to build the app and how to run its tests."))
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(loc("Translations matter as much as code. Every language has a catalogue of its own, and a correction to any of them is worth sending."))
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .formStyle(.grouped)
            .alignedWithTheHeading()
        }
    }
}
