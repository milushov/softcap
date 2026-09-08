import Testing
import Foundation
@testable import StatusUI

@Suite struct LocalizationCatalog {

    private static let languages = AppLanguage.allCases.filter { $0 != .system }

    @Test func everyLanguageHasACatalog() throws {
        for language in Self.languages {
            let path = Localization.lprojPath(language.rawValue)
            #expect(path != nil, "no catalogue for \(language.rawValue)")
        }
    }

    /// A missed translation would surface as the English key, and spotting that
    /// by eye across nine languages is hopeless — so the key sets are compared.
    @Test func everyLanguageCoversAllKeys() throws {
        let reference = try Self.keys(for: .english)
        #expect(reference.count >= 40, "the catalogue is suspiciously small: \(reference.count)")

        for language in Self.languages where language != .english {
            let keys = try Self.keys(for: language)
            let missing = reference.subtracting(keys)
            let extra = keys.subtracting(reference)
            #expect(missing.isEmpty, "\(language.rawValue): no translation for \(missing.sorted())")
            #expect(extra.isEmpty, "\(language.rawValue): unexpected keys \(extra.sorted())")
        }
    }

    /// The placeholders have to match: where English has "%@" and a translation
    /// does not, the account name simply vanishes from the message.
    @Test func placeholdersMatchAcrossLanguages() throws {
        let reference = try Self.entries(for: .english)

        for language in Self.languages where language != .english {
            let entries = try Self.entries(for: language)
            for (key, value) in entries {
                guard let source = reference[key] else { continue }
                #expect(Self.placeholders(source) == Self.placeholders(value),
                        "\(language.rawValue): placeholders disagree in \(key)")
            }
        }
    }

    @Test func unknownCodeFallsBackToSystem() {
        #expect(AppLanguage(code: "kl") == .system)
        #expect(AppLanguage(code: nil) == .system)
        #expect(AppLanguage(code: "ru") == .russian)
    }

    @Test func onlyArabicIsRightToLeft() {
        let rtl = AppLanguage.allCases.filter(\.isRightToLeft)
        #expect(rtl == [.arabic])
    }

    // MARK: - reading the catalogues

    private static func keys(for language: AppLanguage) throws -> Set<String> {
        Set(try entries(for: language).keys)
    }

    private static func entries(for language: AppLanguage) throws -> [String: String] {
        guard let path = Localization.lprojPath(language.rawValue),
              let file = Bundle(path: path)?.path(forResource: "Localizable", ofType: "strings"),
              let dictionary = NSDictionary(contentsOfFile: file) as? [String: String]
        else {
            Issue.record("could not read the catalogue for \(language.rawValue)")
            return [:]
        }
        return dictionary
    }

    private static func placeholders(_ text: String) -> [String] {
        let pattern = "%(@|lld|d|s)"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap {
            Range($0.range, in: text).map { String(text[$0]) }
        }
    }
}

@Suite @MainActor struct LocalizationSwitching {

    @Test func switchingLanguageChangesTheString() {
        let loc = Localization()
        loc.use(.russian)
        #expect(loc("Refresh") == "Обновить")

        loc.use(.arabic)
        #expect(loc("Refresh") == "تحديث")

        loc.use(.indonesian)
        #expect(loc("Refresh") == "Segarkan")
    }

    @Test func systemFallsBackToKeyForUntranslatedBundle() {
        let loc = Localization()
        loc.use(.english)
        #expect(loc("Refresh") == "Refresh")
    }

    @Test func layoutDirectionFollowsArabic() {
        let loc = Localization()
        loc.use(.arabic)
        #expect(loc.layoutDirection == .rightToLeft)

        loc.use(.russian)
        #expect(loc.layoutDirection == .leftToRight)

        loc.use(.system)
        // Under the system language the direction is the system's choice, not the app's.
        #expect(loc.layoutDirection == nil)
    }

    @Test func windowTitlesTranslate() {
        let loc = Localization()
        loc.use(.russian)
        #expect(loc.windowTitle("session") == "5ч")
        #expect(loc.windowTitle("weekly") == "нед")
    }

    @Test func remainingTimeUsesTranslatedUnits() {
        let loc = Localization()
        loc.use(.russian)
        #expect(loc.remaining(13_140) == "3 ч 39 м")
        #expect(loc.remaining(517_140) == "5 д 23 ч")
        #expect(loc.remaining(nil) == "—")
    }
}
