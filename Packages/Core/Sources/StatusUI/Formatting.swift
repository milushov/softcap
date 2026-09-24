import Foundation
import SwiftUI
import ProviderKit
import Preferences
import Monitoring

/// Labels the models deliberately do not hold: they depend on the language.
public extension Localization {

    /// The locale matching the chosen language, for the system formatters.
    ///
    /// The app's language is not necessarily the system's — it is chosen in
    /// settings — so a formatter left on `Locale.current` would spell dates and
    /// units in the wrong language while every other label followed the choice.
    var activeLocale: Locale {
        language == .system ? .current : Locale(identifier: language.rawValue)
    }

    /// A limit window's name, by its identifier.
    func windowTitle(_ id: String) -> String {
        switch id {
        case "session": self("5h")
        case "weekly":  self("week")
        // A third period, and named like the other two rather than after the
        // kind of allowance it counts. The column these sit in is one width
        // shared by every row on screen, so a long word here widens rows
        // belonging to services that will never show it.
        case "premium": self("month")
        default:        id
        }
    }

    /// The settings window's own title: `Softcap Settings`, `Настройки Softcap`.
    ///
    /// macOS writes this title itself, in the *system's* language — so a Russian
    /// interface opened on an English Mac was headed `Softcap Settings` while
    /// every label under it read Russian. The app chooses its language, so it
    /// spells its own title. The name is a placeholder because the languages
    /// put it in different places, and it is a brand rather than a word: it is
    /// not translated.
    func settingsWindowTitle(_ app: String) -> String {
        String(format: self("%@ Settings"), app)
    }

    /// The day a chart's axis is labelled with: `14 Sep`, `14 сент.`, `١٤ سبتمبر`.
    ///
    /// The locale is named here rather than left to the environment because
    /// Swift Charts does not read the environment for it. `SettingsView` sets
    /// `\.locale` for everything inside it and the axis ignored it, spelling
    /// its days in the system's language under all ten interfaces —
    /// `DatesFollowTheChosenLanguage` holds it.
    var chartDay: Date.FormatStyle {
        .dateTime.day().month(.abbreviated).locale(activeLocale)
    }

    /// A percentage spelled the way the language spells it.
    ///
    /// Not `"\(n)%"`: Russian, French and Spanish put a non-breaking space
    /// before the sign, and Arabic wraps it in directional marks so it does not
    /// drift when the line runs right to left. Written by hand, four of the ten
    /// languages come out wrong — and the app already disagreed with itself,
    /// showing "80%" in a row and "80 %" in settings.
    func percent(_ value: Double) -> String {
        Int(value.rounded()).formatted(.percent.locale(activeLocale))
    }

    /// The remaining time in words: "3 h 39 m", "5 d 23 h", "47 m".
    /// Units come from the catalogue, so order and abbreviations change with the
    /// language.
    func remaining(_ interval: TimeInterval?) -> String {
        guard let interval, let time = RemainingTime(interval) else { return "—" }
        let units = time.significantUnits
        let major = unit(units.major)
        guard let minor = units.minor.map(unit) else { return major }
        return "\(major) \(minor)"
    }

    /// The short form for the menu bar: "0:47", "3:39", "5d".
    func remainingCompact(_ interval: TimeInterval?) -> String {
        guard let interval, let time = RemainingTime(interval) else { return "—" }
        guard time.days == 0 else { return unit(.days(time.days)) }
        return String(format: "%d:%02d", time.hours, time.minutes)
    }

    /// Error text is built from the failure kind, not the diagnostic: the latter
    /// is written for the log and may carry a status code or a path.
    func failureText(_ kind: ProviderFailure.Kind) -> String {
        switch kind {
        case .needsLogin:      self("Sign-in required")
        case .network:         self("Network unavailable")
        case .noData:          self("No data available")
        case .malformed:       self("Unexpected response")
        }
    }

    /// The words a threshold event turns into.
    ///
    /// The window is part of the sentence, not an optional detail. Both limits
    /// can cross the same number on the same evening — the weekly did, and the
    /// five-hour followed within the hour — and without the window's name the
    /// two notifications read identically, which a reader can only take as the
    /// app repeating itself. Whole sentences per window rather than a name
    /// slotted into one template: half the languages decline or reorder the
    /// window's name, and a catalogue can only do that when it owns the whole
    /// line.
    ///
    /// An unfamiliar window id falls back to the old unnamed wording — the
    /// same stance the providers take on window kinds they do not know.
    func notificationTitle(for event: ThresholdEvent) -> String {
        switch event.kind {
        case .crossed(let level):
            let template = switch event.windowID {
            case "session": self("%1$@: %2$@ of the 5-hour limit")
            case "weekly":  self("%1$@: %2$@ of the weekly limit")
            case "premium": self("%1$@: %2$@ of the monthly limit")
            default:        self("%1$@: %2$@ of limit")
            }
            return String(format: template, event.accountName, percent(Double(level)))
        case .recovered:
            return String(format: self("%@ is free again"), event.accountName)
        }
    }

    func notificationBody(for event: ThresholdEvent) -> String {
        switch event.kind {
        case .crossed(let level):
            // The remainder, worked out rather than assumed: "less than a
            // fifth left" was once written out, true of the default 80 and of
            // no other threshold a reader might set.
            return level >= 95
                ? self("Almost exhausted — time to switch.")
                : String(format: self("About %@ left."), percent(Double(100 - level)))
        case .recovered:
            // The five-hour limit resets several times a day. Unnamed, its
            // reset sounds like an all-clear the weekly limit may be nowhere
            // near giving.
            switch event.windowID {
            case "session": return self("The 5-hour limit reset, you can come back.")
            case "weekly":  return self("The weekly limit reset, you can come back.")
            case "premium": return self("The monthly limit reset, you can come back.")
            default:        return self("The limit reset, you can come back.")
            }
        }
    }

    private func unit(_ unit: RemainingTime.Unit) -> String {
        let key = switch unit {
        case .days:    "%lldd"
        case .hours:   "%lldh"
        case .minutes: "%lldm"
        }
        return String(format: self(key), unit.value)
    }
}

/// Labels for settings values. They live next to the translations, not in the model.
public extension Localization {
    func title(_ value: Appearance) -> String {
        switch value {
        case .system: self("System")
        case .light:  self("Light")
        case .dark:   self("Dark")
        }
    }

    func title(_ value: MenuBarContent) -> String {
        switch value {
        case .iconOnly: self("Icon")
        case .timer:    self("Timer")
        case .percent:  self("Percent")
        case .both:     self("Both")
        }
    }

    func title(_ value: PrimaryWindow) -> String {
        switch value {
        case .worst:   self("Busiest")
        case .session: self("Five-hour")
        case .weekly:  self("Weekly")
        }
    }

    func title(_ value: RowLayout) -> String {
        switch value {
        case .twoWindows: self("Two windows")
        case .compact:    self("Single line")
        case .rings:      self("Rings")
        }
    }

    func title(_ value: Ordering) -> String {
        switch value {
        case .leastLoadedFirst: self("Least loaded first")
        case .byName:           self("By name")
        case .custom:           self("Custom")
        }
    }

    func title(_ value: WindowScope) -> String {
        switch value {
        case .session: self("5h")
        case .weekly:  self("week")
        case .both:    self("both")
        }
    }
}

public extension Severity {
    /// Bar, ring and fill colour. The thresholds live in `Severity` itself.
    var tint: Color {
        switch self {
        case .ok:       .green
        case .warning:  .yellow
        case .hot:      .orange
        case .critical: .red
        }
    }

    /// The colour a *number* takes, which is a different question.
    ///
    /// A bar is an area, and yellow reads perfectly well as one. Yellow digits
    /// on a light background do not — and the figure is the part somebody is
    /// actually trying to read, so losing it there costs more than the colour
    /// gains. A number therefore stays in the ordinary text colour until the
    /// limit is nearly spent, and takes orange and red only from `.hot` up,
    /// where both are legible either side of the theme.
    ///
    /// Nothing is lost by it: the bar beside the number carries all four
    /// levels, and it is the one that has the room for colour.
    var numberTint: AnyShapeStyle {
        switch self {
        case .ok, .warning:   AnyShapeStyle(.primary)
        case .hot, .critical: AnyShapeStyle(tint)
        }
    }
}
