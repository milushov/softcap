# Localization into ten languages — design

Date: 2026-08-30
Status: approved, implemented

## Problem

The interface was written in Russian, as string literals in the code. Ten
languages are needed, including Arabic with right-to-left script.

The work has two parts, and the second matters more:

1. **Translations.** About 105 strings into ten languages.
2. **Refactoring.** Of those 105 strings, **35 lived in `Packages/Core`** — in
   models that have no business knowing about language.

## Languages

The ten most spoken; Russian and Indonesian make the list on their own.

| Code | Language | | Code | Language |
|---|---|---|---|---|
| `en` | English (base) | | `fr` | French |
| `zh-Hans` | Chinese, simplified | | `bn` | Bengali |
| `hi` | Hindi | | `pt-BR` | Portuguese |
| `es` | Spanish | | `ru` | Russian |
| `ar` | Arabic (RTL) | | `id` | Indonesian |

English is the base language: string keys are the English text, so a missing
translation shows meaningful words rather than an identifier.

## Core decision: no UI strings in Core

Models used to hold ready-made labels. That broke two things at once: the
language could not change without a rebuild, and `Core` could not be ported to
iOS with a different string set.

The rule: **`Packages/Core` returns nothing shown to a person.** It hands out
identifiers and numbers; translation lives in the app layer.

What moved:

| Was in Core | Became |
|---|---|
| `LimitWindow.label` = `"5ч"` | removed; the UI translates by `id` (`session`/`weekly`) |
| `Appearance.title` = `"Системное"` | removed; the UI supplies a label per value |
| `.title` on `MenuBarContent`, `PrimaryWindow`, `RowLayout`, `Ordering`, `WindowScope` | same |
| `ProviderID.title` = `"Claude"` | **stays** — brand names are not translated |
| `ProviderFailure.message` = `"Нужен вход"` | renamed to `diagnostic`, for the log; the UI builds text from `kind` |
| `formatRemaining` → `"3 ч 39 м"` | returns `RemainingTime(days:hours:minutes:)`; the UI formats |

`ProviderFailure.kind` already existed and already described the case
(`needsLogin`, `network`, `noData`, `malformed`) — which means the message text
was redundant duplication.

`RemainingTime` replaces a ready string because unit order and inflection depend
on the language: Russian says "5 д 23 ч", Arabic runs units right to left, and
some languages need different forms for 1, 2 and 5.

## Translation mechanism

**Localization catalogues** (`.lproj/Localizable.strings`), one directory per
language, under `StatusUI/Resources/`.

Keys are English phrases: `Text("Accounts")` still reads correctly if the
catalogue is missing.

### Choosing the language inside the app

The Appearance section gains a "Language" item: "System" plus the ten languages
written in their own script (Русский, العربية, Bahasa Indonesia…).

The switch takes effect **immediately**, without restarting. The app holds its
own `Bundle` for the chosen language:

```swift
@MainActor
final class Localization: ObservableObject {
    @Published private(set) var language: AppLanguage = .system
    private var bundle: Bundle = .module

    func callAsFunction(_ key: String) -> String {
        bundle.localizedString(forKey: key, value: key, table: nil)
    }
}
```

Root views carry `.id(localization.language)`, so a language change alters the
identity and forces a full redraw. Without it SwiftUI would reuse the labels it
had already rendered.

The system `AppleLanguages` mechanism is deliberately not used: it requires an
app restart. For a menu bar monitor that is unacceptable — the user changes the
language and expects the label to follow.

## Arabic: right-to-left

Changing direction affects more than text.

**What the system handles.** `HStack`, `leading`/`trailing` and
`padding(.leading)` mirror automatically, as long as `.left`/`.right` are not
used.

**What needs manual work:**

- **Limit bars.** The fill is drawn through a `GeometryReader` anchored
  `.leading` inside a `ZStack` — under RTL it must fill from the right edge.
- **The five-hour tick mark** in the single-line layout is positioned with
  `offset(x:)`, so under RTL the sign flips.
- **Rings** are drawn with `trim` from −90°; the sweep direction stays as is —
  circular indicators are not mirrored in any system.
- **The menu bar item.** `imagePosition = .imageLeading` already depends on
  direction; verified separately.
- **Numbers with percentages** stay left-to-right inside an Arabic string —
  that is Unicode's default behaviour and needs no intervention.

Verification: Appearance → language "العربية", then walk all six settings
sections and all three row layouts.

## Plural forms

Time units need different forms: "1 day", "2 days", "5 days". Catalogues support
this, with categories defined per language (Russian has one/few/many/other,
Arabic has six, Indonesian has one).

Keys: `"%lldd"`, `"%lldh"`, `"%lldm"` in short form.

## What is not translated

Service names (`Claude`, `Codex`, `Cursor`), plan names (`Max 20x`, `Plus`) and
technical identifiers (`~/.codex`, keychain item names). The plan name comes from
the service and is not subject to translation.

## Errors

- Missing translation — the key is shown, i.e. the English phrase.
- Unknown language code in settings — falls back to system.
- Catalogue missing from the bundle — the app runs in English rather than
  crashing.

## Tests

- `RemainingTime` splits an interval correctly: 47 minutes, 3 h 39 m, 5 d 23 h;
  a negative interval yields `nil`;
- `AppLanguage` encodes and decodes; an unknown code yields `.system`;
- every catalogue key is present in all ten languages (checked by reading the
  catalogue files, not by eye);
- no strings with Cyrillic remain in `Packages/Core` — checked by a test that
  scans the sources: this is the safeguard against UI strings drifting back into
  models.

That last test is the important one: it keeps the architectural rule from
eroding over time.

## Out of scope

Translating the README and documentation, localizing number and date formats
beyond the system defaults, VoiceOver narration beyond labels.
