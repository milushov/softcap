> **Note.** This plan is kept in Russian: it is a record of work already
> carried out, step by step, not a reference document. New plans are written
> in English. See `docs/DECISIONS.md` for the reasoning.

# Экран настроек — план реализации

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Окно настроек с шестью разделами, которое действительно управляет поведением приложения, плюс вход в аккаунт Claude через браузер прямо из настроек.

**Architecture:** Модель настроек и вся логика, которую можно проверить без запуска приложения, живут в новом модуле `Packages/Core/Sources/Preferences`. Существующие места, где значения зашиты (`ThresholdTracker`, `orderedForDisplay`, интервалы опроса), начинают принимать их параметром. Экраны — сцена `Settings` в `App/Settings/`, по файлу на раздел.

**Tech Stack:** Swift 6.2, SwiftUI `Settings` + `NavigationSplitView`, `UserDefaults`, `CryptoKit` (PKCE), `Network` (слушатель для возврата из браузера), `ServiceManagement` (автозапуск), Carbon (глобальные сочетания), Swift Testing.

## Global Constraints

- Swift tools version `6.2`, платформа `.macOS(.v14)`, строгая конкурентность.
- Ни один тест не ходит в сеть, не читает Keychain и не пишет в `UserDefaults` — всё за протоколами.
- Секреты (`code_verifier`, токены) не попадают в логи, `UserDefaults` и сообщения об ошибках.
- Настройки хранятся в `UserDefaults` одним ключом `preferences`; учётные данные остаются в Keychain.
- Язык интерфейса — русский. Оформление по умолчанию — `Системное`.
- Пороги по умолчанию `[80, 95]`; интервалы опроса 60 с и 300 с; границы интервалов 30…3600 с.
- Адреса OAuth (из констант Claude Code, проверены 2026-08-30):
  authorize `https://platform.claude.com/oauth/authorize`,
  token `https://platform.claude.com/v1/oauth/token`,
  client_id `9d1c250a-e61b-44d9-88ed-5944d1962f5e`,
  scope `org:create_api_key user:profile user:inference`.
- Иконки разделов — монохромные штриховые глифы в цвет подписи, без плашек.

## Структура файлов

```
Packages/Core/Sources/Preferences/          # новый модуль
├── Preferences.swift          # модель, значения по умолчанию, нормализация
├── QuietHours.swift           # окно тишины, в том числе через полночь
└── PreferencesStore.swift     # протокол хранилища + UserDefaults

Packages/Core/Sources/ClaudeProvider/
├── OAuthEndpoints.swift       # адреса и client_id одним местом
├── PKCE.swift                 # verifier, challenge, base64url
├── OAuthLogin.swift           # сборка URL + обмен кода на токены
└── ClaudeProvider.swift       # (без изменений)

Packages/Core/Sources/Credentials/
└── CredentialStore.swift      # + addLoggedInAccount, forget, hidden

Packages/Core/Sources/Monitoring/
└── ThresholdNotifier.swift    # пороги и тихие часы параметром

Packages/Core/Sources/ProviderKit/
└── SnapshotOrdering.swift     # порядок параметром

App/
├── PreferencesModel.swift     # @MainActor обёртка над Preferences
├── LaunchAtLogin.swift        # SMAppService
├── LoginController.swift      # слушатель localhost + запуск браузера
├── HotKeys.swift              # Carbon RegisterEventHotKey
└── Settings/
    ├── SettingsView.swift     # каркас, боковая панель
    ├── SettingsIcons.swift    # монохромные глифы разделов
    ├── AccountsPane.swift
    ├── AppearancePane.swift
    ├── NotificationsPane.swift
    ├── UpdatesPane.swift
    ├── ServicesPane.swift
    └── AboutPane.swift
```

---

### Task 1: Модель настроек

**Files:**
- Create: `Packages/Core/Sources/Preferences/Preferences.swift`
- Create: `Packages/Core/Sources/Preferences/QuietHours.swift`
- Modify: `Packages/Core/Package.swift`
- Test: `Packages/Core/Tests/PreferencesTests/PreferencesTests.swift`
- Test: `Packages/Core/Tests/PreferencesTests/QuietHoursTests.swift`

**Interfaces:**
- Consumes: `ProviderID` из `ProviderKit`.
- Produces:
  - `enum Appearance: String, Codable, Sendable, CaseIterable` — `.system`, `.light`, `.dark`
  - `enum MenuBarContent: String, Codable, Sendable, CaseIterable` — `.iconOnly`, `.timer`, `.percent`, `.both`
  - `enum PrimaryWindow: String, Codable, Sendable, CaseIterable` — `.worst`, `.session`, `.weekly`
  - `enum RowLayout: String, Codable, Sendable, CaseIterable` — `.twoWindows`, `.compact`, `.rings`
  - `enum Ordering: String, Codable, Sendable, CaseIterable` — `.leastLoadedFirst`, `.byName`
  - `enum WindowScope: String, Codable, Sendable, CaseIterable` — `.session`, `.weekly`, `.both`
  - `struct QuietHours: Codable, Sendable, Hashable` — `init(startMinute:endMinute:)`, `contains(_ date: Date, calendar: Calendar) -> Bool`
  - `struct Preferences: Codable, Sendable, Equatable` — все поля из спеки, `static let defaults`, `func normalized() -> Preferences`
  - `Preferences.intervalRange: ClosedRange<TimeInterval>` = `30...3600`

- [ ] **Step 1: Добавить модуль в манифест**

В `Packages/Core/Package.swift` добавить в `products`:

```swift
        .library(name: "Preferences", targets: ["Preferences"]),
```

и в `targets`:

```swift
        .target(name: "Preferences", dependencies: ["ProviderKit"]),
        .testTarget(name: "PreferencesTests", dependencies: ["Preferences"]),
```

Создать каталоги:

```bash
mkdir -p Packages/Core/Sources/Preferences Packages/Core/Tests/PreferencesTests
```

- [ ] **Step 2: Написать падающий тест на окно тишины**

Создать `Packages/Core/Tests/PreferencesTests/QuietHoursTests.swift`:

```swift
import Testing
import Foundation
@testable import Preferences

private var utc: Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    return c
}

private func at(_ hour: Int, _ minute: Int) -> Date {
    utc.date(from: DateComponents(year: 2026, month: 8, day: 30, hour: hour, minute: minute))!
}

@Test func daytimeWindowContainsOnlyItsHours() {
    let hours = QuietHours(startMinute: 13 * 60, endMinute: 14 * 60)   // 13:00–14:00
    #expect(hours.contains(at(13, 30), calendar: utc))
    #expect(hours.contains(at(12, 59), calendar: utc) == false)
    #expect(hours.contains(at(14, 0), calendar: utc) == false)   // конец не включаем
}

@Test func windowAcrossMidnightWorksOnBothSides() {
    let hours = QuietHours(startMinute: 23 * 60, endMinute: 9 * 60)    // 23:00–09:00
    #expect(hours.contains(at(23, 30), calendar: utc))   // вечер
    #expect(hours.contains(at(2, 0), calendar: utc))     // ночь
    #expect(hours.contains(at(8, 59), calendar: utc))    // утро
    #expect(hours.contains(at(9, 0), calendar: utc) == false)
    #expect(hours.contains(at(15, 0), calendar: utc) == false)
}

@Test func startEqualToEndMeansAlwaysQuiet() {
    // Вырожденный случай: пользователь выставил одинаковое время.
    // Трактуем как «тишина круглые сутки», а не «никогда».
    let hours = QuietHours(startMinute: 60, endMinute: 60)
    #expect(hours.contains(at(0, 30), calendar: utc))
    #expect(hours.contains(at(12, 0), calendar: utc))
}
```

- [ ] **Step 3: Убедиться, что тест падает**

Run: `cd Packages/Core && swift test --filter QuietHoursTests`
Expected: FAIL — модуль `Preferences` ещё пуст.

- [ ] **Step 4: Реализовать окно тишины**

Создать `Packages/Core/Sources/Preferences/QuietHours.swift`:

```swift
import Foundation

/// Промежуток суток, заданный минутами от полуночи.
/// Хранится в минутах, а не датами: настройка привязана ко времени дня,
/// а не к конкретному дню, и переживает смену часового пояса.
public struct QuietHours: Codable, Sendable, Hashable {
    public let startMinute: Int
    public let endMinute: Int

    public init(startMinute: Int, endMinute: Int) {
        self.startMinute = max(0, min(startMinute, 24 * 60 - 1))
        self.endMinute = max(0, min(endMinute, 24 * 60 - 1))
    }

    public func contains(_ date: Date, calendar: Calendar = .current) -> Bool {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        let minute = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)

        // Начало позже конца — промежуток переваливает через полночь,
        // и тогда «внутри» означает «после начала ИЛИ до конца».
        if startMinute < endMinute {
            return minute >= startMinute && minute < endMinute
        }
        if startMinute > endMinute {
            return minute >= startMinute || minute < endMinute
        }
        return true   // начало равно концу — тишина круглые сутки
    }
}
```

- [ ] **Step 5: Убедиться, что тесты проходят**

Run: `cd Packages/Core && swift test --filter QuietHoursTests`
Expected: PASS, 3 теста.

- [ ] **Step 6: Написать падающий тест на модель**

Создать `Packages/Core/Tests/PreferencesTests/PreferencesTests.swift`:

```swift
import Testing
import Foundation
import ProviderKit
@testable import Preferences

@Test func defaultsMatchTheSpec() {
    let p = Preferences.defaults
    #expect(p.appearance == .system)
    #expect(p.menuBarContent == .timer)
    #expect(p.primaryWindow == .worst)
    #expect(p.rowLayout == .twoWindows)
    #expect(p.ordering == .leastLoadedFirst)
    #expect(p.showSnapshotAge)
    #expect(p.notificationsEnabled)
    #expect(p.thresholds == [95, 80])
    #expect(p.notifyOnRecovery)
    #expect(p.notifyWindows == .both)
    #expect(p.quietHours == nil)
    #expect(p.foregroundInterval == 60)
    #expect(p.backgroundInterval == 300)
    #expect(p.refreshAfterWake)
    #expect(p.disabledProviders.isEmpty)
    #expect(p.hiddenAccounts.isEmpty)
    #expect(p.codexRoot == nil)
}

@Test func thresholdsAreSortedDescendingAndDeduplicated() {
    var p = Preferences.defaults
    p.thresholds = [50, 95, 50, 80]
    #expect(p.normalized().thresholds == [95, 80, 50])
}

@Test func thresholdsOutsideRangeAreDropped() {
    var p = Preferences.defaults
    p.thresholds = [0, 50, 100, 140, -10]
    // 0 и отрицательные бессмысленны, выше 100 недостижимо
    #expect(p.normalized().thresholds == [100, 50])
}

@Test func emptyThresholdListIsAllowed() {
    var p = Preferences.defaults
    p.thresholds = []
    #expect(p.normalized().thresholds.isEmpty)
}

@Test func intervalsAreClampedToAllowedRange() {
    var p = Preferences.defaults
    p.foregroundInterval = 5
    p.backgroundInterval = 7200
    let n = p.normalized()
    #expect(n.foregroundInterval == 30)
    #expect(n.backgroundInterval == 3600)
}

@Test func intervalsInsideRangeSurviveUntouched() {
    var p = Preferences.defaults
    p.foregroundInterval = 45
    p.backgroundInterval = 600
    let n = p.normalized()
    #expect(n.foregroundInterval == 45)
    #expect(n.backgroundInterval == 600)
}

@Test func survivesEncodingRoundTrip() throws {
    var p = Preferences.defaults
    p.appearance = .dark
    p.thresholds = [90]
    p.quietHours = QuietHours(startMinute: 23 * 60, endMinute: 9 * 60)
    p.disabledProviders = [.codex]
    p.hiddenAccounts = ["claude/u-1"]
    p.codexRoot = "/tmp/codex"

    let data = try JSONEncoder().encode(p)
    let back = try JSONDecoder().decode(Preferences.self, from: data)
    #expect(back == p)
}
```

- [ ] **Step 7: Убедиться, что тест падает**

Run: `cd Packages/Core && swift test --filter PreferencesTests`
Expected: FAIL, `cannot find 'Preferences' in scope`.

- [ ] **Step 8: Реализовать модель**

Создать `Packages/Core/Sources/Preferences/Preferences.swift`:

```swift
import Foundation
import ProviderKit

public enum Appearance: String, Codable, Sendable, CaseIterable {
    case system, light, dark

    public var title: String {
        switch self {
        case .system: "Системное"
        case .light:  "Светлое"
        case .dark:   "Тёмное"
        }
    }
}

public enum MenuBarContent: String, Codable, Sendable, CaseIterable {
    case iconOnly, timer, percent, both

    public var title: String {
        switch self {
        case .iconOnly: "Иконка"
        case .timer:    "Таймер"
        case .percent:  "Процент"
        case .both:     "Оба"
        }
    }
}

public enum PrimaryWindow: String, Codable, Sendable, CaseIterable {
    case worst, session, weekly

    public var title: String {
        switch self {
        case .worst:   "Самое забитое"
        case .session: "Пятичасовое"
        case .weekly:  "Недельное"
        }
    }
}

public enum RowLayout: String, Codable, Sendable, CaseIterable {
    case twoWindows, compact, rings

    public var title: String {
        switch self {
        case .twoWindows: "Два окна"
        case .compact:    "Одна строка"
        case .rings:      "Кольца"
        }
    }
}

public enum Ordering: String, Codable, Sendable, CaseIterable {
    case leastLoadedFirst, byName

    public var title: String {
        switch self {
        case .leastLoadedFirst: "Свободные сверху"
        case .byName:           "По имени"
        }
    }
}

public enum WindowScope: String, Codable, Sendable, CaseIterable {
    case session, weekly, both

    public var title: String {
        switch self {
        case .session: "5ч"
        case .weekly:  "нед"
        case .both:    "оба"
        }
    }

    /// Подходит ли окно с таким идентификатором под выбранный охват.
    public func includes(windowID: String) -> Bool {
        switch self {
        case .both:    true
        case .session: windowID == "session"
        case .weekly:  windowID == "weekly"
        }
    }
}

public struct Preferences: Codable, Sendable, Equatable {
    // Внешний вид
    public var appearance: Appearance
    public var menuBarContent: MenuBarContent
    public var primaryWindow: PrimaryWindow
    public var rowLayout: RowLayout
    public var ordering: Ordering
    public var showSnapshotAge: Bool

    // Уведомления
    public var notificationsEnabled: Bool
    public var thresholds: [Int]
    public var notifyOnRecovery: Bool
    public var notifyWindows: WindowScope
    public var quietHours: QuietHours?

    // Обновление и запуск
    public var foregroundInterval: TimeInterval
    public var backgroundInterval: TimeInterval
    public var refreshAfterWake: Bool

    // Сервисы и аккаунты
    public var disabledProviders: Set<ProviderID>
    public var hiddenAccounts: Set<String>
    public var codexRoot: String?

    /// Допустимые границы опроса. Чаще, чем раз в полминуты, ходить незачем:
    /// лимиты на стороне сервиса пересчитываются не мгновенно. Реже часа —
    /// монитор перестаёт быть монитором.
    public static let intervalRange: ClosedRange<TimeInterval> = 30...3600

    public static let defaults = Preferences(
        appearance: .system,
        menuBarContent: .timer,
        primaryWindow: .worst,
        rowLayout: .twoWindows,
        ordering: .leastLoadedFirst,
        showSnapshotAge: true,
        notificationsEnabled: true,
        thresholds: [95, 80],
        notifyOnRecovery: true,
        notifyWindows: .both,
        quietHours: nil,
        foregroundInterval: 60,
        backgroundInterval: 300,
        refreshAfterWake: true,
        disabledProviders: [],
        hiddenAccounts: [],
        codexRoot: nil
    )

    /// Приводит значения к допустимым. Вызывается перед сохранением и после
    /// чтения: настройки могут прийти из файла, который правили руками.
    public func normalized() -> Preferences {
        var copy = self
        copy.thresholds = Array(Set(thresholds.filter { $0 > 0 && $0 <= 100 }))
            .sorted(by: >)
        copy.foregroundInterval = Self.clamp(foregroundInterval)
        copy.backgroundInterval = Self.clamp(backgroundInterval)
        return copy
    }

    private static func clamp(_ value: TimeInterval) -> TimeInterval {
        min(max(value, intervalRange.lowerBound), intervalRange.upperBound)
    }
}
```

- [ ] **Step 9: Сделать `ProviderID` кодируемым**

`Preferences` хранит `Set<ProviderID>`, а raw-value enum **не получает**
`Codable` автоматически — без явного объявления весь `Preferences` перестанет
быть `Codable` с ошибкой «does not conform to protocol 'Decodable'». Проверено.

В `Packages/Core/Sources/ProviderKit/Models.swift` дописать `Codable` в
объявление:

```swift
public enum ProviderID: String, Sendable, Hashable, Codable, CaseIterable {
```

- [ ] **Step 10: Убедиться, что тесты проходят**

Run: `cd Packages/Core && swift test --filter PreferencesTests`
Expected: PASS, 7 тестов модели.

Run: `cd Packages/Core && swift test --filter QuietHoursTests`
Expected: PASS, 3 теста.

- [ ] **Step 11: Commit**

```bash
git add Packages/Core
git commit -m "Модель настроек: значения по умолчанию, границы, окно тишины"
```

---

### Task 2: Хранилище настроек

**Files:**
- Create: `Packages/Core/Sources/Preferences/PreferencesStore.swift`
- Test: `Packages/Core/Tests/PreferencesTests/PreferencesStoreTests.swift`

**Interfaces:**
- Consumes: `Preferences` из Task 1.
- Produces:
  - `protocol PreferencesStorage: Sendable` — `read() -> Data?`, `write(_ data: Data)`
  - `struct UserDefaultsStorage: PreferencesStorage` — `init(defaults: UserDefaults = .standard)`, ключ `"preferences"`
  - `actor PreferencesStore` — `init(storage:)`, `load() -> Preferences`, `save(_ value: Preferences)`, `current() -> Preferences`

- [ ] **Step 1: Написать падающий тест**

Создать `Packages/Core/Tests/PreferencesTests/PreferencesStoreTests.swift`:

```swift
import Testing
import Foundation
@testable import Preferences

private actor MemoryStorage: PreferencesStorage {
    private var data: Data?
    init(_ seed: Data? = nil) { data = seed }
    func read() -> Data? { data }
    func write(_ value: Data) { data = value }
}

@Test func emptyStorageGivesDefaults() async {
    let store = PreferencesStore(storage: MemoryStorage())
    #expect(await store.load() == Preferences.defaults)
}

@Test func savedValueComesBack() async {
    let storage = MemoryStorage()
    let store = PreferencesStore(storage: storage)
    var p = Preferences.defaults
    p.appearance = .dark
    p.thresholds = [70]
    await store.save(p)

    let reopened = PreferencesStore(storage: storage)
    let loaded = await reopened.load()
    #expect(loaded.appearance == .dark)
    #expect(loaded.thresholds == [70])
}

@Test func saveNormalizesBeforeWriting() async {
    let storage = MemoryStorage()
    let store = PreferencesStore(storage: storage)
    var p = Preferences.defaults
    p.thresholds = [80, 95, 80]
    p.foregroundInterval = 1
    await store.save(p)

    let loaded = await PreferencesStore(storage: storage).load()
    #expect(loaded.thresholds == [95, 80])
    #expect(loaded.foregroundInterval == 30)
}

@Test func corruptedDataFallsBackToDefaults() async {
    let storage = MemoryStorage(Data("это не json".utf8))
    let store = PreferencesStore(storage: storage)
    // Повреждённый файл не должен ронять приложение.
    #expect(await store.load() == Preferences.defaults)
}

@Test func partialDataFallsBackToDefaults() async {
    // Настройки от будущей версии, где полей меньше: важнее не упасть.
    let storage = MemoryStorage(Data(#"{"appearance":"dark"}"#.utf8))
    #expect(await PreferencesStore(storage: storage).load() == Preferences.defaults)
}

@Test func currentReturnsLastLoadedWithoutTouchingStorage() async {
    let store = PreferencesStore(storage: MemoryStorage())
    _ = await store.load()
    #expect(await store.current() == Preferences.defaults)
}
```

- [ ] **Step 2: Убедиться, что тест падает**

Run: `cd Packages/Core && swift test --filter PreferencesStoreTests`
Expected: FAIL, `cannot find 'PreferencesStore' in scope`.

- [ ] **Step 3: Реализовать**

Создать `Packages/Core/Sources/Preferences/PreferencesStore.swift`:

```swift
import Foundation

/// Хранилище за протоколом, чтобы тесты не писали в настоящий `UserDefaults`
/// и не оставляли следов в системе.
public protocol PreferencesStorage: Sendable {
    func read() async -> Data?
    func write(_ data: Data) async
}

public struct UserDefaultsStorage: PreferencesStorage {
    public static let key = "preferences"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    public func read() -> Data? { defaults.data(forKey: Self.key) }
    public func write(_ data: Data) { defaults.set(data, forKey: Self.key) }
}

public actor PreferencesStore {
    private let storage: any PreferencesStorage
    private var value: Preferences = .defaults

    public init(storage: any PreferencesStorage) { self.storage = storage }

    /// Читает настройки. Любая неудача — повреждённые данные, неполный набор
    /// полей от другой версии — даёт значения по умолчанию: настройки не тот
    /// повод, чтобы приложение не запустилось.
    @discardableResult
    public func load() async -> Preferences {
        guard let data = await storage.read(),
              let decoded = try? JSONDecoder().decode(Preferences.self, from: data)
        else {
            value = .defaults
            return value
        }
        value = decoded.normalized()
        return value
    }

    public func save(_ newValue: Preferences) async {
        value = newValue.normalized()
        guard let data = try? JSONEncoder().encode(value) else { return }
        await storage.write(data)
    }

    /// Последнее прочитанное значение, без обращения к хранилищу.
    public func current() -> Preferences { value }
}
```

- [ ] **Step 4: Убедиться, что тесты проходят**

Run: `cd Packages/Core && swift test --filter PreferencesStoreTests`
Expected: PASS, 6 тестов.

- [ ] **Step 5: Commit**

```bash
git add Packages/Core
git commit -m "Хранилище настроек с откатом на значения по умолчанию"
```

---

### Task 3: Пороги, тихие часы и порядок становятся настройками

**Files:**
- Modify: `Packages/Core/Sources/Monitoring/ThresholdNotifier.swift`
- Modify: `Packages/Core/Sources/ProviderKit/SnapshotOrdering.swift`
- Modify: `Packages/Core/Package.swift` (Monitoring зависит от Preferences)
- Modify: `Packages/Core/Tests/MonitoringTests/ThresholdNotifierTests.swift`
- Modify: `Packages/Core/Tests/ProviderKitTests/SnapshotOrderingTests.swift`

**Interfaces:**
- Consumes: `Preferences`, `QuietHours`, `WindowScope`, `Ordering` из Tasks 1–2.
- Produces:
  - `ThresholdTracker.init(thresholds: [Int], notifyOnRecovery: Bool, scope: WindowScope, quietHours: QuietHours?, calendar: Calendar)` — старый `init()` остаётся с прежним поведением по умолчанию
  - `ThresholdTracker.events(for:now:) -> [ThresholdEvent]` — добавлен параметр `now` для проверки тихих часов
  - `orderedForDisplay(_ snapshots: [AccountSnapshot], ordering: Ordering) -> [AccountSnapshot]` — прежняя однопараметрическая форма сохраняется

Сейчас `ThresholdTracker` берёт `[95, 80]` из константы типа, а `orderedForDisplay`
всегда сортирует по загрузке. Значения переезжают в параметры — заодно это
единственный способ проверить их на разных настройках.

- [ ] **Step 1: Добавить зависимость модуля**

В `Packages/Core/Package.swift` заменить строку с `Monitoring`:

```swift
        .target(name: "Monitoring", dependencies: ["ProviderKit", "Preferences"]),
```

и строку с `ProviderKit`-тестами оставить как есть, а `ProviderKit` пусть
остаётся без зависимостей: `Ordering` для сортировки объявлен в `Preferences`,
поэтому `orderedForDisplay` переезжает в `Monitoring`. Заменить строку
`SnapshotOrdering.swift` в списке файлов ниже — файл перемещается.

```bash
git mv Packages/Core/Sources/ProviderKit/SnapshotOrdering.swift \
       Packages/Core/Sources/Monitoring/SnapshotOrdering.swift
git mv Packages/Core/Tests/ProviderKitTests/SnapshotOrderingTests.swift \
       Packages/Core/Tests/MonitoringTests/SnapshotOrderingTests.swift
```

В `Packages/Core/Sources/Monitoring/SnapshotOrdering.swift` добавить первой строкой
`import Preferences`, а в тестах заменить `@testable import ProviderKit` на:

```swift
import ProviderKit
import Preferences
@testable import Monitoring
```

- [ ] **Step 2: Написать падающий тест на порядок по имени**

Дописать в `Packages/Core/Tests/MonitoringTests/SnapshotOrderingTests.swift`:

```swift
@Test func byNameIgnoresLoad() {
    let ordered = orderedForDisplay(
        [make("zeta", peak: 5), make("alpha", peak: 99)], ordering: .byName
    )
    #expect(ordered.map(\.id) == ["alpha", "zeta"])
}

@Test func byNameStillSinksFailures() {
    let ordered = orderedForDisplay(
        [make("alpha", peak: 0, failed: true), make("zeta", peak: 50)], ordering: .byName
    )
    #expect(ordered.map(\.id) == ["zeta", "alpha"])
}
```

- [ ] **Step 3: Убедиться, что тест падает**

Run: `cd Packages/Core && swift test --filter SnapshotOrderingTests`
Expected: FAIL — у `orderedForDisplay` нет параметра `ordering`.

- [ ] **Step 4: Реализовать порядок**

Заменить содержимое `Packages/Core/Sources/Monitoring/SnapshotOrdering.swift`:

```swift
import Foundation
import ProviderKit
import Preferences

/// Порядок строк в окне. Аккаунты с ошибкой всегда внизу независимо от выбора:
/// по ним нечего сказать, и держать их вверху значит занимать лучшее место
/// пустой строкой.
public func orderedForDisplay(
    _ snapshots: [AccountSnapshot], ordering: Ordering = .leastLoadedFirst
) -> [AccountSnapshot] {
    snapshots.sorted { lhs, rhs in
        let lhsFailed = lhs.failure != nil
        let rhsFailed = rhs.failure != nil
        if lhsFailed != rhsFailed { return !lhsFailed }

        switch ordering {
        case .leastLoadedFirst:
            if lhs.peakPercent != rhs.peakPercent { return lhs.peakPercent < rhs.peakPercent }
        case .byName:
            break
        }
        return lhs.displayName.localizedCompare(rhs.displayName) == .orderedAscending
    }
}
```

- [ ] **Step 5: Убедиться, что тесты порядка проходят**

Run: `cd Packages/Core && swift test --filter SnapshotOrderingTests`
Expected: PASS, 5 тестов.

- [ ] **Step 6: Написать падающий тест на настраиваемые пороги**

Дописать в `Packages/Core/Tests/MonitoringTests/ThresholdNotifierTests.swift`:

```swift
import Preferences

private var utcCalendar: Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    return c
}

private func moment(_ hour: Int) -> Date {
    utcCalendar.date(from: DateComponents(year: 2026, month: 8, day: 30, hour: hour))!
}

@Test func customThresholdFiresAtItsOwnLevel() {
    var tracker = ThresholdTracker(
        thresholds: [50], notifyOnRecovery: true, scope: .both,
        quietHours: nil, calendar: utcCalendar
    )
    _ = tracker.events(for: snap(10), now: moment(12))
    #expect(tracker.events(for: snap(51), now: moment(12)).map(\.kind) == [.crossed(50)])
}

@Test func emptyThresholdsSilenceLoadEventsButKeepRecovery() {
    var tracker = ThresholdTracker(
        thresholds: [], notifyOnRecovery: true, scope: .both,
        quietHours: nil, calendar: utcCalendar
    )
    _ = tracker.events(for: snap(10), now: moment(12))
    #expect(tracker.events(for: snap(99), now: moment(12)).isEmpty)
    #expect(tracker.events(for: snap(5), now: moment(12)).map(\.kind) == [.recovered])
}

@Test func recoveryCanBeTurnedOff() {
    var tracker = ThresholdTracker(
        thresholds: [80], notifyOnRecovery: false, scope: .both,
        quietHours: nil, calendar: utcCalendar
    )
    _ = tracker.events(for: snap(10), now: moment(12))
    _ = tracker.events(for: snap(90), now: moment(12))
    #expect(tracker.events(for: snap(5), now: moment(12)).isEmpty)
}

@Test func scopeLimitsWhichWindowsReport() {
    var tracker = ThresholdTracker(
        thresholds: [80], notifyOnRecovery: true, scope: .session,
        quietHours: nil, calendar: utcCalendar
    )
    // snap(...) отдаёт единственное окно с id "weekly" — под охват не подходит
    _ = tracker.events(for: snap(10), now: moment(12))
    #expect(tracker.events(for: snap(90), now: moment(12)).isEmpty)
}

@Test func quietHoursSuppressEventsInsideTheWindow() {
    var tracker = ThresholdTracker(
        thresholds: [80], notifyOnRecovery: true, scope: .both,
        quietHours: QuietHours(startMinute: 23 * 60, endMinute: 9 * 60),
        calendar: utcCalendar
    )
    _ = tracker.events(for: snap(10), now: moment(12))
    #expect(tracker.events(for: snap(90), now: moment(2)).isEmpty)      // ночь — молчим
}

@Test func quietHoursDoNotLoseTheCrossingAfterwards() {
    var tracker = ThresholdTracker(
        thresholds: [80], notifyOnRecovery: true, scope: .both,
        quietHours: QuietHours(startMinute: 23 * 60, endMinute: 9 * 60),
        calendar: utcCalendar
    )
    _ = tracker.events(for: snap(10), now: moment(12))
    _ = tracker.events(for: snap(90), now: moment(2))                    // подавлено
    // Замер уже учтён, поэтому повторного пересечения нет — и это правильно:
    // догонять ночные уведомления утром значит будить человека прошлым.
    #expect(tracker.events(for: snap(92), now: moment(12)).isEmpty)
}
```

- [ ] **Step 7: Убедиться, что тест падает**

Run: `cd Packages/Core && swift test --filter ThresholdNotifierTests`
Expected: FAIL — у `ThresholdTracker` нет такого инициализатора.

- [ ] **Step 8: Реализовать**

Заменить объявление `ThresholdTracker` в
`Packages/Core/Sources/Monitoring/ThresholdNotifier.swift` (сам `ThresholdEvent`
не трогать):

```swift
/// Помнит предыдущий замер и выдаёт событие только на пересечении порога.
/// Без этого фоновый опрос раз в пять минут превратился бы в поток уведомлений.
public struct ThresholdTracker: Sendable {
    private let thresholds: [Int]        // по убыванию
    private let notifyOnRecovery: Bool
    private let scope: WindowScope
    private let quietHours: QuietHours?
    private let calendar: Calendar
    private static let recoveryLevel = 50.0

    private var previous: [Key: Double] = [:]
    private var seenAtLeastOnce = false

    private struct Key: Hashable { let account: String; let window: String }

    public init(
        thresholds: [Int] = [95, 80],
        notifyOnRecovery: Bool = true,
        scope: WindowScope = .both,
        quietHours: QuietHours? = nil,
        calendar: Calendar = .current
    ) {
        self.thresholds = thresholds.sorted(by: >)
        self.notifyOnRecovery = notifyOnRecovery
        self.scope = scope
        self.quietHours = quietHours
        self.calendar = calendar
    }

    public mutating func events(
        for snapshots: [AccountSnapshot], now: Date = Date()
    ) -> [ThresholdEvent] {
        var events: [ThresholdEvent] = []
        var current: [Key: Double] = [:]

        // Тишина гасит уведомления, но замер всё равно записывается: иначе
        // утром прилетит пачка событий о том, что случилось ночью.
        let silent = quietHours?.contains(now, calendar: calendar) ?? false

        for snapshot in snapshots where snapshot.failure == nil {
            for window in snapshot.windows {
                let key = Key(account: snapshot.id, window: window.id)
                current[key] = window.percent

                guard seenAtLeastOnce, let before = previous[key],
                      scope.includes(windowID: window.id), !silent
                else { continue }
                let now = window.percent

                if let crossed = thresholds.first(where: {
                    before < Double($0) && now >= Double($0)
                }) {
                    events.append(ThresholdEvent(
                        accountID: snapshot.id, windowID: window.id,
                        accountName: snapshot.displayName, kind: .crossed(crossed)
                    ))
                } else if notifyOnRecovery,
                          before >= Self.recoveryLevel, now < Self.recoveryLevel {
                    events.append(ThresholdEvent(
                        accountID: snapshot.id, windowID: window.id,
                        accountName: snapshot.displayName, kind: .recovered
                    ))
                }
            }
        }

        previous = current
        seenAtLeastOnce = true
        return events
    }
}
```

Первой строкой файла добавить `import Preferences`.

- [ ] **Step 9: Убедиться, что весь пакет проходит**

Run: `cd Packages/Core && swift test`
Expected: PASS. Прежние восемь тестов `ThresholdNotifierTests` продолжают
работать без изменений — значения по умолчанию у инициализатора те же.

- [ ] **Step 10: Commit**

```bash
git add Packages/Core
git commit -m "Пороги, охват окон, тихие часы и порядок вынесены в параметры"
```

---

### Task 4: Каркас окна настроек

**Files:**
- Create: `App/PreferencesModel.swift`
- Create: `App/Settings/SettingsIcons.swift`
- Create: `App/Settings/SettingsView.swift`
- Modify: `App/StatusCheckerApp.swift`
- Modify: `App/PopoverView.swift`
- Modify: `project.yml` (зависимость от `Preferences`)

**Interfaces:**
- Consumes: `Preferences`, `PreferencesStore`, `UserDefaultsStorage` из Tasks 1–2.
- Produces:
  - `@MainActor final class PreferencesModel: ObservableObject` — `@Published var value: Preferences`, `func load() async`, `func update(_ change: (inout Preferences) -> Void)`
  - `enum SettingsSection: String, CaseIterable, Identifiable` — `.accounts`, `.appearance`, `.notifications`, `.updates`, `.services`, `.about`; свойства `title`, `icon`
  - `struct SettingsIcon: View` — `init(_ section: SettingsSection)`
  - `struct SettingsView: View` — `init(model: PreferencesModel, appModel: AppModel)`

- [ ] **Step 1: Подключить модуль к приложению**

В `project.yml` в блок `dependencies` цели `StatusChecker` добавить:

```yaml
      - package: Core
        product: Preferences
```

- [ ] **Step 2: Создать модель настроек для UI**

Создать `App/PreferencesModel.swift`:

```swift
import Foundation
import SwiftUI
import Preferences

/// Обёртка над `PreferencesStore` для SwiftUI: хранит текущее значение и
/// сохраняет каждое изменение сразу, без кнопки «Применить» — так принято
/// в настройках macOS.
@MainActor
final class PreferencesModel: ObservableObject {
    @Published private(set) var value: Preferences = .defaults

    private let store: PreferencesStore

    init(store: PreferencesStore = PreferencesStore(storage: UserDefaultsStorage())) {
        self.store = store
    }

    func load() async {
        value = await store.load()
    }

    func update(_ change: (inout Preferences) -> Void) {
        var draft = value
        change(&draft)
        value = draft.normalized()
        let snapshot = value
        Task { await store.save(snapshot) }
    }
}
```

- [ ] **Step 3: Создать разделы и монохромные глифы**

Создать `App/Settings/SettingsIcons.swift`:

```swift
import SwiftUI

enum SettingsSection: String, CaseIterable, Identifiable {
    case accounts, appearance, notifications, updates, services, about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .accounts:      "Аккаунты"
        case .appearance:    "Внешний вид"
        case .notifications: "Уведомления"
        case .updates:       "Обновление"
        case .services:      "Сервисы"
        case .about:         "О программе"
        }
    }

    /// Штриховые символы, а не цветные плашки: в окне лимитов цвет уже кодирует
    /// загрузку, и второй цветовой язык рядом ослабляет оба.
    var symbol: String {
        switch self {
        case .accounts:      "person.2"
        case .appearance:    "circle.lefthalf.filled"
        case .notifications: "bell"
        case .updates:       "arrow.clockwise"
        case .services:      "square.grid.2x2"
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
```

- [ ] **Step 4: Создать каркас окна**

Создать `App/Settings/SettingsView.swift`:

```swift
import SwiftUI
import Preferences

struct SettingsView: View {
    @ObservedObject var model: PreferencesModel
    @ObservedObject var appModel: AppModel

    @State private var selection: SettingsSection = .accounts

    var body: some View {
        NavigationSplitView {
            List(SettingsSection.allCases, selection: $selection) { section in
                NavigationLink(value: section) {
                    Label { Text(section.title) } icon: { SettingsIcon(section) }
                }
            }
            .navigationSplitViewColumnWidth(186)
        } detail: {
            Group {
                switch selection {
                case .accounts:      AccountsPane(model: model, appModel: appModel)
                case .appearance:    AppearancePane(model: model)
                case .notifications: NotificationsPane(model: model)
                case .updates:       UpdatesPane(model: model)
                case .services:      ServicesPane(model: model)
                case .about:         AboutPane(model: model, appModel: appModel)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(20)
        }
        .frame(width: 720, height: 470)
        .task { await model.load() }
    }
}

/// Общая обёртка раздела: заголовок, пояснение и содержимое.
/// Вынесена, чтобы шесть экранов не расходились в отступах и размерах.
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
```

- [ ] **Step 5: Создать заглушки шести разделов**

Чтобы каркас собрался до того, как разделы наполнятся, создать по файлу на
раздел. Каждый следующий заменяется в своей задаче.

```bash
mkdir -p App/Settings
for n in Accounts Appearance Notifications Updates Services About; do
  cat > "App/Settings/${n}Pane.swift" <<EOF
import SwiftUI
import Preferences

struct ${n}Pane: View {
    @ObservedObject var model: PreferencesModel

    var body: some View {
        Pane(title: "${n}", subtitle: "Наполняется в следующей задаче") { EmptyView() }
    }
}
EOF
done
```

Разделы `Accounts` и `About` принимают ещё и `appModel`, поэтому в них добавить
строку `@ObservedObject var appModel: AppModel` после `model`:

```bash
for n in Accounts About; do
  /usr/bin/sed -i '' 's/    @ObservedObject var model: PreferencesModel/    @ObservedObject var model: PreferencesModel\n    @ObservedObject var appModel: AppModel/' "App/Settings/${n}Pane.swift"
done
```

- [ ] **Step 6: Объявить сцену и пункт открытия**

В `App/StatusCheckerApp.swift` добавить в `StatusCheckerApp` свойство и сцену:

```swift
@main
struct StatusCheckerApp: App {
    @StateObject private var model = AppModel()
    @StateObject private var preferences = PreferencesModel()

    var body: some Scene {
        MenuBarExtra {
            PopoverView(model: model)
        } label: {
            MenuBarLabel(model: model)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(model: preferences, appModel: model)
        }
    }
}
```

В `App/PopoverView.swift` в `footer` добавить пункт между «Обновить» и «Выйти»:

```swift
    private var footer: some View {
        HStack {
            Button("Обновить") { Task { await model.refresh() } }
                .buttonStyle(.plain)
                .font(.system(size: 11.5))
                .keyboardShortcut("r")
            Spacer()
            SettingsLink { Text("Настройки…") }
                .buttonStyle(.plain)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
            Spacer()
            Button("Выйти") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.plain)
                .font(.system(size: 11.5))
                .foregroundStyle(.tertiary)
                .keyboardShortcut("q")
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }
```

- [ ] **Step 7: Собрать и открыть**

Run: `make build`
Expected: `BUILD SUCCEEDED`.

Run: `make run`, затем нажать значок в строке меню и «Настройки…».
Expected: открывается окно 720×470 с боковой панелью из шести разделов,
иконки монохромные, подписи целые.

- [ ] **Step 8: Commit**

```bash
git add App project.yml
git commit -m "Каркас окна настроек: боковая панель и шесть разделов"
```

---

### Task 5: Раздел «Внешний вид» и применение оформления

**Files:**
- Modify: `App/Settings/AppearancePane.swift`
- Modify: `App/StatusCheckerApp.swift`
- Modify: `App/AccountRowView.swift`
- Modify: `App/AppModel.swift`

**Interfaces:**
- Consumes: `PreferencesModel` из Task 4; `Appearance`, `MenuBarContent`, `PrimaryWindow`, `RowLayout`, `Ordering` из Task 1.
- Produces: `func applyAppearance(_ appearance: Appearance)` в `App/StatusCheckerApp.swift`.

- [ ] **Step 1: Наполнить раздел**

Заменить содержимое `App/Settings/AppearancePane.swift`:

```swift
import SwiftUI
import Preferences

struct AppearancePane: View {
    @ObservedObject var model: PreferencesModel

    var body: some View {
        Pane(title: "Внешний вид",
             subtitle: "Как выглядит значок в строке меню и строка аккаунта в окне.") {
            Form {
                Picker("Оформление", selection: binding(\.appearance)) {
                    ForEach(Appearance.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)

                Picker("В строке меню", selection: binding(\.menuBarContent)) {
                    ForEach(MenuBarContent.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)

                Picker("Считать главным", selection: binding(\.primaryWindow)) {
                    ForEach(PrimaryWindow.allCases, id: \.self) { Text($0.title).tag($0) }
                }

                Picker("Компоновка строки", selection: binding(\.rowLayout)) {
                    ForEach(RowLayout.allCases, id: \.self) { Text($0.title).tag($0) }
                }

                Picker("Порядок", selection: binding(\.ordering)) {
                    ForEach(Ordering.allCases, id: \.self) { Text($0.title).tag($0) }
                }

                Toggle("Показывать возраст снимка", isOn: binding(\.showSnapshotAge))
            }
            .formStyle(.grouped)
        }
    }

    private func binding<T>(_ path: WritableKeyPath<Preferences, T>) -> Binding<T> {
        Binding(
            get: { model.value[keyPath: path] },
            set: { newValue in model.update { $0[keyPath: path] = newValue } }
        )
    }
}
```

- [ ] **Step 2: Применять оформление ко всему приложению**

В `App/StatusCheckerApp.swift` добавить функцию и вызов при изменении:

```swift
/// Переводит выбор пользователя в оформление AppKit.
/// `nil` означает «как в системе» — это и есть значение по умолчанию.
@MainActor
func applyAppearance(_ appearance: Appearance) {
    NSApp.appearance = switch appearance {
    case .system: nil
    case .light:  NSAppearance(named: .aqua)
    case .dark:   NSAppearance(named: .darkAqua)
    }
}
```

В `body` сцены `Settings` добавить реакцию:

```swift
        Settings {
            SettingsView(model: preferences, appModel: model)
                .onChange(of: preferences.value.appearance, initial: true) { _, new in
                    applyAppearance(new)
                }
        }
```

- [ ] **Step 3: Значок строки меню читает настройку**

В `App/StatusCheckerApp.swift` заменить `MenuBarLabel`:

```swift
private struct MenuBarLabel: View {
    @ObservedObject var model: AppModel
    let content: MenuBarContent

    var body: some View {
        Group {
            if let text = trailingText {
                Label {
                    Text(text).monospacedDigit()
                } icon: {
                    Image(systemName: "gauge.with.needle")
                }
                // Без явного стиля строка меню показывает только иконку.
                .labelStyle(.titleAndIcon)
            } else {
                Image(systemName: "gauge.with.needle")
            }
        }
        .task { await model.start() }
    }

    /// Что дописать рядом со значком. `nil` — только значок.
    private var trailingText: String? {
        guard let summary = model.summary else { return nil }
        let percent = "\(Int(summary.percent.rounded()))%"
        let timer = summary.remaining.map(formatRemainingCompact)

        switch content {
        case .iconOnly: return nil
        case .percent:  return percent
        case .timer:    return timer
        case .both:     return timer.map { "\(percent) · \($0)" } ?? percent
        }
    }
}
```

и передать настройку при создании:

```swift
        } label: {
            MenuBarLabel(model: model, content: preferences.value.menuBarContent)
        }
```

- [ ] **Step 4: Окно читает компоновку, порядок и возраст снимка**

В `App/AppModel.swift` добавить свойство и учесть его при опросе:

```swift
    /// Настройки, влияющие на опрос и показ. Обновляются из окна настроек.
    var preferences: Preferences = .defaults {
        didSet { restartTimer() }
    }
```

В `refresh()` заменить строку сортировки и сборки сводки:

```swift
        let result = orderedForDisplay(await poller.refresh(), ordering: preferences.ordering)
        snapshots = result
        summary = menuBarSummary(result, now: Date(), window: preferences.primaryWindow)
```

В `restartTimer()` заменить жёсткие числа:

```swift
        let interval = isPopoverOpen
            ? preferences.foregroundInterval
            : preferences.backgroundInterval
```

В `App/AccountRowView.swift` добавить параметры и скрыть плашку по настройке:

```swift
struct AccountRowView: View {
    let snapshot: AccountSnapshot
    let now: Date
    var layout: RowLayout = .twoWindows
    var showSnapshotAge: Bool = true
```

и в `header` заменить условие плашки:

```swift
            if snapshot.freshness.isStale && showSnapshotAge {
```

В `App/PopoverView.swift` передать значения:

```swift
                    AccountRowView(
                        snapshot: snapshot, now: now,
                        layout: model.preferences.rowLayout,
                        showSnapshotAge: model.preferences.showSnapshotAge
                    )
```

Компоновки `.compact` и `.rings` рисуются в Task 11; пока `AccountRowView`
игнорирует значение `layout`, кроме `.twoWindows`, — это осознанно, чтобы
раздел заработал раньше отрисовки альтернатив.

- [ ] **Step 5: Научить сводку выбирать окно**

В `Packages/Core/Sources/Monitoring/UsagePoller.swift` заменить `menuBarSummary`:

```swift
/// Что показать в строке меню.
/// По умолчанию берётся окно, ближайшее к исчерпанию: брать ближайший по
/// времени сброс нельзя — у свободного аккаунта он ни о чём не говорит.
public func menuBarSummary(
    _ snapshots: [AccountSnapshot], now: Date, window: PrimaryWindow = .worst
) -> MenuBarSummary? {
    let candidates: [LimitWindow] = switch window {
    case .worst:   snapshots.compactMap(\.peakWindow)
    case .session: snapshots.flatMap(\.windows).filter { $0.id == "session" }
    case .weekly:  snapshots.flatMap(\.windows).filter { $0.id == "weekly" }
    }
    guard let worst = candidates.max(by: { $0.percent < $1.percent }) else { return nil }

    return MenuBarSummary(
        percent: worst.percent, severity: worst.severity, remaining: worst.remaining(from: now)
    )
}
```

Первой строкой файла добавить `import Preferences`.

- [ ] **Step 6: Тест на выбор окна**

Дописать в `Packages/Core/Tests/MonitoringTests/UsagePollerTests.swift`:

```swift
@Test func menuBarCanBePinnedToWeeklyWindow() {
    let now = Date(timeIntervalSince1970: 1_000_000)
    let account = AccountSnapshot(
        id: "a", provider: .claude, displayName: "a", planLabel: "Max",
        windows: [
            LimitWindow(id: "session", label: "5ч", percent: 90, resetsAt: nil),
            LimitWindow(id: "weekly", label: "нед", percent: 20, resetsAt: nil),
        ],
        freshness: .live(now), failure: nil
    )
    #expect(menuBarSummary([account], now: now, window: .worst)?.percent == 90)
    #expect(menuBarSummary([account], now: now, window: .weekly)?.percent == 20)
    #expect(menuBarSummary([account], now: now, window: .session)?.percent == 90)
}
```

Дописать `import Preferences` в начало файла.

- [ ] **Step 7: Проверить**

Run: `cd Packages/Core && swift test --filter UsagePollerTests`
Expected: PASS, 7 тестов.

Run: `make build`
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 8: Commit**

```bash
git add App Packages/Core
git commit -m "Раздел «Внешний вид»: оформление, значок и вид окна"
```

---

### Task 6: Раздел «Уведомления»

**Files:**
- Modify: `App/Settings/NotificationsPane.swift`
- Modify: `App/AppModel.swift`

**Interfaces:**
- Consumes: `PreferencesModel` из Task 4; `ThresholdTracker.init(thresholds:notifyOnRecovery:scope:quietHours:calendar:)` из Task 3.
- Produces: `AppModel.rebuildTracker()` — пересобирает трекер при изменении настроек.

- [ ] **Step 1: Наполнить раздел**

Заменить содержимое `App/Settings/NotificationsPane.swift`:

```swift
import SwiftUI
import Preferences

struct NotificationsPane: View {
    @ObservedObject var model: PreferencesModel
    @State private var draftThreshold = ""

    var body: some View {
        Pane(title: "Уведомления",
             subtitle: "Событие приходит на пересечении порога снизу вверх, а не при каждом опросе выше него.") {
            Form {
                Toggle("Уведомлять", isOn: binding(\.notificationsEnabled))

                Section("Пороги") {
                    HStack(spacing: 6) {
                        ForEach(model.value.thresholds, id: \.self) { level in
                            HStack(spacing: 4) {
                                Text("\(level) %").font(.system(size: 11.5))
                                Button {
                                    model.update { $0.thresholds.removeAll { $0 == level } }
                                } label: {
                                    Image(systemName: "xmark").font(.system(size: 8))
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(.quaternary, in: Capsule())
                        }

                        TextField("+", text: $draftThreshold)
                            .frame(width: 44)
                            .onSubmit(addThreshold)
                    }
                    if model.value.thresholds.isEmpty {
                        Text("Порогов нет — о загрузке не уведомляем.")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }

                Toggle("Когда снова свободен", isOn: binding(\.notifyOnRecovery))

                Picker("По каким окнам", selection: binding(\.notifyWindows)) {
                    ForEach(WindowScope.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)

                Section("Тихие часы") {
                    Toggle("Не беспокоить ночью", isOn: quietEnabled)
                    if let hours = model.value.quietHours {
                        HStack {
                            timeField("С", minutes: hours.startMinute) { new in
                                model.update {
                                    $0.quietHours = QuietHours(
                                        startMinute: new, endMinute: hours.endMinute)
                                }
                            }
                            timeField("до", minutes: hours.endMinute) { new in
                                model.update {
                                    $0.quietHours = QuietHours(
                                        startMinute: hours.startMinute, endMinute: new)
                                }
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .disabled(!model.value.notificationsEnabled)
        }
    }

    private func addThreshold() {
        guard let level = Int(draftThreshold.trimmingCharacters(in: .whitespaces)),
              level > 0, level <= 100
        else { draftThreshold = ""; return }
        model.update { $0.thresholds.append(level) }   // normalized() отсортирует
        draftThreshold = ""
    }

    private var quietEnabled: Binding<Bool> {
        Binding(
            get: { model.value.quietHours != nil },
            set: { on in
                model.update {
                    $0.quietHours = on
                        ? QuietHours(startMinute: 23 * 60, endMinute: 9 * 60)
                        : nil
                }
            }
        )
    }

    private func timeField(
        _ label: String, minutes: Int, set: @escaping (Int) -> Void
    ) -> some View {
        HStack(spacing: 5) {
            Text(label).foregroundStyle(.secondary).font(.system(size: 11.5))
            Stepper(
                value: Binding(get: { minutes }, set: set),
                in: 0...(24 * 60 - 1), step: 30
            ) {
                Text(String(format: "%02d:%02d", minutes / 60, minutes % 60))
                    .monospacedDigit()
            }
        }
    }

    private func binding<T>(_ path: WritableKeyPath<Preferences, T>) -> Binding<T> {
        Binding(
            get: { model.value[keyPath: path] },
            set: { newValue in model.update { $0[keyPath: path] = newValue } }
        )
    }
}
```

- [ ] **Step 2: Пересобирать трекер при изменении настроек**

В `App/AppModel.swift` заменить объявление трекера и добавить пересборку:

```swift
    private var tracker = ThresholdTracker()
```

на

```swift
    private var tracker = ThresholdTracker()

    /// Трекер держит историю замеров, поэтому пересоздаётся только когда
    /// настройки уведомлений действительно изменились — иначе каждое открытие
    /// настроек стирало бы память о предыдущих значениях и первое же
    /// срабатывание после этого пропало бы.
    private var trackerSettings: TrackerSettings?

    private struct TrackerSettings: Equatable {
        let thresholds: [Int]
        let notifyOnRecovery: Bool
        let scope: WindowScope
        let quietHours: QuietHours?
    }

    private func rebuildTrackerIfNeeded() {
        let wanted = TrackerSettings(
            thresholds: preferences.thresholds,
            notifyOnRecovery: preferences.notifyOnRecovery,
            scope: preferences.notifyWindows,
            quietHours: preferences.quietHours
        )
        guard wanted != trackerSettings else { return }
        trackerSettings = wanted
        tracker = ThresholdTracker(
            thresholds: wanted.thresholds,
            notifyOnRecovery: wanted.notifyOnRecovery,
            scope: wanted.scope,
            quietHours: wanted.quietHours
        )
    }
```

В `refresh()` перед разбором событий вставить вызов и учесть выключатель:

```swift
        rebuildTrackerIfNeeded()
        if preferences.notificationsEnabled {
            for event in tracker.events(for: result, now: Date()) { post(event) }
        } else {
            // Замер всё равно скармливаем, чтобы после включения уведомлений
            // не прилетела пачка событий за всё время простоя.
            _ = tracker.events(for: result, now: Date())
        }
```

- [ ] **Step 3: Собрать и проверить**

Run: `make build`
Expected: `BUILD SUCCEEDED`.

Run: `make run`, открыть «Настройки… → Уведомления».
Expected: пороги показаны чипами, удаляются крестиком, добавляются вводом числа
и Enter; при выключенном «Уведомлять» форма недоступна.

- [ ] **Step 4: Commit**

```bash
git add App
git commit -m "Раздел «Уведомления»: настраиваемые пороги и тихие часы"
```

---

### Task 7: Раздел «Обновление и запуск»

**Files:**
- Create: `App/LaunchAtLogin.swift`
- Modify: `App/Settings/UpdatesPane.swift`
- Modify: `App/AppModel.swift`

**Interfaces:**
- Consumes: `PreferencesModel` из Task 4.
- Produces: `enum LaunchAtLogin` — `static var isEnabled: Bool`, `static func set(_ on: Bool) throws`.

- [ ] **Step 1: Реализовать автозапуск**

Создать `App/LaunchAtLogin.swift`:

```swift
import Foundation
import ServiceManagement

/// Запуск при входе в систему.
///
/// Состояние читается у системы, а не хранится в настройках: пользователь может
/// отключить автозапуск в системных настройках, и тогда наше сохранённое
/// значение врало бы.
enum LaunchAtLogin {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func set(_ on: Bool) throws {
        if on {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
```

- [ ] **Step 2: Наполнить раздел**

Заменить содержимое `App/Settings/UpdatesPane.swift`:

```swift
import SwiftUI
import Preferences

struct UpdatesPane: View {
    @ObservedObject var model: PreferencesModel

    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var launchError: String?

    var body: some View {
        Pane(title: "Обновление и запуск",
             subtitle: "Как часто ходить за данными и стартовать ли самому.") {
            Form {
                Section {
                    Toggle("Запускать при входе в систему", isOn: $launchAtLogin)
                        .onChange(of: launchAtLogin) { _, on in setLaunch(on) }
                    if let launchError {
                        Text(launchError)
                            .font(.system(size: 11)).foregroundStyle(.orange)
                    }
                }

                Section("Частота опроса") {
                    interval("Когда окно открыто", path: \.foregroundInterval)
                    interval("В фоне", path: \.backgroundInterval)
                    Toggle("Обновлять после пробуждения", isOn: binding(\.refreshAfterWake))
                }

                Section("Горячие клавиши") {
                    Text("Настраиваются в следующей версии.")
                        .font(.system(size: 11.5)).foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
        }
    }

    private func setLaunch(_ on: Bool) {
        do {
            try LaunchAtLogin.set(on)
            launchError = nil
        } catch {
            // Не притворяемся, что получилось: возвращаем переключатель назад.
            launchAtLogin = LaunchAtLogin.isEnabled
            launchError = "Не удалось изменить автозапуск. Проверьте «Системные настройки → Основные → Объекты входа»."
        }
    }

    private func interval(
        _ title: String, path: WritableKeyPath<Preferences, TimeInterval>
    ) -> some View {
        let value = model.value[keyPath: path]
        return Stepper(
            value: Binding(
                get: { value },
                set: { new in model.update { $0[keyPath: path] = new } }
            ),
            in: Preferences.intervalRange,
            step: 30
        ) {
            Text("\(title): \(label(for: value))")
        }
    }

    private func label(for seconds: TimeInterval) -> String {
        seconds < 60
            ? "\(Int(seconds)) с"
            : "\(Int(seconds) / 60) мин"
    }

    private func binding<T>(_ path: WritableKeyPath<Preferences, T>) -> Binding<T> {
        Binding(
            get: { model.value[keyPath: path] },
            set: { newValue in model.update { $0[keyPath: path] = newValue } }
        )
    }
}
```

- [ ] **Step 3: Обновлять после пробуждения**

В `App/AppModel.swift` в `start()` подписаться на уведомление о пробуждении:

```swift
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.preferences.refreshAfterWake else { return }
                await self.refresh()
            }
        }
```

Первой строкой файла добавить `import AppKit`.

- [ ] **Step 4: Собрать и проверить**

Run: `make build`
Expected: `BUILD SUCCEEDED`.

Run: `make run`, открыть «Настройки… → Обновление».
Expected: переключатель автозапуска отражает настоящее состояние системы;
шаг интервалов 30 секунд, ниже 30 с и выше часа не уходит.

- [ ] **Step 5: Commit**

```bash
git add App
git commit -m "Раздел «Обновление и запуск»: автозапуск и частоты опроса"
```

---

### Task 8: Раздел «Сервисы» и фильтрация опроса

**Files:**
- Modify: `App/Settings/ServicesPane.swift`
- Modify: `App/AppModel.swift`
- Modify: `Packages/Core/Sources/CodexProvider/CodexProvider.swift`

**Interfaces:**
- Consumes: `PreferencesModel` из Task 4; `RealCodexFileSystem(root:)` из прототипа.
- Produces: `AppModel.rebuildPoller()` учитывает `disabledProviders` и `codexRoot`.

- [ ] **Step 1: Наполнить раздел**

Заменить содержимое `App/Settings/ServicesPane.swift`:

```swift
import SwiftUI
import AppKit
import ProviderKit
import Preferences

struct ServicesPane: View {
    @ObservedObject var model: PreferencesModel

    private static let ready: [ProviderID] = [.claude, .codex]
    private static let planned: [ProviderID] = [.cursor, .copilot, .gemini]

    var body: some View {
        Pane(title: "Сервисы",
             subtitle: "Откуда брать данные. Выключенный сервис не опрашивается.") {
            Form {
                Section {
                    Toggle("Claude Code", isOn: enabled(.claude))
                    Text("Живые данные из API.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }

                Section {
                    Toggle("OpenAI Codex", isOn: enabled(.codex))
                    HStack {
                        Text(model.value.codexRoot ?? "~/.codex")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Button("Выбрать…") { chooseCodexRoot() }
                        if model.value.codexRoot != nil {
                            Button("Сбросить") { model.update { $0.codexRoot = nil } }
                        }
                    }
                    Text("Снимок из файлов сессий — обновляется, когда Codex ходит в сеть.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }

                Section("Позже") {
                    ForEach(Self.planned, id: \.self) { provider in
                        HStack {
                            Text(provider.title)
                            Spacer()
                            Text("позже")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                        .foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)
        }
    }

    private func enabled(_ provider: ProviderID) -> Binding<Bool> {
        Binding(
            get: { !model.value.disabledProviders.contains(provider) },
            set: { on in
                model.update {
                    if on { $0.disabledProviders.remove(provider) }
                    else { $0.disabledProviders.insert(provider) }
                }
            }
        )
    }

    private func chooseCodexRoot() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Выбрать"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.update { $0.codexRoot = url.path }
    }
}
```

- [ ] **Step 2: Учесть настройки при сборке опроса**

В `App/AppModel.swift` заменить `rebuildPoller()`:

```swift
    private func rebuildPoller() async {
        let refs = await store.knownRefs()
            .filter { !preferences.hiddenAccounts.contains($0.id) }

        var providers: [any UsageProvider] = []
        if !preferences.disabledProviders.contains(.claude) {
            providers.append(ClaudeUsageProvider(tokens: store, knownAccounts: refs))
        }
        if !preferences.disabledProviders.contains(.codex) {
            let root = preferences.codexRoot.map(URL.init(fileURLWithPath:))
            providers.append(CodexUsageProvider(
                fileSystem: root.map { RealCodexFileSystem(root: $0) } ?? RealCodexFileSystem()
            ))
        }
        poller = UsagePoller(providers: providers)
    }
```

- [ ] **Step 3: Тест на фильтрацию скрытых аккаунтов**

Дописать в `Packages/Core/Tests/MonitoringTests/UsagePollerTests.swift`:

```swift
@Test func pollerWithoutProvidersReturnsNothing() async {
    let result = await UsagePoller(providers: []).refresh()
    #expect(result.isEmpty)
}
```

- [ ] **Step 4: Проверить**

Run: `cd Packages/Core && swift test --filter UsagePollerTests`
Expected: PASS, 8 тестов.

Run: `make build`
Expected: `BUILD SUCCEEDED`.

Проверить вручную: выключить Codex — его строка пропадает из окна; выключить оба
сервиса — окно показывает «Аккаунты не найдены», приложение не падает.

- [ ] **Step 5: Commit**

```bash
git add App Packages/Core
git commit -m "Раздел «Сервисы»: включение провайдеров и путь к каталогу Codex"
```

---

### Task 9: Раздел «Аккаунты»

**Files:**
- Modify: `App/Settings/AccountsPane.swift`
- Modify: `Packages/Core/Sources/Credentials/CredentialStore.swift`
- Test: `Packages/Core/Tests/CredentialsTests/CredentialStoreTests.swift`

**Interfaces:**
- Consumes: `CredentialStore` из прототипа; `PreferencesModel` из Task 4.
- Produces:
  - `enum AccountState: Sendable` — `.activeInCLI`, `.refreshed`, `.needsLogin`
  - `CredentialStore.accountStates() async -> [(account: StoredAccount, state: AccountState)]`
  - `CredentialStore.forget(handle: String) async throws`

- [ ] **Step 1: Написать падающий тест**

Дописать в `Packages/Core/Tests/CredentialsTests/CredentialStoreTests.swift`:

```swift
@Test func statesDistinguishActiveFromRefreshed() async throws {
    let keychain = MemoryKeychain([
        CredentialStore.cliService: cliCredentials(token: "tok-A", refresh: "refresh-A")
    ])
    let store = await makeStore(keychain)
    try await store.syncWithCLI(profileUUID: "u-1", displayName: "a@b.c")
    await keychain.seed(cliCredentials(token: "tok-B", refresh: "refresh-B"),
                        service: CredentialStore.cliService)
    try await store.syncWithCLI(profileUUID: "u-2", displayName: "b@b.c")

    let states = await store.accountStates()
    let byHandle = Dictionary(uniqueKeysWithValues: states.map { ($0.account.handle, $0.state) })
    #expect(byHandle["u-2"] == .activeInCLI)
    #expect(byHandle["u-1"] == .refreshed)
}

@Test func accountWithoutCopyNeedsLogin() async throws {
    // Keychain CLI пуст — копию refresh-токена снять было неоткуда.
    let store = await makeStore(MemoryKeychain())
    try await store.syncWithCLI(profileUUID: "u-9", displayName: "c@b.c")

    let states = await store.accountStates()
    #expect(states.first?.state == .needsLogin)
}

@Test func forgetRemovesAccountButNotTheCLIEntry() async throws {
    let keychain = MemoryKeychain([CredentialStore.cliService: cliCredentials(token: "t")])
    let store = await makeStore(keychain)
    try await store.syncWithCLI(profileUUID: "u-1", displayName: "a@b.c")
    try await store.forget(handle: "u-1")

    #expect(await store.knownRefs().isEmpty)
    // Вход в CLI не тронут — это главное обещание кнопки «Забыть».
    #expect(await keychain.writeCount(for: CredentialStore.cliService) == 0)
}

@Test func forgettingUnknownAccountIsHarmless() async throws {
    let store = await makeStore(MemoryKeychain())
    try await store.forget(handle: "нет такого")
    #expect(await store.knownRefs().isEmpty)
}
```

- [ ] **Step 2: Убедиться, что тест падает**

Run: `cd Packages/Core && swift test --filter CredentialStoreTests`
Expected: FAIL — нет `accountStates` и `forget`.

- [ ] **Step 3: Реализовать**

Дописать в `Packages/Core/Sources/Credentials/CredentialStore.swift` внутри
`CredentialStore`:

```swift
    /// Как приложение добывает токен для этого аккаунта прямо сейчас.
    /// Вычисляется, а не хранится: состояние меняется от того, под кем
    /// пользователь залогинен в CLI, а не от наших записей.
    public enum AccountState: Sendable, Hashable {
        case activeInCLI   // токен читается из Keychain CLI, не продлевается
        case refreshed     // живёт на своей копии refresh-токена
        case needsLogin    // копии нет, продлить нечем
    }

    public func accountStates() async -> [(account: StoredAccount, state: AccountState)] {
        let activeRefresh = try? await currentCLIRefreshToken()

        return accounts.map { account in
            let state: AccountState
            if let activeRefresh, account.refreshToken == activeRefresh {
                state = .activeInCLI
            } else if account.refreshToken != nil {
                state = .refreshed
            } else {
                state = .needsLogin
            }
            return (account, state)
        }
    }

    /// Забывает аккаунт вместе с копией токена.
    /// Элемент Keychain, принадлежащий Claude Code, не трогается — вход в CLI
    /// остаётся рабочим, и это обещано пользователю в интерфейсе.
    public func forget(handle: String) async throws {
        accounts.removeAll { $0.handle == handle }
        try await persist()
    }
```

- [ ] **Step 4: Убедиться, что тесты проходят**

Run: `cd Packages/Core && swift test --filter CredentialStoreTests`
Expected: PASS, 14 тестов.

- [ ] **Step 5: Наполнить раздел**

Заменить содержимое `App/Settings/AccountsPane.swift`:

```swift
import SwiftUI
import ProviderKit
import Credentials
import Preferences

struct AccountsPane: View {
    @ObservedObject var model: PreferencesModel
    @ObservedObject var appModel: AppModel

    @State private var rows: [AccountRow] = []
    @State private var pendingForget: AccountRow?

    struct AccountRow: Identifiable, Hashable {
        let id: String
        let handle: String
        let displayName: String
        let state: CredentialStore.AccountState
    }

    var body: some View {
        Pane(title: "Аккаунты",
             subtitle: "Появляются сами, когда вы заходите в них через claude /login. Здесь можно скрыть аккаунт из окна или забыть совсем.") {
            VStack(alignment: .leading, spacing: 12) {
                if rows.isEmpty {
                    Text("Аккаунтов пока нет.")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                } else {
                    ForEach(rows) { row in
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(row.displayName)
                                    .font(.system(size: 12.5, weight: .medium))
                                Text(caption(for: row.state))
                                    .font(.system(size: 11)).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(badge(for: row.state))
                                .font(.system(size: 10, weight: .semibold))
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(tint(for: row.state).opacity(0.16),
                                            in: RoundedRectangle(cornerRadius: 4))
                                .foregroundStyle(tint(for: row.state))
                            Toggle("", isOn: visible(row))
                                .labelsHidden()
                            Button("Забыть…") { pendingForget = row }
                        }
                        .padding(.vertical, 4)
                        Divider()
                    }
                }

                Text("«Активен в CLI» — токен читается напрямую и не продлевается, иначе claude разлогинится. «Продлевается» — приложение держит свою копию refresh-токена.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .task { await reload() }
        .alert(item: $pendingForget) { row in
            Alert(
                title: Text("Забыть \(row.displayName)?"),
                message: Text("Копия токена будет удалена. Вход в Claude Code это не затронет."),
                primaryButton: .destructive(Text("Забыть")) {
                    Task { await forget(row) }
                },
                secondaryButton: .cancel(Text("Отмена"))
            )
        }
    }

    private func reload() async {
        rows = await appModel.accountRows()
    }

    private func forget(_ row: AccountRow) async {
        await appModel.forgetAccount(handle: row.handle)
        await reload()
    }

    private func visible(_ row: AccountRow) -> Binding<Bool> {
        Binding(
            get: { !model.value.hiddenAccounts.contains(row.id) },
            set: { on in
                model.update {
                    if on { $0.hiddenAccounts.remove(row.id) }
                    else { $0.hiddenAccounts.insert(row.id) }
                }
            }
        )
    }

    private func badge(for state: CredentialStore.AccountState) -> String {
        switch state {
        case .activeInCLI: "активен в CLI"
        case .refreshed:   "продлевается"
        case .needsLogin:  "нужен вход"
        }
    }

    private func caption(for state: CredentialStore.AccountState) -> String {
        switch state {
        case .activeInCLI: "Claude · токен читается из Claude Code"
        case .refreshed:   "Claude · своя копия refresh-токена"
        case .needsLogin:  "Claude · продлить нечем"
        }
    }

    private func tint(for state: CredentialStore.AccountState) -> Color {
        switch state {
        case .activeInCLI: .green
        case .refreshed:   .blue
        case .needsLogin:  .red
        }
    }
}
```

- [ ] **Step 6: Добавить мост в AppModel**

В `App/AppModel.swift` дописать:

```swift
    func accountRows() async -> [AccountsPane.AccountRow] {
        await store.accountStates().map { item in
            AccountsPane.AccountRow(
                id: item.account.id,
                handle: item.account.handle,
                displayName: item.account.displayName,
                state: item.state
            )
        }
    }

    func forgetAccount(handle: String) async {
        try? await store.forget(handle: handle)
        await refresh()
    }
```

- [ ] **Step 7: Собрать и проверить**

Run: `make build`
Expected: `BUILD SUCCEEDED`.

Run: `make run`, открыть «Настройки… → Аккаунты».
Expected: аккаунт показан с бейджем «активен в CLI»; выключатель убирает его из
окна лимитов; «Забыть…» спрашивает подтверждение и после согласия убирает строку,
а `claude --version` продолжает работать.

- [ ] **Step 8: Commit**

```bash
git add App Packages/Core
git commit -m "Раздел «Аккаунты»: состояния, скрытие и забывание"
```

---

### Task 10: Вход через браузер

**Files:**
- Create: `Packages/Core/Sources/ClaudeProvider/OAuthEndpoints.swift`
- Create: `Packages/Core/Sources/ClaudeProvider/PKCE.swift`
- Create: `Packages/Core/Sources/ClaudeProvider/OAuthLogin.swift`
- Modify: `Packages/Core/Sources/Credentials/CredentialStore.swift`
- Create: `App/LoginController.swift`
- Modify: `App/Settings/AccountsPane.swift`
- Test: `Packages/Core/Tests/ClaudeProviderTests/PKCETests.swift`
- Test: `Packages/Core/Tests/ClaudeProviderTests/OAuthLoginTests.swift`

**Interfaces:**
- Consumes: `HTTPClient` из прототипа; `ClaudeProfileResponse` из прототипа.
- Produces:
  - `enum OAuthEndpoints` — `authorize`, `token`, `manualRedirect`, `clientID`, `scope`
  - `struct PKCEPair: Sendable` — `verifier`, `challenge`; `static func generate() -> PKCEPair`
  - `struct OAuthLogin: Sendable` — `init(http:)`, `func authorizationURL(redirectURI:pkce:state:manual:) -> URL`, `func exchange(code:verifier:redirectURI:) async throws -> RefreshedTokens`
  - `CredentialStore.addLoggedInAccount(uuid:displayName:refreshToken:) async throws`

Адреса взяты из констант установленного Claude Code и проверены живьём
2026-08-30: запрос авторизации отвечает `200` и отдаёт страницу входа.
**Прежний адрес `claude.ai/oauth/authorize` отвечает `403` — домены сменились**,
поэтому здесь же `AnthropicTokenRefresher` переводится на `platform.claude.com`.

- [ ] **Step 1: Написать падающий тест на PKCE**

Создать `Packages/Core/Tests/ClaudeProviderTests/PKCETests.swift`:

```swift
import Testing
import Foundation
import CryptoKit
@testable import ClaudeProvider

@Test func challengeIsBase64URLOfSHA256OfVerifier() {
    let pair = PKCEPair.generate()
    let expected = Data(SHA256.hash(data: Data(pair.verifier.utf8)))
        .base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
    #expect(pair.challenge == expected)
}

@Test func encodingIsURLSafeAndUnpadded() {
    for _ in 0..<50 {
        let pair = PKCEPair.generate()
        for value in [pair.verifier, pair.challenge] {
            #expect(value.contains("+") == false)
            #expect(value.contains("/") == false)
            #expect(value.contains("=") == false)
        }
    }
}

@Test func verifierIsLongEnoughForTheSpec() {
    // RFC 7636 требует от 43 до 128 символов.
    let pair = PKCEPair.generate()
    #expect(pair.verifier.count >= 43)
    #expect(pair.verifier.count <= 128)
}

@Test func eachPairIsDifferent() {
    let first = PKCEPair.generate()
    let second = PKCEPair.generate()
    #expect(first.verifier != second.verifier)
}
```

- [ ] **Step 2: Убедиться, что тест падает**

Run: `cd Packages/Core && swift test --filter PKCETests`
Expected: FAIL, `cannot find 'PKCEPair' in scope`.

- [ ] **Step 3: Реализовать адреса и PKCE**

Создать `Packages/Core/Sources/ClaudeProvider/OAuthEndpoints.swift`:

```swift
import Foundation

/// Адреса входа, взятые из констант установленного Claude Code.
///
/// Домены сменились: `claude.ai/oauth/authorize` отвечает `403`, действующий
/// адрес — `platform.claude.com`. Держим их одним местом, чтобы следующая
/// смена правилась в одной точке.
public enum OAuthEndpoints {
    public static let authorize = URL(string: "https://platform.claude.com/oauth/authorize")!
    public static let token = URL(string: "https://platform.claude.com/v1/oauth/token")!
    public static let manualRedirect = "https://platform.claude.com/oauth/code/callback"
    public static let clientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
    public static let scope = "org:create_api_key user:profile user:inference"
}
```

Создать `Packages/Core/Sources/ClaudeProvider/PKCE.swift`:

```swift
import Foundation
import CryptoKit

/// Пара для PKCE (RFC 7636). Верификатор остаётся у приложения, вызов уходит
/// в браузер только в виде challenge — поэтому перехват адреса ничего не даёт.
public struct PKCEPair: Sendable, Hashable {
    public let verifier: String
    public let challenge: String

    public static func generate() -> PKCEPair {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let verifier = base64URL(Data(bytes))
        let digest = Data(SHA256.hash(data: Data(verifier.utf8)))
        return PKCEPair(verifier: verifier, challenge: base64URL(digest))
    }

    /// base64url без набивки: `+` и `/` недопустимы в параметрах адреса,
    /// а `=` спецификация запрещает.
    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
```

- [ ] **Step 4: Убедиться, что тесты PKCE проходят**

Run: `cd Packages/Core && swift test --filter PKCETests`
Expected: PASS, 4 теста.

- [ ] **Step 5: Написать падающий тест на вход**

Создать `Packages/Core/Tests/ClaudeProviderTests/OAuthLoginTests.swift`:

```swift
import Testing
import Foundation
import ProviderKit
@testable import ClaudeProvider

private struct StubHTTP: HTTPClient {
    var response: (Data, Int)
    var seenBody: @Sendable (Data) -> Void = { _ in }

    func get(_ url: URL, headers: [String: String]) async throws -> (Data, Int) {
        (Data(), 404)
    }
    func post(_ url: URL, headers: [String: String], body: Data) async throws -> (Data, Int) {
        seenBody(body)
        return response
    }
}

private func d(_ s: String) -> Data { s.data(using: .utf8)! }

@Test func authorizationURLCarriesEveryRequiredParameter() {
    let login = OAuthLogin(http: StubHTTP(response: (Data(), 200)))
    let pkce = PKCEPair.generate()
    let url = login.authorizationURL(
        redirectURI: "http://localhost:54545/callback", pkce: pkce,
        state: "st-1", manual: false
    )
    let items = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems ?? []
    let byName = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })

    #expect(url.host == "platform.claude.com")
    #expect(byName["client_id"] == OAuthEndpoints.clientID)
    #expect(byName["response_type"] == "code")
    #expect(byName["redirect_uri"] == "http://localhost:54545/callback")
    #expect(byName["code_challenge"] == pkce.challenge)
    #expect(byName["code_challenge_method"] == "S256")
    #expect(byName["state"] == "st-1")
    #expect(byName["scope"] == OAuthEndpoints.scope)
    #expect(byName["code"] == nil)   // не ручной режим
}

@Test func manualModeAddsCodeFlagAndItsOwnRedirect() {
    let login = OAuthLogin(http: StubHTTP(response: (Data(), 200)))
    let url = login.authorizationURL(
        redirectURI: OAuthEndpoints.manualRedirect, pkce: .generate(),
        state: "st", manual: true
    )
    let byName = Dictionary(uniqueKeysWithValues:
        (URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems ?? [])
            .map { ($0.name, $0.value ?? "") })
    #expect(byName["code"] == "true")
    #expect(byName["redirect_uri"] == OAuthEndpoints.manualRedirect)
}

@Test func exchangeReturnsBothTokens() async throws {
    let http = StubHTTP(response: (d(#"{"access_token":"at","refresh_token":"rt"}"#), 200))
    let tokens = try await OAuthLogin(http: http).exchange(
        code: "c", verifier: "v", redirectURI: "http://localhost:1/callback"
    )
    #expect(tokens.accessToken == "at")
    #expect(tokens.refreshToken == "rt")
}

@Test func exchangeSendsVerifierAndGrantType() async throws {
    let box = Box()
    var http = StubHTTP(response: (d(#"{"access_token":"at"}"#), 200))
    http.seenBody = { box.set($0) }
    _ = try await OAuthLogin(http: http).exchange(
        code: "the-code", verifier: "the-verifier", redirectURI: "http://localhost:1/callback"
    )
    let sent = try #require(box.value)
    let json = try JSONSerialization.jsonObject(with: sent) as? [String: Any]
    #expect(json?["grant_type"] as? String == "authorization_code")
    #expect(json?["code"] as? String == "the-code")
    #expect(json?["code_verifier"] as? String == "the-verifier")
    #expect(json?["client_id"] as? String == OAuthEndpoints.clientID)
}

@Test func serverErrorBecomesNeedsLogin() async {
    let http = StubHTTP(response: (d(#"{"error":"invalid_grant"}"#), 400))
    await #expect(throws: ProviderFailure.self) {
        _ = try await OAuthLogin(http: http).exchange(
            code: "c", verifier: "v", redirectURI: "http://localhost:1/callback"
        )
    }
}

@Test func errorMessageNeverLeaksTheVerifier() async {
    let http = StubHTTP(response: (d(#"{"error":"invalid_grant"}"#), 400))
    do {
        _ = try await OAuthLogin(http: http).exchange(
            code: "c", verifier: "SECRET-VERIFIER", redirectURI: "http://localhost:1/callback"
        )
        Issue.record("ожидалась ошибка")
    } catch let failure as ProviderFailure {
        #expect(failure.message.contains("SECRET") == false)
    } catch {
        Issue.record("другой тип ошибки")
    }
}

/// Тестовая коробка: замыкание `@Sendable` не может писать в `var` напрямую.
private final class Box: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Data?
    var value: Data? { lock.lock(); defer { lock.unlock() }; return stored }
    func set(_ data: Data) { lock.lock(); stored = data; lock.unlock() }
}
```

- [ ] **Step 6: Убедиться, что тест падает**

Run: `cd Packages/Core && swift test --filter OAuthLoginTests`
Expected: FAIL, `cannot find 'OAuthLogin' in scope`.

- [ ] **Step 7: Реализовать вход**

Создать `Packages/Core/Sources/ClaudeProvider/OAuthLogin.swift`:

```swift
import Foundation
import ProviderKit

public struct OAuthLogin: Sendable {
    private let http: any HTTPClient

    public init(http: any HTTPClient = URLSessionHTTPClient()) { self.http = http }

    /// Адрес страницы входа.
    /// `manual: true` добавляет `code=true` — тогда сервер показывает код на
    /// странице вместо возврата на `redirect_uri`. Это запасной путь на случай,
    /// если возврат на localhost не сработает.
    public func authorizationURL(
        redirectURI: String, pkce: PKCEPair, state: String, manual: Bool
    ) -> URL {
        var components = URLComponents(
            url: OAuthEndpoints.authorize, resolvingAgainstBaseURL: false
        )!
        var items = [
            URLQueryItem(name: "client_id", value: OAuthEndpoints.clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: OAuthEndpoints.scope),
            URLQueryItem(name: "code_challenge", value: pkce.challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
        ]
        if manual { items.insert(URLQueryItem(name: "code", value: "true"), at: 0) }
        components.queryItems = items
        return components.url!
    }

    public func exchange(
        code: String, verifier: String, redirectURI: String
    ) async throws -> RefreshedTokens {
        let body = try JSONSerialization.data(withJSONObject: [
            "grant_type": "authorization_code",
            "code": code,
            "code_verifier": verifier,
            "client_id": OAuthEndpoints.clientID,
            "redirect_uri": redirectURI,
        ])

        let (data, status) = try await http.post(
            OAuthEndpoints.token, headers: ["Content-Type": "application/json"], body: body
        )
        guard status == 200,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let access = root["access_token"] as? String
        else {
            // Ответ сервера наружу не пересказываем: в него мог попасть код или
            // верификатор, а сообщение уходит в интерфейс.
            throw ProviderFailure(kind: .needsLogin, message: "Не удалось завершить вход")
        }
        return RefreshedTokens(
            accessToken: access, refreshToken: root["refresh_token"] as? String
        )
    }
}
```

`RefreshedTokens` объявлен в модуле `Credentials`, а `OAuthLogin` живёт в
`ClaudeProvider`, который от него не зависит. Поэтому переносим тип: вырезать
объявление `RefreshedTokens` из
`Packages/Core/Sources/Credentials/CredentialStore.swift` и вставить в
`Packages/Core/Sources/ClaudeProvider/OAuthLogin.swift` перед `OAuthLogin`:

```swift
public struct RefreshedTokens: Sendable, Hashable {
    public let accessToken: String
    public let refreshToken: String?

    public init(accessToken: String, refreshToken: String?) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
    }
}
```

`Credentials` уже импортирует `ClaudeProvider`, поэтому больше ничего не нужно.

- [ ] **Step 8: Перевести продление на действующий адрес**

В `Packages/Core/Sources/Credentials/CredentialStore.swift` в
`AnthropicTokenRefresher` заменить константы на общие:

```swift
public struct AnthropicTokenRefresher: TokenRefreshing {
    private let http: any HTTPClient

    public init(http: any HTTPClient = URLSessionHTTPClient()) { self.http = http }

    public func refresh(refreshToken: String) async throws -> RefreshedTokens {
        let body = try JSONSerialization.data(withJSONObject: [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": OAuthEndpoints.clientID,
        ])

        let (data, code) = try await http.post(
            OAuthEndpoints.token, headers: ["Content-Type": "application/json"], body: body
        )
        guard code == 200,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let access = root["access_token"] as? String
        else {
            throw ProviderFailure(kind: .needsLogin, message: "Нужен вход в аккаунт")
        }
        return RefreshedTokens(
            accessToken: access, refreshToken: root["refresh_token"] as? String
        )
    }
}
```

- [ ] **Step 9: Добавить сохранение вошедшего аккаунта**

Дописать в `CredentialStore`:

```swift
    /// Сохраняет аккаунт, добавленный входом через браузер.
    /// У него своя пара токенов, не связанная с сессией CLI, поэтому он сразу
    /// попадает в состояние «продлевается».
    public func addLoggedInAccount(
        uuid: String, displayName: String, refreshToken: String
    ) async throws {
        accounts.removeAll { $0.handle == uuid }
        accounts.append(StoredAccount(
            id: "claude/\(uuid)", handle: uuid,
            displayName: displayName, refreshToken: refreshToken
        ))
        try await persist()
    }
```

- [ ] **Step 10: Убедиться, что весь пакет проходит**

Run: `cd Packages/Core && swift test`
Expected: PASS, все тесты.

- [ ] **Step 11: Реализовать возврат из браузера**

Создать `App/LoginController.swift`:

```swift
import Foundation
import AppKit
import Network
import ProviderKit
import ClaudeProvider
import Credentials

/// Проводит вход через браузер: поднимает слушатель на свободном порту,
/// открывает страницу входа и ждёт возврата с кодом.
@MainActor
final class LoginController: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var message: String?
    /// Адрес показывается, если возврат не сработал и нужен ручной ввод кода.
    @Published private(set) var manualCodeExpected = false

    private let login = OAuthLogin()
    private let store: CredentialStore
    private var listener: NWListener?
    private var pkce: PKCEPair?
    private var state: String?
    private var redirectURI: String?
    private var timeout: Task<Void, Never>?

    init(store: CredentialStore) { self.store = store }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        message = nil
        manualCodeExpected = false

        let pair = PKCEPair.generate()
        let st = UUID().uuidString
        pkce = pair
        state = st

        do {
            let port = try startListener()
            let uri = "http://localhost:\(port)/callback"
            redirectURI = uri
            NSWorkspace.shared.open(
                login.authorizationURL(redirectURI: uri, pkce: pair, state: st, manual: false)
            )
            armTimeout()
        } catch {
            // Порт занять не удалось — уходим на ручной ввод кода.
            fallBackToManual(pair: pair, state: st)
        }
    }

    /// Ручной путь: код скопирован со страницы и вставлен в поле.
    func submit(code: String) async {
        guard let pair = pkce, let uri = redirectURI else { return }
        await finish(code: code, verifier: pair.verifier, redirectURI: uri)
    }

    func cancel() {
        stopListener()
        isRunning = false
        manualCodeExpected = false
        message = nil
    }

    // MARK: - внутреннее

    private func startListener() throws -> UInt16 {
        let listener = try NWListener(using: .tcp, on: .any)
        self.listener = listener

        listener.newConnectionHandler = { [weak self] connection in
            connection.start(queue: .main)
            connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) {
                data, _, _, _ in
                guard let data, let request = String(data: data, encoding: .utf8) else { return }
                Task { @MainActor in self?.handle(request: request, on: connection) }
            }
        }
        listener.start(queue: .main)

        // Порт назначается системой асинхронно; ждём его появления.
        var attempts = 0
        while listener.port == nil && attempts < 200 {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
            attempts += 1
        }
        guard let port = listener.port?.rawValue else {
            throw ProviderFailure(kind: .network, message: "Не удалось занять порт")
        }
        return port
    }

    private func handle(request: String, on connection: NWConnection) {
        defer { connection.cancel() }

        // Первая строка вида: GET /callback?code=...&state=... HTTP/1.1
        guard let line = request.split(separator: "\r\n").first,
              let path = line.split(separator: " ").dropFirst().first,
              let components = URLComponents(string: "http://localhost\(path)")
        else { return }

        let items = components.queryItems ?? []
        let code = items.first { $0.name == "code" }?.value
        let returned = items.first { $0.name == "state" }?.value

        respond(on: connection, ok: code != nil)

        // Чужой state означает подставной редирект — такой код не берём.
        guard let code, returned == state, let pair = pkce, let uri = redirectURI else {
            message = "Возврат из браузера не распознан."
            isRunning = false
            stopListener()
            return
        }

        stopListener()
        Task { await finish(code: code, verifier: pair.verifier, redirectURI: uri) }
    }

    private func respond(on connection: NWConnection, ok: Bool) {
        let text = ok ? "Готово. Можно вернуться в приложение." : "Что-то пошло не так."
        let body = "<html><meta charset=\"utf-8\"><body style=\"font-family:-apple-system;padding:40px\">\(text)</body></html>"
        let response = """
        HTTP/1.1 200 OK\r
        Content-Type: text/html; charset=utf-8\r
        Content-Length: \(body.utf8.count)\r
        Connection: close\r
        \r
        \(body)
        """
        connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in })
    }

    private func finish(code: String, verifier: String, redirectURI: String) async {
        do {
            let tokens = try await login.exchange(
                code: code, verifier: verifier, redirectURI: redirectURI
            )
            guard let refresh = tokens.refreshToken else {
                throw ProviderFailure(kind: .needsLogin, message: "Сервис не вернул refresh-токен")
            }

            let http = URLSessionHTTPClient()
            let headers = [
                "Authorization": "Bearer \(tokens.accessToken)",
                "anthropic-beta": "oauth-2025-04-20",
                "User-Agent": "claude-cli/2.0.0 (external, cli)",
            ]
            let url = URL(string: "https://api.anthropic.com/api/oauth/profile")!
            let (data, status) = try await http.get(url, headers: headers)
            guard status == 200, let profile = try? ClaudeProfileResponse.parse(data) else {
                throw ProviderFailure(kind: .needsLogin, message: "Не удалось прочитать профиль")
            }

            try await store.addLoggedInAccount(
                uuid: profile.uuid, displayName: profile.displayName, refreshToken: refresh
            )
            message = "Аккаунт \(profile.displayName) добавлен."
        } catch let failure as ProviderFailure {
            message = failure.message
        } catch {
            message = "Не удалось завершить вход."
        }
        isRunning = false
        manualCodeExpected = false
        timeout?.cancel()
    }

    private func fallBackToManual(pair: PKCEPair, state: String) {
        redirectURI = OAuthEndpoints.manualRedirect
        manualCodeExpected = true
        message = "Скопируйте код со страницы и вставьте его ниже."
        NSWorkspace.shared.open(login.authorizationURL(
            redirectURI: OAuthEndpoints.manualRedirect, pkce: pair, state: state, manual: true
        ))
    }

    /// Слушатель не должен висеть бесконечно, если человек закрыл вкладку.
    private func armTimeout() {
        timeout?.cancel()
        timeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(120))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self, self.isRunning else { return }
                self.stopListener()
                self.isRunning = false
                self.message = "Вход не завершён за две минуты."
            }
        }
    }

    private func stopListener() {
        listener?.cancel()
        listener = nil
        timeout?.cancel()
    }
}
```

- [ ] **Step 12: Добавить кнопку в раздел «Аккаунты»**

В `App/Settings/AccountsPane.swift` добавить состояние и кнопку. После
`@State private var pendingForget: AccountRow?` вставить:

```swift
    @StateObject private var loginController: LoginController
    @State private var manualCode = ""

    init(model: PreferencesModel, appModel: AppModel) {
        self.model = model
        self.appModel = appModel
        _loginController = StateObject(wrappedValue: LoginController(store: appModel.store))
    }
```

В `VStack` после списка аккаунтов, перед пояснением, вставить:

```swift
                HStack(spacing: 8) {
                    Button("Добавить аккаунт…") { loginController.start() }
                        .disabled(loginController.isRunning)
                    if loginController.isRunning {
                        ProgressView().controlSize(.small)
                        Button("Отмена") { loginController.cancel() }
                    }
                    Spacer()
                }

                if loginController.manualCodeExpected {
                    HStack(spacing: 6) {
                        TextField("Код со страницы", text: $manualCode)
                            .frame(width: 220)
                        Button("Готово") {
                            Task {
                                await loginController.submit(code: manualCode)
                                manualCode = ""
                                await reload()
                            }
                        }
                        .disabled(manualCode.isEmpty)
                    }
                }

                if let message = loginController.message {
                    Text(message)
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
```

И в `.task` добавить перезагрузку после успешного входа:

```swift
        .onChange(of: loginController.message) { _, _ in
            Task { await reload() }
        }
```

- [ ] **Step 13: Открыть доступ к хранилищу**

В `App/AppModel.swift` заменить `private let store: CredentialStore` на:

```swift
    /// Раздел «Аккаунты» создаёт свой `LoginController` поверх того же хранилища.
    let store: CredentialStore
```

- [ ] **Step 14: Собрать и проверить**

Run: `make build`
Expected: `BUILD SUCCEEDED`.

Run: `make run`, открыть «Настройки… → Аккаунты → Добавить аккаунт…».
Expected: открывается браузер со страницей входа Claude; после входа браузер
возвращается на localhost и показывает «Готово», а в списке появляется новый
аккаунт с бейджем «продлевается».

Если браузер показывает код вместо возврата — сработал запасной путь: скопировать
код в поле «Код со страницы» и нажать «Готово». Результат тот же.

- [ ] **Step 15: Commit**

```bash
git add App Packages/Core
git commit -m "Вход в аккаунт Claude через браузер из настроек"
```

---

### Task 11: Раздел «О программе», альтернативные компоновки строки

**Files:**
- Modify: `App/Settings/AboutPane.swift`
- Modify: `App/AccountRowView.swift`

**Interfaces:**
- Consumes: `RowLayout` из Task 1; `CredentialStore.forget` из Task 9.
- Produces: `AppModel.forgetAllAccounts() async`.

- [ ] **Step 1: Наполнить раздел «О программе»**

Заменить содержимое `App/Settings/AboutPane.swift`:

```swift
import SwiftUI
import AppKit
import Credentials
import Preferences

struct AboutPane: View {
    @ObservedObject var model: PreferencesModel
    @ObservedObject var appModel: AppModel

    @State private var confirmForgetAll = false

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "\(short) (сборка \(build))"
    }

    var body: some View {
        Pane(title: "О программе и данные",
             subtitle: "Что приложение хранит и как это убрать.") {
            Form {
                Section {
                    LabeledContent("Версия", value: version)
                    LabeledContent("Учётные данные",
                                   value: "Keychain · \(CredentialStore.ownService)")
                    LabeledContent("Настройки",
                                   value: "~/Library/Preferences/dev.example.StatusChecker.plist")
                }

                Section {
                    Button("Забыть все аккаунты…", role: .destructive) {
                        confirmForgetAll = true
                    }
                    Text("Удалит только копии токенов, которые хранит это приложение. Вход в Claude Code это не затронет.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .formStyle(.grouped)
        }
        .confirmationDialog(
            "Забыть все аккаунты?", isPresented: $confirmForgetAll, titleVisibility: .visible
        ) {
            Button("Забыть все", role: .destructive) {
                Task { await appModel.forgetAllAccounts() }
            }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Копии токенов будут удалены. Вход в Claude Code останется рабочим.")
        }
    }
}
```

- [ ] **Step 2: Добавить метод в AppModel**

В `App/AppModel.swift` дописать:

```swift
    func forgetAllAccounts() async {
        for ref in await store.knownRefs() {
            try? await store.forget(handle: ref.handle)
        }
        await refresh()
    }
```

- [ ] **Step 3: Реализовать компоновки B и C**

В `App/AccountRowView.swift` заменить `body`:

```swift
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            header
            if let failure = snapshot.failure {
                Text(failure.message)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            } else {
                switch layout {
                case .twoWindows: ForEach(snapshot.windows) { meter(for: $0) }
                case .compact:    compactMeter
                case .rings:      ringsRow
                }
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 10)
    }

    /// Одна строка: крупно недельный процент, пятичасовое окно — засечкой.
    private var compactMeter: some View {
        let weekly = snapshot.windows.first { $0.id == "weekly" } ?? snapshot.windows.first
        let session = snapshot.windows.first { $0.id == "session" }

        return VStack(alignment: .leading, spacing: 5) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.11))
                    if let weekly {
                        Capsule()
                            .fill(weekly.severity.tint)
                            .frame(width: max(2, geo.size.width * weekly.percent / 100))
                    }
                    if let session {
                        Rectangle()
                            .fill(.primary.opacity(0.55))
                            .frame(width: 1.5, height: 7)
                            .offset(x: geo.size.width * session.percent / 100)
                    }
                }
            }
            .frame(height: 4)

            HStack(spacing: 6) {
                if let weekly {
                    Text("нед \(Int(weekly.percent.rounded()))%")
                    Text(weekly.remaining(from: now).map(formatRemaining) ?? "—")
                }
                if let session {
                    Text("· 5ч \(Int(session.percent.rounded()))%")
                }
            }
            .font(.system(size: 10.5))
            .monospacedDigit()
            .foregroundStyle(.tertiary)
        }
    }

    /// Кольца: процент читается цифрой, без сравнения длин полос.
    private var ringsRow: some View {
        HStack(spacing: 10) {
            ForEach(snapshot.windows) { window in
                VStack(spacing: 3) {
                    ZStack {
                        Circle()
                            .stroke(.white.opacity(0.11), lineWidth: 3.4)
                        Circle()
                            .trim(from: 0, to: max(0.01, window.percent / 100))
                            .stroke(window.severity.tint,
                                    style: StrokeStyle(lineWidth: 3.4, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        Text("\(Int(window.percent.rounded()))")
                            .font(.system(size: 9.5, weight: .semibold))
                            .monospacedDigit()
                    }
                    .frame(width: 34, height: 34)
                    Text(window.label)
                        .font(.system(size: 8.5))
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()
            if let worst = snapshot.peakWindow {
                Text(worst.remaining(from: now).map(formatRemaining) ?? "—")
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
            }
        }
    }
```

- [ ] **Step 4: Собрать и проверить**

Run: `make build`
Expected: `BUILD SUCCEEDED`.

Run: `make run`, в «Внешний вид» переключить компоновку между «Два окна»,
«Одна строка» и «Кольца».
Expected: окно перерисовывается, все три вида читаемы, ничего не обрезается.

- [ ] **Step 5: Commit**

```bash
git add App
git commit -m "Раздел «О программе» и альтернативные компоновки строки"
```

---

### Task 12: Горячие клавиши

**Files:**
- Create: `App/HotKeys.swift`
- Modify: `App/Settings/UpdatesPane.swift`
- Modify: `Packages/Core/Sources/Preferences/Preferences.swift`
- Test: `Packages/Core/Tests/PreferencesTests/HotKeyTests.swift`

**Interfaces:**
- Consumes: `Preferences` из Task 1.
- Produces:
  - `struct HotKeyCombo: Codable, Sendable, Hashable` — `keyCode: UInt32`, `modifiers: UInt32`, `displayString: String`
  - `Preferences.openWindowHotKey: HotKeyCombo?`, `Preferences.refreshHotKey: HotKeyCombo?`
  - `final class HotKeyCenter` — `register(_ combo: HotKeyCombo?, id: UInt32, action: @escaping () -> Void)`, `unregisterAll()`

Это единственная часть плана, требующая C-API: глобальное сочетание без прав
Accessibility даёт только Carbon `RegisterEventHotKey`. Задача идёт последней —
если работу нужно остановить раньше, всё остальное уже работает.

- [ ] **Step 1: Написать падающий тест на описание сочетания**

Создать `Packages/Core/Tests/PreferencesTests/HotKeyTests.swift`:

```swift
import Testing
import Foundation
@testable import Preferences

@Test func describesModifiersInAppleOrder() {
    // Порядок значков в macOS: ⌃ ⌥ ⇧ ⌘
    let combo = HotKeyCombo(keyCode: 37, modifiers: HotKeyCombo.command | HotKeyCombo.option)
    #expect(combo.displayString == "⌥⌘L")
}

@Test func describesSingleModifier() {
    #expect(HotKeyCombo(keyCode: 37, modifiers: HotKeyCombo.command).displayString == "⌘L")
}

@Test func describesAllFourModifiers() {
    let all = HotKeyCombo.control | HotKeyCombo.option | HotKeyCombo.shift | HotKeyCombo.command
    #expect(HotKeyCombo(keyCode: 37, modifiers: all).displayString == "⌃⌥⇧⌘L")
}

@Test func unknownKeyCodeFallsBackToNumber() {
    #expect(HotKeyCombo(keyCode: 999, modifiers: HotKeyCombo.command).displayString == "⌘#999")
}

@Test func survivesEncodingRoundTrip() throws {
    let combo = HotKeyCombo(keyCode: 15, modifiers: HotKeyCombo.command)
    let data = try JSONEncoder().encode(combo)
    #expect(try JSONDecoder().decode(HotKeyCombo.self, from: data) == combo)
}
```

- [ ] **Step 2: Убедиться, что тест падает**

Run: `cd Packages/Core && swift test --filter HotKeyTests`
Expected: FAIL, `cannot find 'HotKeyCombo' in scope`.

- [ ] **Step 3: Реализовать описание сочетания**

Дописать в `Packages/Core/Sources/Preferences/Preferences.swift` перед
`struct Preferences`:

```swift
/// Сочетание клавиш. Хранится кодами Carbon, а не символами: символ зависит от
/// раскладки, а код клавиши — нет, поэтому сочетание не «переезжает» при
/// переключении на другой язык ввода.
public struct HotKeyCombo: Codable, Sendable, Hashable {
    public static let control: UInt32 = 1 << 12
    public static let option: UInt32 = 1 << 11
    public static let shift: UInt32 = 1 << 9
    public static let command: UInt32 = 1 << 8

    public let keyCode: UInt32
    public let modifiers: UInt32

    public init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// Как сочетание выглядит в интерфейсе. Порядок значков — принятый в macOS.
    public var displayString: String {
        var result = ""
        if modifiers & Self.control != 0 { result += "⌃" }
        if modifiers & Self.option != 0 { result += "⌥" }
        if modifiers & Self.shift != 0 { result += "⇧" }
        if modifiers & Self.command != 0 { result += "⌘" }
        return result + Self.name(for: keyCode)
    }

    private static let names: [UInt32: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V",
        11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T", 31: "O", 32: "U",
        34: "I", 35: "P", 37: "L", 38: "J", 40: "K", 45: "N", 46: "M", 49: "Space",
    ]

    private static func name(for code: UInt32) -> String {
        names[code] ?? "#\(code)"
    }
}
```

Добавить поля в `Preferences` после `refreshAfterWake`:

```swift
    public var openWindowHotKey: HotKeyCombo?
    public var refreshHotKey: HotKeyCombo?
```

и в `defaults` после `refreshAfterWake: true,`:

```swift
        openWindowHotKey: nil,
        refreshHotKey: nil,
```

- [ ] **Step 4: Убедиться, что тесты проходят**

Run: `cd Packages/Core && swift test --filter HotKeyTests`
Expected: PASS, 5 тестов.

Run: `cd Packages/Core && swift test --filter PreferencesTests`
Expected: PASS — `defaultsMatchTheSpec` продолжает работать, новые поля `nil`.

- [ ] **Step 5: Реализовать регистрацию**

Создать `App/HotKeys.swift`:

```swift
import Foundation
import AppKit
import Carbon.HIToolbox
import Preferences

/// Глобальные сочетания клавиш.
///
/// Carbon `RegisterEventHotKey` — единственный способ получить сочетание,
/// работающее вне активного приложения, без запроса прав Accessibility.
/// Современного замещения у него нет.
@MainActor
final class HotKeyCenter {
    static let shared = HotKeyCenter()

    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var actions: [UInt32: () -> Void] = [:]
    private var handler: EventHandlerRef?

    private init() { installHandler() }

    func register(_ combo: HotKeyCombo?, id: UInt32, action: @escaping () -> Void) {
        unregister(id: id)
        guard let combo else { return }

        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x53544348), id: id)  // 'STCH'
        let status = RegisterEventHotKey(
            combo.keyCode, combo.modifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref
        )
        guard status == noErr, let ref else { return }

        refs[id] = ref
        actions[id] = action
    }

    func unregister(id: UInt32) {
        if let ref = refs.removeValue(forKey: id) { UnregisterEventHotKey(ref) }
        actions[id] = nil
    }

    func unregisterAll() {
        for id in refs.keys { unregister(id: id) }
    }

    private func installHandler() {
        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, _ -> OSStatus in
                var id = EventHotKeyID()
                GetEventParameter(
                    event, EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID), nil,
                    MemoryLayout<EventHotKeyID>.size, nil, &id
                )
                let pressed = id.id
                Task { @MainActor in HotKeyCenter.shared.fire(pressed) }
                return noErr
            },
            1, &spec, nil, &handler
        )
    }

    fileprivate func fire(_ id: UInt32) {
        actions[id]?()
    }
}

enum HotKeyID {
    static let openWindow: UInt32 = 1
    static let refresh: UInt32 = 2
}
```

- [ ] **Step 6: Добавить запись сочетания в раздел**

В `App/Settings/UpdatesPane.swift` заменить секцию «Горячие клавиши»:

```swift
                Section("Горячие клавиши") {
                    hotKeyRow("Открыть окно", path: \.openWindowHotKey)
                    hotKeyRow("Обновить сейчас", path: \.refreshHotKey)
                }
```

и дописать в тот же тип:

```swift
    @State private var recording: String?

    private func hotKeyRow(
        _ title: String, path: WritableKeyPath<Preferences, HotKeyCombo?>
    ) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(model.value[keyPath: path]?.displayString ?? "не назначено")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(model.value[keyPath: path] == nil ? .secondary : .primary)
            Button(recording == title ? "Нажмите…" : "Изменить") {
                recording = recording == title ? nil : title
            }
            if model.value[keyPath: path] != nil {
                Button("Убрать") { model.update { $0[keyPath: path] = nil } }
            }
        }
        .background(
            HotKeyRecorder(isActive: recording == title) { combo in
                model.update { $0[keyPath: path] = combo }
                recording = nil
            }
        )
    }
```

Создать перехватчик нажатия в том же файле:

```swift
/// Ловит одно нажатие и отдаёт его как сочетание.
/// Через `NSView`, потому что SwiftUI не отдаёт коды клавиш и модификаторы
/// в том виде, в каком их ждёт Carbon.
private struct HotKeyRecorder: NSViewRepresentable {
    let isActive: Bool
    let onCapture: (HotKeyCombo) -> Void

    func makeNSView(context: Context) -> RecorderView {
        let view = RecorderView()
        view.onCapture = onCapture
        return view
    }

    func updateNSView(_ view: RecorderView, context: Context) {
        view.onCapture = onCapture
        if isActive { view.window?.makeFirstResponder(view) }
    }

    final class RecorderView: NSView {
        var onCapture: ((HotKeyCombo) -> Void)?

        override var acceptsFirstResponder: Bool { true }

        override func keyDown(with event: NSEvent) {
            var modifiers: UInt32 = 0
            if event.modifierFlags.contains(.control) { modifiers |= HotKeyCombo.control }
            if event.modifierFlags.contains(.option) { modifiers |= HotKeyCombo.option }
            if event.modifierFlags.contains(.shift) { modifiers |= HotKeyCombo.shift }
            if event.modifierFlags.contains(.command) { modifiers |= HotKeyCombo.command }

            // Сочетание без модификаторов перехватило бы обычный ввод.
            guard modifiers != 0 else { NSSound.beep(); return }
            onCapture?(HotKeyCombo(keyCode: UInt32(event.keyCode), modifiers: modifiers))
        }
    }
}
```

- [ ] **Step 7: Подключить действия**

В `App/StatusCheckerApp.swift` в сцене `Settings` добавить регистрацию:

```swift
                .onChange(of: preferences.value.openWindowHotKey, initial: true) { _, combo in
                    HotKeyCenter.shared.register(combo, id: HotKeyID.openWindow) {
                        NSApp.sendAction(
                            Selector(("openMenuBarExtra:")), to: nil, from: nil
                        )
                    }
                }
                .onChange(of: preferences.value.refreshHotKey, initial: true) { _, combo in
                    HotKeyCenter.shared.register(combo, id: HotKeyID.refresh) {
                        Task { await model.refresh() }
                    }
                }
```

Открытие окна строки меню программно системой не поддерживается напрямую;
если `openMenuBarExtra:` не срабатывает, сочетание «Открыть окно» остаётся
незанятым, а «Обновить сейчас» работает. Проверить на шаге 8 и, если открытие не
работает, убрать строку «Открыть окно» из раздела и оставить одно сочетание —
обещать в интерфейсе то, что не работает, нельзя.

- [ ] **Step 8: Собрать и проверить**

Run: `make build`
Expected: `BUILD SUCCEEDED`.

Run: `make run`, назначить «Обновить сейчас» на ⌥⌘R, свернуть все окна, нажать
сочетание.
Expected: время в заголовке окна лимитов обновляется, значок перерисовывается.

- [ ] **Step 9: Commit**

```bash
git add App Packages/Core
git commit -m "Горячие клавиши: запись сочетания и глобальная регистрация"
```

---

### Task 13: Приёмка и документация

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Прогнать все тесты**

Run: `make test`
Expected: PASS, ни одного падения.

- [ ] **Step 2: Пройти по всем разделам**

Run: `make run`, открыть «Настройки…» и проверить каждый:

- **Аккаунты** — состояния показаны верно; выключатель убирает аккаунт из окна;
  «Забыть» спрашивает подтверждение; `claude --version` после этого работает.
- **Внешний вид** — переключение оформления меняет вид окна сразу; три
  компоновки строки читаемы; изменение «В строке меню» видно на значке.
- **Уведомления** — порог добавляется и удаляется; при выключенном «Уведомлять»
  форма недоступна.
- **Обновление** — автозапуск отражает состояние системы; интервалы не выходят
  за 30 с и час.
- **Сервисы** — выключение Codex убирает его строку; выключение обоих даёт
  «Аккаунты не найдены» без падения.
- **О программе** — версия верная; «Забыть все аккаунты» спрашивает подтверждение.

- [ ] **Step 3: Проверить, что вход в CLI цел**

Run: `claude --version`
Expected: версия печатается, вход не слетел.

Run: `security find-generic-password -s "Claude Code-credentials" | head -3`
Expected: элемент на месте.

- [ ] **Step 4: Обновить README**

В `README.md` после раздела «Несколько подписок Claude» добавить:

```markdown
## Настройки

Открываются из окна лимитов пунктом «Настройки…» или сочетанием ⌘,.

Шесть разделов: аккаунты, внешний вид, уведомления, обновление и запуск,
сервисы, о программе. Оформление — системное, светлое или тёмное.

Аккаунт можно добавить прямо из настроек кнопкой «Добавить аккаунт…»: откроется
браузер, пароль вводится только там. Такой аккаунт живёт на своей паре токенов и
не связан с сессией CLI.

Настройки лежат в `~/Library/Preferences/dev.example.StatusChecker.plist`.
Учётные данные там не хранятся — они в Keychain, в элементе
`StatusChecker-accounts`.
```

- [ ] **Step 5: Commit**

```bash
git add README.md
git commit -m "README: раздел о настройках"
```

---

## Что осталось за рамками

1. **Перенос настроек между машинами** — сейчас они локальные.
2. **Живые данные Codex** вместо снимка.
3. **Провайдеры Cursor, GitHub Copilot, Gemini CLI** — место под них в разделе
   «Сервисы» уже есть.
4. **Приложение под iOS и виджет.**
