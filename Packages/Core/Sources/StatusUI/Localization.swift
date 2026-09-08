import Foundation
import SwiftUI
import os

/// Interface languages: the ten most spoken, plus "follow the system".
///
/// Ordered by number of speakers rather than alphabetically: what a person is
/// most likely looking for comes first.
public enum AppLanguage: String, Codable, Sendable, CaseIterable, Identifiable {
    case system
    case english = "en"
    case chinese = "zh-Hans"
    case hindi = "hi"
    case spanish = "es"
    case arabic = "ar"
    case french = "fr"
    case bengali = "bn"
    case portuguese = "pt-BR"
    case russian = "ru"
    case indonesian = "id"

    public var id: String { rawValue }

    /// The language's name in its own script: someone scanning the list in an
    /// interface they cannot read looks for familiar letters, not a translation.
    public var endonym: String {
        switch self {
        case .system:     "—"
        case .english:    "English"
        case .chinese:    "简体中文"
        case .hindi:      "हिन्दी"
        case .spanish:    "Español"
        case .arabic:     "العربية"
        case .french:     "Français"
        case .bengali:    "বাংলা"
        case .portuguese: "Português"
        case .russian:    "Русский"
        case .indonesian: "Bahasa Indonesia"
        }
    }

    /// Whether the language is written right to left.
    public var isRightToLeft: Bool { self == .arabic }

    /// An unknown code falls back to system rather than crashing.
    public init(code: String?) {
        self = code.flatMap(AppLanguage.init(rawValue:)) ?? .system
    }
}

/// The current interface language and access to translations.
///
/// A custom wrapper rather than the system `AppleLanguages` mechanism: that one
/// requires an app restart. For a menu bar monitor this is unacceptable — the
/// user changes the language and expects the label to follow at once.
@MainActor
public final class Localization: ObservableObject {
    public static let shared = Localization()

    @Published public private(set) var language: AppLanguage = .system

    private var bundle: Bundle = .module

    public init() {}

    private static let log = Logger(subsystem: "app.softcap.Softcap", category: "l10n")

    public func use(_ language: AppLanguage) {
        self.language = language
        bundle = Self.bundle(for: language)
        Self.log.info("language: \(language.rawValue, privacy: .public)")
    }

    public func callAsFunction(_ key: String) -> String {
        bundle.localizedString(forKey: key, value: key, table: nil)
    }

    /// Writing direction for the chosen language. Under "system" the system decides.
    public var layoutDirection: LayoutDirection? {
        guard language != .system else { return nil }
        return language.isRightToLeft ? .rightToLeft : .leftToRight
    }

    private static func bundle(for language: AppLanguage) -> Bundle {
        guard language != .system, let path = lprojPath(language.rawValue) else { return .module }
        return Bundle(path: path) ?? .module
    }

    /// The translation catalogue in resources.
    ///
    /// Looked up in two spellings: SwiftPM lowercases localization directory
    /// names when building resources, so `zh-Hans.lproj` in the sources becomes
    /// `zh-hans.lproj` in the bundle.
    nonisolated static func lprojPath(_ code: String) -> String? {
        Bundle.module.path(forResource: code, ofType: "lproj")
            ?? Bundle.module.path(forResource: code.lowercased(), ofType: "lproj")
    }
}
