import Testing
import Foundation

/// Two rules, both out of one bug: a setting could be changed and the window
/// went on drawing the one before it.
///
/// The minimal window is where it was noticed — the toggle went on and the full
/// window stayed — but `Row layout`, `Order`, `Show snapshot age` and both
/// polling intervals had been arriving at the next launch for as long as they
/// had existed, and nobody had looked. The decision log has the entry; these
/// are the two shapes it broke in, held from both ends.
///
/// Neither can be caught by reading the settings screen, which was correct
/// throughout: the switch moved, the value was stored, and the store was right.
/// Only the path from there to the screen was broken, and a path is a thing a
/// scanner can see.
private func swiftSources(under directories: [String]) throws -> [(path: String, text: String)] {
    var found: [(String, String)] = []
    for directory in directories {
        let root = repositoryRootForSettings.appendingPathComponent(directory)
        guard let walker = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: nil
        ) else { continue }
        for case let url as URL in walker where url.pathExtension == "swift" {
            let text = try String(contentsOf: url, encoding: .utf8)
            found.append((directory + "/" + url.lastPathComponent, text))
        }
    }
    return found
}

private var repositoryRootForSettings: URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}

/// Lines with their comments removed: a rule about code should not fire on
/// prose that describes the mistake it forbids, and both of these are described
/// in prose a few lines from where they are enforced.
private func code(_ text: String) -> [String] {
    text.components(separatedBy: "\n").map { line in
        guard let comment = line.range(of: "//") else { return line }
        return String(line[line.startIndex..<comment.lowerBound])
    }
}

private func matches(_ pattern: String, in line: String) -> Bool {
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
    return regex.firstMatch(
        in: line, range: NSRange(line.startIndex..., in: line)
    ) != nil
}

/// A model that keeps a copy of the settings must say when it changes.
///
/// Three of them do keep one — the Mac's `AppModel` and `UpdateModel`, the
/// phone's `PhoneModel` — because the settings are owned by one object and
/// needed by several. A plain `var` on an `ObservableObject` announces nothing,
/// so a view drawn from that copy keeps drawing the value it was built with.
/// That is not a thing anybody notices while writing it: the assignment is
/// right there, and it plainly happens.
///
/// The widgets are not scanned. A widget is rebuilt from a timeline entry and
/// observes nothing, so it has nowhere for this mistake to live.
@Suite struct SettingsCopiesAnnounceThemselves {

    @Test func everyCopyOfTheSettingsIsPublished() throws {
        var offenders: [String] = []
        var seen = 0

        for (path, text) in try swiftSources(under: ["App", "iOS"]) {
            for line in code(text) {
                // `PreferencesModel` is a different type and must not match, so
                // the name may not run on into another word.
                guard matches(#"\bvar\s+\w+\s*:\s*Preferences(?![A-Za-z])"#, in: line) else { continue }
                seen += 1
                if !line.contains("@Published") {
                    offenders.append("\(path): \(line.trimmingCharacters(in: .whitespaces))")
                }
            }
        }

        #expect(seen >= 3, """
            only \(seen) settings copies found where there are three — \
            the scan is looking in the wrong place
            """)
        #expect(offenders.isEmpty, """
            a settings copy that announces nothing is a setting that does not \
            apply: \(offenders.sorted()) — mark it `@Published`
            """)
    }
}

/// A scene reads no value out of a model.
///
/// A `Scene`'s content is built when its window opens and not again: the `App`
/// observes nothing that publishes, so a value read there is frozen at the
/// moment of the build, and a modifier comparing it never sees it change. The
/// settings used to travel from `PreferencesModel` to `AppModel` through an
/// `.onChange` written exactly like that, and they travelled once.
///
/// Passing the objects themselves is what a scene is for, and stays allowed: a
/// view that receives an `ObservableObject` observes it properly. So the rule
/// is about reaching *through* one — `delegate.preferences.value` — rather than
/// about mentioning it. A call is allowed too: `model.start()` asks the model
/// to do something rather than reading a value that will go stale.
@Suite struct ASceneReadsNoValueOutOfAModel {

    @Test func noSceneReachesThroughAModel() throws {
        var offenders: [String] = []
        var scenes = 0

        for (path, text) in try swiftSources(under: ["App", "iOS"]) {
            guard let body = Self.sceneBody(of: text) else { continue }
            scenes += 1
            for line in body where matches(
                #"[A-Za-z_]\w*\.[A-Za-z_]\w*\.[A-Za-z_]\w*(?!\s*\()"#, in: line
            ) {
                offenders.append("\(path): \(line.trimmingCharacters(in: .whitespaces))")
            }
        }

        #expect(scenes == 2, """
            \(scenes) scenes found where there are two, the Mac's and the \
            phone's — the scan is looking in the wrong place
            """)
        #expect(offenders.isEmpty, """
            a scene reading a value out of a model: \(offenders.sorted()) — it \
            is read once and never again. Pass the object and let the view \
            observe it, or subscribe where the objects are owned
            """)
    }

    /// The scene body: from `some Scene` to the brace that closes it, which in
    /// both files is a `}` at four spaces. Matching braces properly would be a
    /// parser; if this ever stops finding two scenes the count above says so
    /// rather than the rule going quietly unenforced.
    private static func sceneBody(of text: String) -> [String]? {
        let lines = code(text)
        guard let start = lines.firstIndex(where: { $0.contains("some Scene") }) else { return nil }
        guard let end = lines[lines.index(after: start)...].firstIndex(where: {
            $0.trimmingCharacters(in: .whitespaces) == "}" && $0.hasPrefix("    }")
        }) else { return nil }
        return Array(lines[start...end])
    }
}

/// The widget hears about a setting change.
///
/// It is another process and carries its own copy of some of the settings, so
/// it learns of a change when the snapshot is rewritten and at no other time.
/// The snapshot used to be rewritten by a poll and by nothing else: the row
/// layout, and the language, reached the desktop up to five minutes after they
/// reached the window.
///
/// So every setting `publishToWidget` puts into the snapshot has to be one the
/// model watches for change. Add a fifth field and forget the comparison and
/// the widget goes on drawing the fourth one's world, with the switch moved,
/// the window right, and nothing on screen to say why.
@Suite struct TheWidgetHearsAboutASettingChange {

    @Test func everySettingTheSnapshotCarriesIsWatchedForChange() throws {
        let url = repositoryRootForSettings.appendingPathComponent("App/AppModel.swift")
        let lines = code(try String(contentsOf: url, encoding: .utf8))
        let whole = lines.joined(separator: "\n")

        let carried = Self.settingsRead(inBodyAfter: "func publishToWidget", of: lines)
        #expect(carried.count >= 4, """
            the snapshot is built from \(carried.count) settings where it is \
            built from four — the scan is looking in the wrong place
            """)

        let unwatched = carried.filter {
            !whole.contains("oldValue.\($0) != preferences.\($0)")
        }
        #expect(unwatched.isEmpty, """
            the widget carries \(unwatched.sorted()) and nothing notices when \
            it changes: the snapshot is rewritten on a poll, so the desktop \
            would keep the old value until the next one
            """)
    }

    /// The settings read inside one function's body. The body ends at the first
    /// closing brace in the function's own column, which is how every function
    /// in that file is written; if it ever stops finding four the count above
    /// says so rather than the rule passing on an empty list.
    private static func settingsRead(inBodyAfter marker: String, of lines: [String]) -> [String] {
        guard let start = lines.firstIndex(where: { $0.contains(marker) }) else { return [] }
        guard let end = lines[lines.index(after: start)...].firstIndex(where: {
            $0.hasPrefix("    }")
        }) else { return [] }

        let body = lines[start...end].joined(separator: "\n")
        guard let regex = try? NSRegularExpression(pattern: #"preferences\.(\w+)"#) else { return [] }
        let found = regex.matches(in: body, range: NSRange(body.startIndex..., in: body))
        return Array(Set(found.compactMap { match in
            Range(match.range(at: 1), in: body).map { String(body[$0]) }
        })).sorted()
    }
}

/// A number does not take the colour of a bar.
///
/// `Severity.tint` is yellow at `.warning`, and yellow is an excellent bar and
/// an unreadable four digits on a light background — the figure being the part
/// somebody is actually trying to read. `numberTint` is the one for text: plain
/// through `.warning`, orange and red from `.hot` up, where both are legible
/// either side of the theme.
///
/// The rule is written against `foregroundStyle`, which is what colours text and
/// symbols; `fill` and `stroke` colour shapes and keep all four levels. An
/// explicit `Severity.hot.tint` stays allowed and is used in seven places for a
/// warning sentence: it is orange by name rather than by a percentage, and
/// orange reads.
@Suite struct ANumberDoesNotTakeTheColourOfABar {

    @Test func noTextIsColouredByTheBarTint() throws {
        var offenders: [String] = []
        var painted = 0

        for (path, text) in try swiftSources(
            under: ["App", "iOS", "Widget", "iOSWidget", "Packages/Core/Sources/StatusUI"]
        ) {
            for line in code(text) where line.contains("foregroundStyle(") {
                painted += 1
                if line.contains(".severity.tint") || line.contains("Severity(percent:") {
                    offenders.append("\(path): \(line.trimmingCharacters(in: .whitespaces))")
                }
            }
        }

        #expect(painted >= 20, """
            only \(painted) coloured labels found — the scan is looking in the \
            wrong place
            """)
        #expect(offenders.isEmpty, """
            a number wearing the bar's colour: \(offenders.sorted()) — yellow \
            is unreadable as text. Use `numberTint`
            """)
    }
}

/// Words are never fainter than `.secondary`.
///
/// SwiftUI's hierarchy runs primary, secondary, tertiary, quaternary, and the
/// last two are around 40% and 20% of the text colour. Over the window's
/// translucent material that lands near 3:1 against the background — under the
/// 4.5:1 that small text needs to be read, and it was the whole minimal window
/// at first: the service, the countdown, the date a reading was taken and the
/// three symbols in the footer were all drawn at a level meant for something
/// else.
///
/// The rule the levels now carry: `.primary` for the name and the figure, which
/// are what somebody opens the window to read; `.secondary` for every other
/// word; `.tertiary` and below for shapes only — a bar's empty track is not
/// read, it is seen.
///
/// It cannot measure contrast, which depends on a material this cannot see.
/// It can refuse the level that was measurably too faint on the one background
/// that matters, which is the mistake that was made.
@Suite struct WordsAreNeverFainterThanSecondary {

    @Test func nothingIsPaintedBelowSecondary() throws {
        var offenders: [String] = []
        var painted = 0

        for (path, text) in try swiftSources(
            under: ["App", "iOS", "Widget", "iOSWidget", "Packages/Core/Sources/StatusUI"]
        ) {
            for line in code(text) where line.contains("foregroundStyle(") {
                painted += 1
                if line.contains("foregroundStyle(.tertiary)")
                    || line.contains("foregroundStyle(.quaternary)") {
                    offenders.append("\(path): \(line.trimmingCharacters(in: .whitespaces))")
                }
            }
        }

        #expect(painted >= 20, """
            only \(painted) coloured labels found — the scan is looking in the \
            wrong place
            """)
        #expect(offenders.isEmpty, """
            words too faint to read over the window's material: \
            \(offenders.sorted()) — `.secondary` is the floor for anything \
            made of letters
            """)
    }
}
