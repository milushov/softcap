> **Note.** This plan is kept in Russian: it is a record of work already
> carried out, step by step, not a reference document. New plans are written
> in English. See `docs/DECISIONS.md` for the reasoning.

# Прототип монитора лимитов для macOS — план реализации

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Приложение в строке меню macOS, показывающее остаток лимитов по трём подпискам Claude Code и одной OpenAI Codex в одном окне.

**Architecture:** Вся логика живёт в SwiftPM-пакете `Packages/Core` и тестируется через `swift test` без Xcode. Приложение — тонкий слой SwiftUI поверх него, проект генерируется XcodeGen из `project.yml`. Провайдеры сервисов реализуют общий протокол `UsageProvider` и возвращают единую структуру `AccountSnapshot`, поэтому интерфейс не знает, откуда пришли данные.

**Tech Stack:** Swift 6.2, SwiftUI `MenuBarExtra`, Swift Testing (`import Testing`), SwiftPM, XcodeGen, Keychain Services, `UserNotifications`.

## Global Constraints

- Swift tools version `6.2`; платформа `.macOS(.v14)` в пакете, приложение собирается под macOS 14+.
- Строгая конкурентность Swift 6: все модели `Sendable`, UI помечен `@MainActor`.
- Ни один тест не ходит в сеть и не читает настоящий Keychain — сеть и файловая система за протоколами.
- Секреты никогда не пишутся в логи, файлы настроек и сообщения об ошибках.
- Язык интерфейса — русский. Подписи окон: `5ч`, `нед`. Формат остатка: `47 м`, `3 ч 39 м`, `5 д 23 ч`.
- Цветовые пороги: `<50 %` зелёный, `50–75 %` жёлтый, `75–90 %` оранжевый, `≥90 %` красный.
- Порог уведомлений: 80 % и 95 %, срабатывает на пересечении снизу вверх.
- Имя приложения и схемы: `StatusChecker`.

## Структура файлов

```
softcap/
├── project.yml                                  # XcodeGen: цель StatusChecker
├── Packages/Core/
│   ├── Package.swift
│   ├── Sources/
│   │   ├── ProviderKit/
│   │   │   ├── Models.swift                     # LimitWindow, AccountSnapshot, Freshness, Severity
│   │   │   ├── UsageProvider.swift              # протокол + AccountRef + ProviderFailure
│   │   │   ├── TimeFormatting.swift             # остаток времени словами
│   │   │   └── SnapshotOrdering.swift           # сортировка строк списка
│   │   ├── ClaudeProvider/
│   │   │   ├── ClaudeUsageResponse.swift        # разбор ответа /oauth/usage
│   │   │   ├── ClaudeProfileResponse.swift      # разбор ответа /oauth/profile
│   │   │   ├── HTTPClient.swift                 # протокол сети + реализация на URLSession
│   │   │   └── ClaudeProvider.swift             # сборка снимка
│   │   ├── CodexProvider/
│   │   │   ├── RolloutParser.swift              # rate_limits из .jsonl
│   │   │   ├── CodexIdentity.swift              # личность из auth.json (JWT)
│   │   │   └── CodexProvider.swift              # сборка снимка
│   │   ├── Credentials/
│   │   │   ├── KeychainAccess.swift             # протокол доступа к Keychain
│   │   │   └── CredentialStore.swift            # свои аккаунты + зеркало CLI
│   │   └── Monitoring/
│   │       ├── UsagePoller.swift                # опрос и кэш
│   │       └── ThresholdNotifier.swift          # пороги
│   └── Tests/
│       ├── ProviderKitTests/
│       ├── ClaudeProviderTests/
│       ├── CodexProviderTests/
│       ├── CredentialsTests/
│       └── MonitoringTests/
└── App/
    ├── StatusCheckerApp.swift                   # MenuBarExtra, иконка с таймером
    ├── AccountRowView.swift                     # строка варианта A
    ├── PopoverView.swift                        # окно целиком
    ├── AppModel.swift                           # @MainActor обёртка над UsagePoller
    └── Info.plist                               # LSUIElement = 1
```

---

### Task 1: Каркас пакета и форматирование остатка времени

**Files:**
- Create: `Packages/Core/Package.swift`
- Create: `Packages/Core/Sources/ProviderKit/TimeFormatting.swift`
- Test: `Packages/Core/Tests/ProviderKitTests/TimeFormattingTests.swift`

**Interfaces:**
- Consumes: ничего.
- Produces: `ProviderKit.formatRemaining(_ interval: TimeInterval) -> String` — возвращает `"—"` для `nil`-подобных случаев (отрицательный интервал), `"47 м"`, `"3 ч 39 м"`, `"5 д 23 ч"`.

- [ ] **Step 1: Создать манифест пакета**

Создать `Packages/Core/Package.swift`:

```swift
// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Core",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ProviderKit", targets: ["ProviderKit"]),
        .library(name: "ClaudeProvider", targets: ["ClaudeProvider"]),
        .library(name: "CodexProvider", targets: ["CodexProvider"]),
        .library(name: "Credentials", targets: ["Credentials"]),
        .library(name: "Monitoring", targets: ["Monitoring"]),
    ],
    targets: [
        .target(name: "ProviderKit"),
        .target(name: "ClaudeProvider", dependencies: ["ProviderKit"]),
        .target(name: "CodexProvider", dependencies: ["ProviderKit"]),
        .target(name: "Credentials", dependencies: ["ProviderKit", "ClaudeProvider"]),
        .target(name: "Monitoring", dependencies: ["ProviderKit"]),
        .testTarget(name: "ProviderKitTests", dependencies: ["ProviderKit"]),
        .testTarget(name: "ClaudeProviderTests", dependencies: ["ClaudeProvider"]),
        .testTarget(name: "CodexProviderTests", dependencies: ["CodexProvider"]),
        .testTarget(name: "CredentialsTests", dependencies: ["Credentials"]),
        .testTarget(name: "MonitoringTests", dependencies: ["Monitoring"]),
    ]
)
```

- [ ] **Step 2: Написать падающий тест**

Создать `Packages/Core/Tests/ProviderKitTests/TimeFormattingTests.swift`:

```swift
import Testing
import Foundation
@testable import ProviderKit

@Test func showsMinutesOnlyUnderAnHour() {
    #expect(formatRemaining(47 * 60) == "47 м")
}

@Test func showsHoursAndMinutes() {
    #expect(formatRemaining(3 * 3600 + 39 * 60) == "3 ч 39 м")
}

@Test func showsDaysAndHours() {
    #expect(formatRemaining(5 * 86400 + 23 * 3600 + 39 * 60) == "5 д 23 ч")
}

@Test func showsDashWhenAlreadyElapsed() {
    #expect(formatRemaining(-120) == "—")
}

@Test func roundsDownRatherThanUp() {
    // 59 секунд — это ещё ноль минут, а не одна
    #expect(formatRemaining(59) == "0 м")
}
```

Пустые директории для остальных тест-таргетов создать сразу, иначе SwiftPM не соберёт манифест:

```bash
mkdir -p Packages/Core/Sources/{ProviderKit,ClaudeProvider,CodexProvider,Credentials,Monitoring}
mkdir -p Packages/Core/Tests/{ProviderKitTests,ClaudeProviderTests,CodexProviderTests,CredentialsTests,MonitoringTests}
for t in ClaudeProvider CodexProvider Credentials Monitoring; do
  echo "// placeholder, наполняется в следующих задачах" > "Packages/Core/Sources/$t/$t.swift"
done
for t in ClaudeProviderTests CodexProviderTests CredentialsTests MonitoringTests; do
  printf 'import Testing\n\n@Test func placeholder_%s() { #expect(Bool(true)) }\n' "$t" > "Packages/Core/Tests/$t/Placeholder.swift"
done
```

- [ ] **Step 3: Убедиться, что тест падает**

Run: `cd Packages/Core && swift test --filter TimeFormattingTests`
Expected: FAIL, компилятор сообщает `cannot find 'formatRemaining' in scope`.

- [ ] **Step 4: Реализовать**

Создать `Packages/Core/Sources/ProviderKit/TimeFormatting.swift`:

```swift
import Foundation

/// Остаток времени человеческими словами: «47 м», «3 ч 39 м», «5 д 23 ч».
/// Всегда округляет вниз: пока минута не прошла целиком, она не считается.
public func formatRemaining(_ interval: TimeInterval) -> String {
    guard interval >= 0 else { return "—" }
    let total = Int(interval)
    let days = total / 86_400
    let hours = (total % 86_400) / 3_600
    let minutes = (total % 3_600) / 60

    if days > 0 { return "\(days) д \(hours) ч" }
    if hours > 0 { return "\(hours) ч \(minutes) м" }
    return "\(minutes) м"
}

/// Компактный вид для строки меню: «0:47», «3:39», «5д».
public func formatRemainingCompact(_ interval: TimeInterval) -> String {
    guard interval >= 0 else { return "—" }
    let total = Int(interval)
    let days = total / 86_400
    guard days == 0 else { return "\(days)д" }
    let hours = (total % 86_400) / 3_600
    let minutes = (total % 3_600) / 60
    return String(format: "%d:%02d", hours, minutes)
}
```

- [ ] **Step 5: Убедиться, что тест проходит**

Run: `cd Packages/Core && swift test --filter TimeFormattingTests`
Expected: PASS, 5 тестов.

- [ ] **Step 6: Добавить тест компактного формата и проверить**

Дописать в `TimeFormattingTests.swift`:

```swift
@Test func compactFormShowsClock() {
    #expect(formatRemainingCompact(47 * 60) == "0:47")
    #expect(formatRemainingCompact(3 * 3600 + 39 * 60) == "3:39")
}

@Test func compactFormCollapsesDays() {
    #expect(formatRemainingCompact(5 * 86400 + 23 * 3600) == "5д")
}
```

Run: `cd Packages/Core && swift test --filter TimeFormattingTests`
Expected: PASS, 7 тестов.

- [ ] **Step 7: Commit**

```bash
git add Packages/Core
git commit -m "Каркас пакета Core и форматирование остатка времени"
```

---

### Task 2: Модели и протокол провайдера

**Files:**
- Create: `Packages/Core/Sources/ProviderKit/Models.swift`
- Create: `Packages/Core/Sources/ProviderKit/UsageProvider.swift`
- Create: `Packages/Core/Sources/ProviderKit/SnapshotOrdering.swift`
- Test: `Packages/Core/Tests/ProviderKitTests/ModelsTests.swift`
- Test: `Packages/Core/Tests/ProviderKitTests/SnapshotOrderingTests.swift`

**Interfaces:**
- Consumes: `formatRemaining` из Task 1.
- Produces:
  - `ProviderID` — `.claude`, `.codex`, `.cursor`, `.copilot`, `.gemini`
  - `LimitWindow(id:label:percent:resetsAt:)`, свойство `severity: Severity`
  - `Severity` — `.ok`, `.warning`, `.hot`, `.critical`, метод `Severity(percent:)`
  - `Freshness` — `.live(Date)`, `.snapshot(Date)`, свойство `capturedAt: Date`
  - `ProviderFailure(kind:message:)`, `ProviderFailure.Kind` — `.needsLogin`, `.network`, `.noData`, `.malformed`
  - `AccountSnapshot(id:provider:displayName:planLabel:windows:freshness:failure:)`, свойства `peakPercent: Double`, `peakWindow: LimitWindow?`
  - `AccountRef(id:provider:handle:)`
  - `protocol UsageProvider: Sendable` с `id`, `discoverAccounts()`, `fetch(_:)`
  - `orderedForDisplay(_ snapshots: [AccountSnapshot]) -> [AccountSnapshot]`

- [ ] **Step 1: Написать падающий тест на модели**

Создать `Packages/Core/Tests/ProviderKitTests/ModelsTests.swift`:

```swift
import Testing
import Foundation
@testable import ProviderKit

@Test func severityFollowsThresholds() {
    #expect(Severity(percent: 0) == .ok)
    #expect(Severity(percent: 49.9) == .ok)
    #expect(Severity(percent: 50) == .warning)
    #expect(Severity(percent: 74.9) == .warning)
    #expect(Severity(percent: 75) == .hot)
    #expect(Severity(percent: 89.9) == .hot)
    #expect(Severity(percent: 90) == .critical)
    #expect(Severity(percent: 100) == .critical)
}

@Test func peakPercentIsTheWorstWindow() {
    let snapshot = AccountSnapshot(
        id: "claude/abc", provider: .claude,
        displayName: "a@b.c", planLabel: "Max 20x",
        windows: [
            LimitWindow(id: "session", label: "5ч", percent: 5, resetsAt: nil),
            LimitWindow(id: "weekly", label: "нед", percent: 23, resetsAt: nil),
        ],
        freshness: .live(Date(timeIntervalSince1970: 0)), failure: nil
    )
    #expect(snapshot.peakPercent == 23)
    #expect(snapshot.peakWindow?.id == "weekly")
}

@Test func peakOfEmptyWindowsIsZero() {
    let snapshot = AccountSnapshot(
        id: "codex/x", provider: .codex,
        displayName: "T", planLabel: "Plus",
        windows: [], freshness: .snapshot(Date(timeIntervalSince1970: 0)),
        failure: ProviderFailure(kind: .noData, message: "нет данных")
    )
    #expect(snapshot.peakPercent == 0)
    #expect(snapshot.peakWindow == nil)
}

@Test func freshnessExposesCaptureTime() {
    let moment = Date(timeIntervalSince1970: 1_787_867_253)
    #expect(Freshness.live(moment).capturedAt == moment)
    #expect(Freshness.snapshot(moment).capturedAt == moment)
    #expect(Freshness.live(moment).isStale == false)
    #expect(Freshness.snapshot(moment).isStale == true)
}
```

- [ ] **Step 2: Убедиться, что тест падает**

Run: `cd Packages/Core && swift test --filter ModelsTests`
Expected: FAIL, `cannot find 'Severity' in scope`.

- [ ] **Step 3: Реализовать модели**

Создать `Packages/Core/Sources/ProviderKit/Models.swift`:

```swift
import Foundation

public enum ProviderID: String, Sendable, Hashable, CaseIterable {
    case claude, codex, cursor, copilot, gemini

    /// Подпись сервиса в строке аккаунта.
    public var title: String {
        switch self {
        case .claude:  "Claude"
        case .codex:   "Codex"
        case .cursor:  "Cursor"
        case .copilot: "Copilot"
        case .gemini:  "Gemini"
        }
    }
}

public enum Severity: Sendable, Hashable {
    case ok, warning, hot, critical

    public init(percent: Double) {
        switch percent {
        case ..<50:  self = .ok
        case ..<75:  self = .warning
        case ..<90:  self = .hot
        default:     self = .critical
        }
    }
}

public struct LimitWindow: Sendable, Hashable, Identifiable {
    public let id: String        // "session", "weekly"
    public let label: String     // "5ч", "нед"
    public let percent: Double   // 0…100
    public let resetsAt: Date?

    public init(id: String, label: String, percent: Double, resetsAt: Date?) {
        self.id = id
        self.label = label
        self.percent = percent
        self.resetsAt = resetsAt
    }

    public var severity: Severity { Severity(percent: percent) }

    /// Остаток до сброса относительно переданного момента.
    public func remaining(from now: Date) -> TimeInterval? {
        resetsAt.map { $0.timeIntervalSince(now) }
    }
}

public enum Freshness: Sendable, Hashable {
    case live(Date)       // получено запросом
    case snapshot(Date)   // прочитано из локального файла

    public var capturedAt: Date {
        switch self {
        case .live(let d), .snapshot(let d): d
        }
    }

    public var isStale: Bool {
        if case .snapshot = self { return true }
        return false
    }
}

public struct ProviderFailure: Sendable, Hashable, Error {
    public enum Kind: Sendable, Hashable {
        case needsLogin   // токен мёртв, нужен вход
        case network      // сеть недоступна
        case noData       // источник пуст
        case malformed    // ответ не разобран
    }

    public let kind: Kind
    public let message: String

    public init(kind: Kind, message: String) {
        self.kind = kind
        self.message = message
    }
}

public struct AccountSnapshot: Sendable, Hashable, Identifiable {
    public let id: String            // "claude/<uuid>"
    public let provider: ProviderID
    public let displayName: String   // email или имя
    public let planLabel: String     // "Max 20x", "Plus"
    public let windows: [LimitWindow]
    public let freshness: Freshness
    public let failure: ProviderFailure?

    public init(
        id: String, provider: ProviderID, displayName: String, planLabel: String,
        windows: [LimitWindow], freshness: Freshness, failure: ProviderFailure?
    ) {
        self.id = id
        self.provider = provider
        self.displayName = displayName
        self.planLabel = planLabel
        self.windows = windows
        self.freshness = freshness
        self.failure = failure
    }

    /// Самое загруженное окно — по нему считается цвет и место в списке.
    public var peakWindow: LimitWindow? {
        windows.max { $0.percent < $1.percent }
    }

    public var peakPercent: Double { peakWindow?.percent ?? 0 }
}
```

- [ ] **Step 4: Убедиться, что тест проходит**

Run: `cd Packages/Core && swift test --filter ModelsTests`
Expected: PASS, 4 теста.

- [ ] **Step 5: Написать падающий тест на сортировку**

Создать `Packages/Core/Tests/ProviderKitTests/SnapshotOrderingTests.swift`:

```swift
import Testing
import Foundation
@testable import ProviderKit

private func make(_ id: String, peak: Double, failed: Bool = false) -> AccountSnapshot {
    AccountSnapshot(
        id: id, provider: .claude, displayName: id, planLabel: "Max",
        windows: [LimitWindow(id: "weekly", label: "нед", percent: peak, resetsAt: nil)],
        freshness: .live(Date(timeIntervalSince1970: 0)),
        failure: failed ? ProviderFailure(kind: .network, message: "нет сети") : nil
    )
}

@Test func leastLoadedComesFirst() {
    let ordered = orderedForDisplay([make("c", peak: 88), make("a", peak: 5), make("b", peak: 61)])
    #expect(ordered.map(\.id) == ["a", "b", "c"])
}

@Test func failuresSinkToTheBottom() {
    let ordered = orderedForDisplay([make("bad", peak: 0, failed: true), make("busy", peak: 99)])
    #expect(ordered.map(\.id) == ["busy", "bad"])
}

@Test func tiesBreakByNameSoOrderIsStable() {
    let ordered = orderedForDisplay([make("zeta", peak: 10), make("alpha", peak: 10)])
    #expect(ordered.map(\.id) == ["alpha", "zeta"])
}
```

- [ ] **Step 6: Убедиться, что тест падает**

Run: `cd Packages/Core && swift test --filter SnapshotOrderingTests`
Expected: FAIL, `cannot find 'orderedForDisplay' in scope`.

- [ ] **Step 7: Реализовать сортировку и протокол**

Создать `Packages/Core/Sources/ProviderKit/SnapshotOrdering.swift`:

```swift
import Foundation

/// Порядок строк в окне: сверху тот аккаунт, куда можно идти работать.
/// Аккаунты с ошибкой уходят вниз — по ним всё равно нечего сказать.
public func orderedForDisplay(_ snapshots: [AccountSnapshot]) -> [AccountSnapshot] {
    snapshots.sorted { lhs, rhs in
        let lhsFailed = lhs.failure != nil
        let rhsFailed = rhs.failure != nil
        if lhsFailed != rhsFailed { return !lhsFailed }
        if lhs.peakPercent != rhs.peakPercent { return lhs.peakPercent < rhs.peakPercent }
        return lhs.displayName.localizedCompare(rhs.displayName) == .orderedAscending
    }
}
```

Создать `Packages/Core/Sources/ProviderKit/UsageProvider.swift`:

```swift
import Foundation

/// Ссылка на аккаунт, достаточная, чтобы за него сходить.
/// `handle` — то, чем провайдер сам себя ориентирует: uuid аккаунта Claude,
/// путь к каталогу сессий Codex и так далее.
public struct AccountRef: Sendable, Hashable, Identifiable {
    public let id: String
    public let provider: ProviderID
    public let handle: String

    public init(id: String, provider: ProviderID, handle: String) {
        self.id = id
        self.provider = provider
        self.handle = handle
    }
}

public protocol UsageProvider: Sendable {
    var id: ProviderID { get }

    /// Какие аккаунты этот провайдер вообще видит.
    func discoverAccounts() async throws -> [AccountRef]

    /// Снимок по конкретному аккаунту. Бросает `ProviderFailure`.
    func fetch(_ ref: AccountRef) async throws -> AccountSnapshot
}
```

- [ ] **Step 8: Убедиться, что все тесты проходят**

Run: `cd Packages/Core && swift test --filter ProviderKitTests`
Expected: PASS, 14 тестов (7 из Task 1 + 4 модели + 3 сортировка).

- [ ] **Step 9: Commit**

```bash
git add Packages/Core
git commit -m "Модели лимитов, протокол провайдера и порядок строк"
```

---

### Task 3: Разбор файлов сессий Codex

**Files:**
- Create: `Packages/Core/Sources/CodexProvider/RolloutParser.swift`
- Delete: `Packages/Core/Sources/CodexProvider/CodexProvider.swift` (заглушка из Task 1)
- Test: `Packages/Core/Tests/CodexProviderTests/RolloutParserTests.swift`
- Delete: `Packages/Core/Tests/CodexProviderTests/Placeholder.swift`

**Interfaces:**
- Consumes: `LimitWindow`, `ProviderFailure` из Task 2.
- Produces:
  - `enum CodexTimestamp { static func date(from text: String) -> Date? }`
  - `struct RateLimitsEvent: Sendable { let capturedAt: Date; let planType: String?; let windows: [LimitWindow] }`
  - `enum RolloutParser { static func latestEvent(inLines lines: [String]) throws -> RateLimitsEvent }`
  - Бросает `ProviderFailure(kind: .noData, …)`, если событий нет.

Формат строки в файле сессии (проверено на реальных данных 2026-08-30):

```json
{"timestamp":"2026-08-27T16:47:37.701Z","ordinal":12,"type":"event_msg",
 "payload":{"type":"token_count","info":{…},
   "rate_limits":{"limit_id":"codex","plan_type":"plus",
     "primary":{"used_percent":0.0,"window_minutes":300,"resets_at":1787867253},
     "secondary":{"used_percent":0.0,"window_minutes":10080,"resets_at":1788454053}}}}
```

`window_minutes` 300 — пятичасовое окно, 10080 — недельное. `resets_at` — unix-секунды.

- [ ] **Step 1: Написать падающий тест**

Создать `Packages/Core/Tests/CodexProviderTests/RolloutParserTests.swift`:

```swift
import Testing
import Foundation
import ProviderKit
@testable import CodexProvider

private let eventLine = """
{"timestamp":"2026-08-27T16:47:37.701Z","ordinal":12,"type":"event_msg","payload":\
{"type":"token_count","info":{"model_context_window":258400},"rate_limits":\
{"limit_id":"codex","plan_type":"plus",\
"primary":{"used_percent":12.5,"window_minutes":300,"resets_at":1787867253},\
"secondary":{"used_percent":32.0,"window_minutes":10080,"resets_at":1788454053}}}}
"""

private let olderLine = """
{"timestamp":"2026-08-27T15:00:00.000Z","ordinal":4,"type":"event_msg","payload":\
{"type":"token_count","rate_limits":\
{"limit_id":"codex","plan_type":"plus",\
"primary":{"used_percent":1.0,"window_minutes":300,"resets_at":1787867253},\
"secondary":{"used_percent":2.0,"window_minutes":10080,"resets_at":1788454053}}}}
"""

private let noiseLine = """
{"timestamp":"2026-08-27T15:30:00.000Z","type":"event_msg","payload":{"type":"agent_message","message":"привет"}}
"""

@Test func readsPercentsAndWindows() throws {
    let event = try RolloutParser.latestEvent(inLines: [eventLine])
    #expect(event.planType == "plus")
    #expect(event.windows.count == 2)

    let session = try #require(event.windows.first { $0.id == "session" })
    #expect(session.label == "5ч")
    #expect(session.percent == 12.5)
    #expect(session.resetsAt == Date(timeIntervalSince1970: 1_787_867_253))

    let weekly = try #require(event.windows.first { $0.id == "weekly" })
    #expect(weekly.label == "нед")
    #expect(weekly.percent == 32.0)
}

@Test func usesEventTimestampAsCaptureTime() throws {
    let event = try RolloutParser.latestEvent(inLines: [eventLine])
    let expected = CodexTimestamp.date(from: "2026-08-27T16:47:37.701Z")
    #expect(event.capturedAt == expected)
}

@Test func takesTheLastEventNotTheFirst() throws {
    let event = try RolloutParser.latestEvent(inLines: [olderLine, noiseLine, eventLine])
    #expect(event.windows.first { $0.id == "weekly" }?.percent == 32.0)
}

@Test func ignoresLinesWithoutRateLimits() throws {
    let event = try RolloutParser.latestEvent(inLines: [noiseLine, eventLine])
    #expect(event.windows.count == 2)
}

@Test func failsWithNoDataWhenNothingMatches() {
    #expect(throws: ProviderFailure.self) {
        try RolloutParser.latestEvent(inLines: [noiseLine])
    }
}

@Test func survivesBrokenJSONLine() throws {
    let event = try RolloutParser.latestEvent(inLines: ["{это не json", eventLine])
    #expect(event.windows.count == 2)
}

@Test func omitsWindowThatServerReportsAsNull() throws {
    let onlyPrimary = """
    {"timestamp":"2026-08-27T16:00:00.000Z","type":"event_msg","payload":\
    {"type":"token_count","rate_limits":{"limit_id":"codex","plan_type":"pro",\
    "primary":{"used_percent":7.0,"window_minutes":300,"resets_at":1787867253},\
    "secondary":null}}}
    """
    let event = try RolloutParser.latestEvent(inLines: [onlyPrimary])
    #expect(event.windows.count == 1)
    #expect(event.windows[0].id == "session")
    #expect(event.planType == "pro")
}
```

- [ ] **Step 2: Убедиться, что тест падает**

Run: `cd Packages/Core && swift test --filter RolloutParserTests`
Expected: FAIL, `cannot find 'RolloutParser' in scope`.

- [ ] **Step 3: Реализовать разбор**

Удалить заглушку и создать `Packages/Core/Sources/CodexProvider/RolloutParser.swift`:

```bash
rm Packages/Core/Sources/CodexProvider/CodexProvider.swift
rm Packages/Core/Tests/CodexProviderTests/Placeholder.swift
```

```swift
import Foundation
import ProviderKit

/// Codex пишет время с долями секунды: «2026-08-27T16:47:37.701Z».
///
/// Взят `Date.ISO8601FormatStyle`, а не `ISO8601DateFormatter`: последний не
/// `Sendable`, и `static let` с ним не проходит проверку конкурентности Swift 6.
public enum CodexTimestamp {
    private static let style = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    public static func date(from text: String) -> Date? { try? style.parse(text) }
}

public struct RateLimitsEvent: Sendable, Hashable {
    public let capturedAt: Date
    public let planType: String?
    public let windows: [LimitWindow]
}

/// Разбирает строки файла сессии Codex и достаёт последнее событие с лимитами.
/// Файл — JSONL, каждая строка самостоятельна, поэтому битая строка просто
/// пропускается: терять весь файл из-за одной строки нельзя.
public enum RolloutParser {

    private struct Line: Decodable {
        let timestamp: String?
        let payload: Payload?

        struct Payload: Decodable {
            let rateLimits: RateLimits?
            enum CodingKeys: String, CodingKey { case rateLimits = "rate_limits" }
        }

        struct RateLimits: Decodable {
            let planType: String?
            let primary: Window?
            let secondary: Window?
            enum CodingKeys: String, CodingKey {
                case planType = "plan_type", primary, secondary
            }
        }

        struct Window: Decodable {
            let usedPercent: Double
            let windowMinutes: Int
            let resetsAt: Double?
            enum CodingKeys: String, CodingKey {
                case usedPercent = "used_percent"
                case windowMinutes = "window_minutes"
                case resetsAt = "resets_at"
            }
        }
    }

    public static func latestEvent(inLines lines: [String]) throws -> RateLimitsEvent {
        let decoder = JSONDecoder()

        for raw in lines.reversed() {
            guard raw.contains("\"rate_limits\""),
                  let data = raw.data(using: .utf8),
                  let line = try? decoder.decode(Line.self, from: data),
                  let limits = line.payload?.rateLimits
            else { continue }

            let windows = [
                limits.primary.map { window($0, id: "session", label: "5ч") },
                limits.secondary.map { window($0, id: "weekly", label: "нед") },
            ].compactMap { $0 }

            guard !windows.isEmpty else { continue }

            let captured = line.timestamp
                .flatMap { CodexTimestamp.date(from: $0) }
                ?? Date(timeIntervalSince1970: 0)

            return RateLimitsEvent(
                capturedAt: captured, planType: limits.planType, windows: windows
            )
        }

        throw ProviderFailure(
            kind: .noData,
            message: "В файлах сессий Codex нет данных о лимитах"
        )
    }

    private static func window(_ w: Line.Window, id: String, label: String) -> LimitWindow {
        LimitWindow(
            id: id,
            label: label,
            percent: w.usedPercent,
            resetsAt: w.resetsAt.map { Date(timeIntervalSince1970: $0) }
        )
    }
}
```

- [ ] **Step 4: Убедиться, что тесты проходят**

Run: `cd Packages/Core && swift test --filter RolloutParserTests`
Expected: PASS, 7 тестов.

- [ ] **Step 5: Проверить на настоящем файле пользователя**

Run:

```bash
cd Packages/Core && cat > /tmp/rollout_check.swift <<'EOF'
// разовая проверка, в репозиторий не коммитится
EOF
swift test --filter RolloutParserTests 2>&1 | tail -3
ls ~/.codex/sessions/**/*.jsonl 2>/dev/null | head -1
```

Expected: тесты зелёные, файл сессии существует. Если файлов нет — это нормально, Task 4 обрабатывает такой случай как `.noData`.

- [ ] **Step 6: Commit**

```bash
git add Packages/Core
git commit -m "Разбор лимитов из файлов сессий Codex"
```

---

### Task 4: Личность Codex и сборка снимка

**Files:**
- Create: `Packages/Core/Sources/CodexProvider/CodexIdentity.swift`
- Create: `Packages/Core/Sources/CodexProvider/CodexProvider.swift`
- Test: `Packages/Core/Tests/CodexProviderTests/CodexIdentityTests.swift`
- Test: `Packages/Core/Tests/CodexProviderTests/CodexProviderTests.swift`

**Interfaces:**
- Consumes: `RolloutParser.latestEvent(inLines:)`, `RateLimitsEvent` из Task 3; `AccountSnapshot`, `AccountRef`, `UsageProvider` из Task 2.
- Produces:
  - `struct CodexIdentity: Sendable { let accountID: String; let displayName: String; let planType: String? }`
  - `enum CodexIdentityReader { static func parse(authJSON: Data) throws -> CodexIdentity }`
  - `protocol CodexFileSystem: Sendable` с `readAuthJSON() throws -> Data` и `latestSessionLines() throws -> [String]`
  - `struct RealCodexFileSystem: CodexFileSystem` — читает `~/.codex`
  - `struct CodexUsageProvider: UsageProvider` — инициализатор `init(fileSystem: CodexFileSystem)`

Личность лежит в `~/.codex/auth.json`, в поле `tokens.id_token` — это JWT. В его теле (вторая часть, base64url) есть верхнеуровневые `name` и `email`, а также объект по ключу `https://api.openai.com/auth` с `chatgpt_plan_type` и `chatgpt_account_id`.

- [ ] **Step 1: Написать падающий тест на разбор личности**

Создать `Packages/Core/Tests/CodexProviderTests/CodexIdentityTests.swift`:

```swift
import Testing
import Foundation
import ProviderKit
@testable import CodexProvider

/// Собирает JWT без подписи — разбирается только тело, подпись не проверяется.
private func makeIDToken(_ payload: [String: Any]) -> String {
    let body = try! JSONSerialization.data(withJSONObject: payload)
    let encoded = body.base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
    return "header.\(encoded).signature"
}

private func makeAuthJSON(_ payload: [String: Any]) -> Data {
    let json: [String: Any] = ["auth_mode": "chatgpt", "tokens": ["id_token": makeIDToken(payload)]]
    return try! JSONSerialization.data(withJSONObject: json)
}

@Test func readsNamePlanAndAccount() throws {
    let data = makeAuthJSON([
        "name": "Tyler Durden",
        "email": "tyler@example.com",
        "https://api.openai.com/auth": [
            "chatgpt_plan_type": "plus",
            "chatgpt_account_id": "d4c3b2a1-f6e5-4b7a-9c8d-5d4c3b2a1f0e",
        ],
    ])
    let identity = try CodexIdentityReader.parse(authJSON: data)
    #expect(identity.displayName == "Tyler Durden")
    #expect(identity.planType == "plus")
    #expect(identity.accountID == "d4c3b2a1-f6e5-4b7a-9c8d-5d4c3b2a1f0e")
}

@Test func fallsBackToEmailWhenNameMissing() throws {
    let data = makeAuthJSON([
        "email": "tyler@example.com",
        "https://api.openai.com/auth": ["chatgpt_plan_type": "pro", "chatgpt_account_id": "acc-1"],
    ])
    let identity = try CodexIdentityReader.parse(authJSON: data)
    #expect(identity.displayName == "tyler@example.com")
}

@Test func fallsBackToAccountIDWhenNothingElseIsThere() throws {
    let data = makeAuthJSON(["https://api.openai.com/auth": ["chatgpt_account_id": "acc-42"]])
    let identity = try CodexIdentityReader.parse(authJSON: data)
    #expect(identity.displayName == "acc-42")
    #expect(identity.planType == nil)
}

@Test func rejectsTokenThatIsNotAJWT() {
    let json: [String: Any] = ["tokens": ["id_token": "нетточек"]]
    let data = try! JSONSerialization.data(withJSONObject: json)
    #expect(throws: ProviderFailure.self) { try CodexIdentityReader.parse(authJSON: data) }
}

@Test func rejectsAuthFileWithoutTokens() {
    let data = try! JSONSerialization.data(withJSONObject: ["auth_mode": "apikey"])
    #expect(throws: ProviderFailure.self) { try CodexIdentityReader.parse(authJSON: data) }
}
```

- [ ] **Step 2: Убедиться, что тест падает**

Run: `cd Packages/Core && swift test --filter CodexIdentityTests`
Expected: FAIL, `cannot find 'CodexIdentityReader' in scope`.

- [ ] **Step 3: Реализовать разбор личности**

Создать `Packages/Core/Sources/CodexProvider/CodexIdentity.swift`:

```swift
import Foundation
import ProviderKit

public struct CodexIdentity: Sendable, Hashable {
    public let accountID: String
    public let displayName: String
    public let planType: String?
}

/// Достаёт личность из `~/.codex/auth.json`.
/// Подпись JWT не проверяется намеренно: файл уже лежит в домашнем каталоге
/// пользователя, а нам нужно только показать имя и тариф.
public enum CodexIdentityReader {
    private static let authClaimKey = "https://api.openai.com/auth"

    public static func parse(authJSON: Data) throws -> CodexIdentity {
        guard
            let root = try? JSONSerialization.jsonObject(with: authJSON) as? [String: Any],
            let tokens = root["tokens"] as? [String: Any],
            let idToken = tokens["id_token"] as? String
        else {
            throw ProviderFailure(kind: .malformed, message: "В auth.json нет tokens.id_token")
        }

        let parts = idToken.split(separator: ".")
        guard parts.count >= 2, let body = decodeSegment(String(parts[1])),
              let claims = try? JSONSerialization.jsonObject(with: body) as? [String: Any]
        else {
            throw ProviderFailure(kind: .malformed, message: "id_token не разобран")
        }

        let auth = claims[authClaimKey] as? [String: Any] ?? [:]
        let accountID = auth["chatgpt_account_id"] as? String ?? "unknown"
        let name = claims["name"] as? String
        let email = claims["email"] as? String

        return CodexIdentity(
            accountID: accountID,
            displayName: name ?? email ?? accountID,
            planType: auth["chatgpt_plan_type"] as? String
        )
    }

    private static func decodeSegment(_ segment: String) -> Data? {
        var s = segment.replacingOccurrences(of: "-", with: "+")
                       .replacingOccurrences(of: "_", with: "/")
        while s.count % 4 != 0 { s += "=" }
        return Data(base64Encoded: s)
    }
}
```

- [ ] **Step 4: Убедиться, что тесты проходят**

Run: `cd Packages/Core && swift test --filter CodexIdentityTests`
Expected: PASS, 5 тестов.

- [ ] **Step 5: Написать падающий тест на провайдер**

Создать `Packages/Core/Tests/CodexProviderTests/CodexProviderTests.swift`:

```swift
import Testing
import Foundation
import ProviderKit
@testable import CodexProvider

private struct StubFS: CodexFileSystem {
    var auth: Data?
    var lines: [String]
    var authError: (any Error)?
    var linesError: (any Error)?

    func readAuthJSON() throws -> Data {
        if let authError { throw authError }
        guard let auth else {
            throw ProviderFailure(kind: .noData, message: "нет auth.json")
        }
        return auth
    }

    func latestSessionLines() throws -> [String] {
        if let linesError { throw linesError }
        return lines
    }
}

private func authFixture() -> Data {
    let payload: [String: Any] = [
        "name": "Tyler Durden",
        "https://api.openai.com/auth": [
            "chatgpt_plan_type": "plus", "chatgpt_account_id": "acc-1",
        ],
    ]
    let body = try! JSONSerialization.data(withJSONObject: payload)
    let seg = body.base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
    let json: [String: Any] = ["tokens": ["id_token": "h.\(seg).s"]]
    return try! JSONSerialization.data(withJSONObject: json)
}

private let limitsLine = """
{"timestamp":"2026-08-27T16:47:37.701Z","type":"event_msg","payload":\
{"type":"token_count","rate_limits":{"limit_id":"codex","plan_type":"plus",\
"primary":{"used_percent":12.0,"window_minutes":300,"resets_at":1787867253},\
"secondary":{"used_percent":32.0,"window_minutes":10080,"resets_at":1788454053}}}}
"""

@Test func discoversOneAccountWhenAuthExists() async throws {
    let provider = CodexUsageProvider(fileSystem: StubFS(auth: authFixture(), lines: []))
    let refs = try await provider.discoverAccounts()
    #expect(refs.count == 1)
    #expect(refs[0].id == "codex/acc-1")
    #expect(refs[0].provider == .codex)
}

@Test func discoversNothingWhenNotLoggedIn() async throws {
    let provider = CodexUsageProvider(fileSystem: StubFS(auth: nil, lines: []))
    let refs = try await provider.discoverAccounts()
    #expect(refs.isEmpty)
}

@Test func buildsSnapshotMarkedAsSnapshotNotLive() async throws {
    let provider = CodexUsageProvider(fileSystem: StubFS(auth: authFixture(), lines: [limitsLine]))
    let ref = try await provider.discoverAccounts()[0]
    let snapshot = try await provider.fetch(ref)

    #expect(snapshot.provider == .codex)
    #expect(snapshot.displayName == "Tyler Durden")
    #expect(snapshot.planLabel == "Plus")
    #expect(snapshot.windows.count == 2)
    #expect(snapshot.failure == nil)
    #expect(snapshot.freshness.isStale == true)
    #expect(snapshot.freshness.capturedAt
            == CodexTimestamp.date(from: "2026-08-27T16:47:37.701Z"))
}

@Test func reportsNoDataAsFailureInsteadOfThrowingAway() async throws {
    let provider = CodexUsageProvider(fileSystem: StubFS(auth: authFixture(), lines: []))
    let ref = try await provider.discoverAccounts()[0]
    let snapshot = try await provider.fetch(ref)

    #expect(snapshot.failure?.kind == .noData)
    #expect(snapshot.windows.isEmpty)
    #expect(snapshot.displayName == "Tyler Durden")
}
```

- [ ] **Step 6: Убедиться, что тест падает**

Run: `cd Packages/Core && swift test --filter CodexProviderTests`
Expected: FAIL, `cannot find 'CodexUsageProvider' in scope`.

- [ ] **Step 7: Реализовать провайдер**

Создать `Packages/Core/Sources/CodexProvider/CodexProvider.swift`:

```swift
import Foundation
import ProviderKit

/// Доступ к файлам Codex вынесен за протокол, чтобы тесты не трогали диск.
public protocol CodexFileSystem: Sendable {
    func readAuthJSON() throws -> Data
    func latestSessionLines() throws -> [String]
}

public struct RealCodexFileSystem: CodexFileSystem {
    private let root: URL

    public init(root: URL = FileManager.default.homeDirectoryForCurrentUser
                              .appendingPathComponent(".codex")) {
        self.root = root
    }

    public func readAuthJSON() throws -> Data {
        try Data(contentsOf: root.appendingPathComponent("auth.json"))
    }

    /// Берёт самый свежий файл сессии. Свежесть — по времени изменения:
    /// Codex дописывает события в конец активного файла.
    public func latestSessionLines() throws -> [String] {
        let sessions = root.appendingPathComponent("sessions")
        guard let walker = FileManager.default.enumerator(
            at: sessions,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey]
        ) else {
            throw ProviderFailure(kind: .noData, message: "Каталог сессий Codex не найден")
        }

        var newest: (URL, Date)?
        for case let url as URL in walker where url.pathExtension == "jsonl" {
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
            guard let modified = values?.contentModificationDate else { continue }
            if newest == nil || modified > newest!.1 { newest = (url, modified) }
        }

        guard let file = newest?.0 else {
            throw ProviderFailure(kind: .noData, message: "Нет файлов сессий Codex")
        }
        let text = try String(contentsOf: file, encoding: .utf8)
        return text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
    }
}

public struct CodexUsageProvider: UsageProvider {
    public let id: ProviderID = .codex
    private let fileSystem: any CodexFileSystem

    public init(fileSystem: any CodexFileSystem = RealCodexFileSystem()) {
        self.fileSystem = fileSystem
    }

    public func discoverAccounts() async throws -> [AccountRef] {
        guard let data = try? fileSystem.readAuthJSON(),
              let identity = try? CodexIdentityReader.parse(authJSON: data)
        else { return [] }

        return [AccountRef(
            id: "codex/\(identity.accountID)", provider: .codex, handle: identity.accountID
        )]
    }

    /// Ошибка чтения лимитов не выбрасывается наружу: аккаунт всё равно надо
    /// показать в списке, просто с пометкой, что данных нет.
    public func fetch(_ ref: AccountRef) async throws -> AccountSnapshot {
        let identity = try CodexIdentityReader.parse(authJSON: try fileSystem.readAuthJSON())
        let plan = identity.planType.map { $0.prefix(1).uppercased() + $0.dropFirst() } ?? "—"

        do {
            let lines = try fileSystem.latestSessionLines()
            let event = try RolloutParser.latestEvent(inLines: lines)
            return AccountSnapshot(
                id: ref.id, provider: .codex,
                displayName: identity.displayName,
                planLabel: event.planType.map { $0.prefix(1).uppercased() + $0.dropFirst() } ?? plan,
                windows: event.windows,
                freshness: .snapshot(event.capturedAt),
                failure: nil
            )
        } catch {
            let failure = error as? ProviderFailure
                ?? ProviderFailure(kind: .noData, message: "Данные Codex недоступны")
            return AccountSnapshot(
                id: ref.id, provider: .codex,
                displayName: identity.displayName, planLabel: plan,
                windows: [], freshness: .snapshot(.distantPast), failure: failure
            )
        }
    }
}
```

- [ ] **Step 8: Убедиться, что все тесты Codex проходят**

Run: `cd Packages/Core && swift test --filter CodexProviderTests`
Expected: PASS, 16 тестов: 7 разбор файлов сессий, 5 личность, 4 провайдер.

- [ ] **Step 9: Commit**

```bash
git add Packages/Core
git commit -m "Провайдер Codex: личность из auth.json и снимок лимитов"
```

---

### Task 5: Разбор ответа Claude об использовании

**Files:**
- Create: `Packages/Core/Sources/ClaudeProvider/ClaudeUsageResponse.swift`
- Delete: `Packages/Core/Sources/ClaudeProvider/ClaudeProvider.swift` (заглушка), `Packages/Core/Tests/ClaudeProviderTests/Placeholder.swift`
- Test: `Packages/Core/Tests/ClaudeProviderTests/ClaudeUsageResponseTests.swift`

**Interfaces:**
- Consumes: `LimitWindow` из Task 2.
- Produces:
  - `enum ClaudeTimestamp { static func date(from text: String) -> Date? }`
  - `enum ClaudeUsageResponse { static func windows(from data: Data) throws -> [LimitWindow] }`

Ответ `/api/oauth/usage` (проверено 2026-08-30). Разбирается массив `limits`, потому что он самоописывающийся; при пустом массиве берутся `five_hour` и `seven_day`. Окна со `scope != null` пропускаются — это срез по одной модели, он дублирует общий недельный лимит и в списке только мешает.

- [ ] **Step 1: Написать падающий тест**

Создать `Packages/Core/Tests/ClaudeProviderTests/ClaudeUsageResponseTests.swift`:

```swift
import Testing
import Foundation
import ProviderKit
@testable import ClaudeProvider

private func data(_ s: String) -> Data { s.data(using: .utf8)! }

private let fullResponse = """
{"five_hour":{"utilization":5.0,"resets_at":"2026-08-30T14:00:00.277644+00:00"},
 "seven_day":{"utilization":23.0,"resets_at":"2026-09-05T10:00:00.277667+00:00"},
 "limits":[
   {"kind":"session","group":"session","percent":5,"severity":"normal",
    "resets_at":"2026-08-30T14:00:00.277644+00:00","scope":null,"is_active":false},
   {"kind":"weekly_all","group":"weekly","percent":23,"severity":"normal",
    "resets_at":"2026-09-05T10:00:00.277667+00:00","scope":null,"is_active":true},
   {"kind":"weekly_scoped","group":"weekly","percent":7,"severity":"normal",
    "resets_at":"2026-09-05T10:00:00.277935+00:00",
    "scope":{"model":{"id":null,"display_name":"Fable"}},"is_active":false}]}
"""

@Test func readsSessionAndWeeklyFromLimits() throws {
    let windows = try ClaudeUsageResponse.windows(from: data(fullResponse))
    #expect(windows.count == 2)

    #expect(windows[0].id == "session")
    #expect(windows[0].label == "5ч")
    #expect(windows[0].percent == 5)

    #expect(windows[1].id == "weekly")
    #expect(windows[1].label == "нед")
    #expect(windows[1].percent == 23)
}

@Test func dropsPerModelScopedWindow() throws {
    let windows = try ClaudeUsageResponse.windows(from: data(fullResponse))
    #expect(windows.contains { $0.percent == 7 } == false)
}

@Test func parsesResetTimeWithFractionalSeconds() throws {
    let windows = try ClaudeUsageResponse.windows(from: data(fullResponse))
    let expected = ClaudeTimestamp.date(from: "2026-08-30T14:00:00.277644+00:00")
    #expect(windows[0].resetsAt == expected)
}

@Test func fallsBackToLegacyFieldsWhenLimitsIsEmpty() throws {
    let legacy = """
    {"five_hour":{"utilization":41.0,"resets_at":"2026-08-30T14:00:00.277644+00:00"},
     "seven_day":{"utilization":66.0,"resets_at":"2026-09-05T10:00:00.277667+00:00"},
     "limits":[]}
    """
    let windows = try ClaudeUsageResponse.windows(from: data(legacy))
    #expect(windows.count == 2)
    #expect(windows[0].percent == 41)
    #expect(windows[1].percent == 66)
}

@Test func toleratesUnknownKindWithoutLosingKnownOnes() throws {
    let mixed = """
    {"limits":[
      {"kind":"session","percent":9,"resets_at":"2026-08-30T14:00:00.277644+00:00","scope":null},
      {"kind":"nimbus_quill","percent":3,"resets_at":null,"scope":null}]}
    """
    let windows = try ClaudeUsageResponse.windows(from: data(mixed))
    #expect(windows.count == 1)
    #expect(windows[0].id == "session")
}

@Test func failsOnGarbage() {
    #expect(throws: ProviderFailure.self) {
        try ClaudeUsageResponse.windows(from: data("не json"))
    }
}

@Test func failsWhenNeitherLimitsNorLegacyPresent() {
    #expect(throws: ProviderFailure.self) {
        try ClaudeUsageResponse.windows(from: data(#"{"limits":[]}"#))
    }
}
```

- [ ] **Step 2: Убедиться, что тест падает**

Run: `cd Packages/Core && swift test --filter ClaudeUsageResponseTests`
Expected: FAIL, `cannot find 'ClaudeUsageResponse' in scope`.

- [ ] **Step 3: Реализовать разбор**

```bash
rm Packages/Core/Sources/ClaudeProvider/ClaudeProvider.swift
rm Packages/Core/Tests/ClaudeProviderTests/Placeholder.swift
```

Создать `Packages/Core/Sources/ClaudeProvider/ClaudeUsageResponse.swift`:

```swift
import Foundation
import ProviderKit

/// Anthropic отдаёт время с микросекундами и смещением:
/// «2026-08-30T14:00:00.277644+00:00». Проверено, что разбирается и такой вид,
/// и «…701Z» с миллисекундами.
///
/// Взят `Date.ISO8601FormatStyle`, а не `ISO8601DateFormatter`: последний не
/// `Sendable`, и `static let` с ним не проходит проверку конкурентности Swift 6.
public enum ClaudeTimestamp {
    private static let style = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    public static func date(from text: String) -> Date? { try? style.parse(text) }
}

public enum ClaudeUsageResponse {

    private struct Body: Decodable {
        let fiveHour: Legacy?
        let sevenDay: Legacy?
        let limits: [Limit]?

        enum CodingKeys: String, CodingKey {
            case fiveHour = "five_hour", sevenDay = "seven_day", limits
        }

        struct Legacy: Decodable {
            let utilization: Double
            let resetsAt: String?
            enum CodingKeys: String, CodingKey { case utilization, resetsAt = "resets_at" }
        }

        struct Limit: Decodable {
            let kind: String
            let percent: Double
            let resetsAt: String?
            let scope: Scope?
            enum CodingKeys: String, CodingKey { case kind, percent, resetsAt = "resets_at", scope }
            struct Scope: Decodable {}
        }
    }

    public static func windows(from data: Data) throws -> [LimitWindow] {
        guard let body = try? JSONDecoder().decode(Body.self, from: data) else {
            throw ProviderFailure(kind: .malformed, message: "Ответ об использовании не разобран")
        }

        let fromLimits = (body.limits ?? []).compactMap(window(from:))
        if !fromLimits.isEmpty { return sorted(fromLimits) }

        // Массив limits пуст — берём старые поля.
        var legacy: [LimitWindow] = []
        if let five = body.fiveHour {
            legacy.append(LimitWindow(
                id: "session", label: "5ч", percent: five.utilization,
                resetsAt: five.resetsAt.flatMap { ClaudeTimestamp.date(from: $0) }
            ))
        }
        if let week = body.sevenDay {
            legacy.append(LimitWindow(
                id: "weekly", label: "нед", percent: week.utilization,
                resetsAt: week.resetsAt.flatMap { ClaudeTimestamp.date(from: $0) }
            ))
        }

        guard !legacy.isEmpty else {
            throw ProviderFailure(kind: .malformed, message: "В ответе нет ни одного окна лимита")
        }
        return sorted(legacy)
    }

    /// Срез по одной модели (`scope != null`) пропускаем: он дублирует общий
    /// недельный лимит и в компактном списке только шумит.
    private static func window(from limit: Body.Limit) -> LimitWindow? {
        guard limit.scope == nil else { return nil }
        let reset = limit.resetsAt.flatMap { ClaudeTimestamp.date(from: $0) }

        switch limit.kind {
        case "session":
            return LimitWindow(id: "session", label: "5ч", percent: limit.percent, resetsAt: reset)
        case "weekly_all":
            return LimitWindow(id: "weekly", label: "нед", percent: limit.percent, resetsAt: reset)
        default:
            return nil   // незнакомый вид окна игнорируем, но остальные сохраняем
        }
    }

    /// Порядок строк в карточке: сначала пятичасовое окно, потом недельное.
    /// Задан явной таблицей, а не сравнением одного поля: предикат вида
    /// `$0.id == "session"` не даёт строгого порядка, и результат сортировки
    /// становится неопределённым.
    private static func sorted(_ windows: [LimitWindow]) -> [LimitWindow] {
        let rank = ["session": 0, "weekly": 1]
        return windows.sorted { (rank[$0.id] ?? 99) < (rank[$1.id] ?? 99) }
    }
}
```

- [ ] **Step 4: Убедиться, что тесты проходят**

Run: `cd Packages/Core && swift test --filter ClaudeUsageResponseTests`
Expected: PASS, 7 тестов.

- [ ] **Step 5: Commit**

```bash
git add Packages/Core
git commit -m "Разбор ответа Claude об использовании лимитов"
```

---

### Task 6: Сетевой слой Claude, профиль и сборка снимка

**Files:**
- Create: `Packages/Core/Sources/ClaudeProvider/HTTPClient.swift`
- Create: `Packages/Core/Sources/ClaudeProvider/ClaudeProfileResponse.swift`
- Create: `Packages/Core/Sources/ClaudeProvider/ClaudeProvider.swift`
- Test: `Packages/Core/Tests/ClaudeProviderTests/ClaudeProfileResponseTests.swift`
- Test: `Packages/Core/Tests/ClaudeProviderTests/ClaudeProviderTests.swift`

**Interfaces:**
- Consumes: `ClaudeUsageResponse.windows(from:)` из Task 5; `AccountSnapshot`, `UsageProvider` из Task 2.
- Produces:
  - `protocol HTTPClient: Sendable { func get(_ url: URL, headers: [String: String]) async throws -> (Data, Int) }`
  - `struct URLSessionHTTPClient: HTTPClient`
  - `struct ClaudeProfile: Sendable { let uuid, displayName, planLabel: String }`
  - `enum ClaudeProfileResponse { static func parse(_ data: Data) throws -> ClaudeProfile }`
  - `protocol ClaudeTokenSource: Sendable { func accessToken(for handle: String) async throws -> String }`
  - `struct ClaudeUsageProvider: UsageProvider` — `init(http:tokens:knownAccounts:)`

Адреса (проверены 2026-08-30):
`https://api.anthropic.com/api/oauth/usage`, `https://api.anthropic.com/api/oauth/profile`.
Заголовки: `Authorization: Bearer <token>`, `anthropic-beta: oauth-2025-04-20`,
`User-Agent: claude-cli/2.0.0 (external, cli)`.

Подпись тарифа строится из `organization.rate_limit_tier`:
`default_claude_max_20x` → `Max 20x`, `default_claude_max_5x` → `Max 5x`,
`default_claude_pro` → `Pro`; неизвестное значение отдаётся как есть.

- [ ] **Step 1: Написать падающий тест на разбор профиля**

Создать `Packages/Core/Tests/ClaudeProviderTests/ClaudeProfileResponseTests.swift`:

```swift
import Testing
import Foundation
import ProviderKit
@testable import ClaudeProvider

private func data(_ s: String) -> Data { s.data(using: .utf8)! }

@Test func readsIdentityAndPlan() throws {
    let body = """
    {"account":{"uuid":"a1b2c3d4-e5f6-4a7b-8c9d-0e1f2a3b4c5d","display_name":"Alex",
      "email":"alex@example.com","has_claude_max":true},
     "organization":{"uuid":"8033be31","name":"org","rate_limit_tier":"default_claude_max_20x"}}
    """
    let profile = try ClaudeProfileResponse.parse(data(body))
    #expect(profile.uuid == "a1b2c3d4-e5f6-4a7b-8c9d-0e1f2a3b4c5d")
    #expect(profile.displayName == "alex@example.com")
    #expect(profile.planLabel == "Max 20x")
}

@Test func mapsKnownTiersToShortLabels() throws {
    func label(_ tier: String) throws -> String {
        let body = """
        {"account":{"uuid":"u","email":"e@x.y"},"organization":{"rate_limit_tier":"\(tier)"}}
        """
        return try ClaudeProfileResponse.parse(data(body)).planLabel
    }
    #expect(try label("default_claude_max_20x") == "Max 20x")
    #expect(try label("default_claude_max_5x") == "Max 5x")
    #expect(try label("default_claude_pro") == "Pro")
}

@Test func keepsUnknownTierVerbatim() throws {
    let body = """
    {"account":{"uuid":"u","email":"e@x.y"},"organization":{"rate_limit_tier":"nova_plan"}}
    """
    #expect(try ClaudeProfileResponse.parse(data(body)).planLabel == "nova_plan")
}

@Test func fallsBackToDisplayNameWhenEmailMissing() throws {
    let body = """
    {"account":{"uuid":"u","display_name":"Иван"},"organization":{"rate_limit_tier":"default_claude_pro"}}
    """
    #expect(try ClaudeProfileResponse.parse(data(body)).displayName == "Иван")
}

@Test func failsWithoutAccountUUID() {
    #expect(throws: ProviderFailure.self) {
        try ClaudeProfileResponse.parse(data(#"{"organization":{}}"#))
    }
}
```

- [ ] **Step 2: Убедиться, что тест падает**

Run: `cd Packages/Core && swift test --filter ClaudeProfileResponseTests`
Expected: FAIL, `cannot find 'ClaudeProfileResponse' in scope`.

- [ ] **Step 3: Реализовать сеть и профиль**

Создать `Packages/Core/Sources/ClaudeProvider/HTTPClient.swift`:

```swift
import Foundation
import ProviderKit

/// Минимум, который нужен провайдеру от сети. Отдельный протокол — чтобы тесты
/// не ходили в интернет.
public protocol HTTPClient: Sendable {
    func get(_ url: URL, headers: [String: String]) async throws -> (Data, Int)
    func post(_ url: URL, headers: [String: String], body: Data) async throws -> (Data, Int)
}

public struct URLSessionHTTPClient: HTTPClient {
    private let session: URLSession

    public init(session: URLSession = .shared) { self.session = session }

    public func get(_ url: URL, headers: [String: String]) async throws -> (Data, Int) {
        try await send(url, method: "GET", headers: headers, body: nil)
    }

    public func post(
        _ url: URL, headers: [String: String], body: Data
    ) async throws -> (Data, Int) {
        try await send(url, method: "POST", headers: headers, body: body)
    }

    private func send(
        _ url: URL, method: String, headers: [String: String], body: Data?
    ) async throws -> (Data, Int) {
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.httpMethod = method
        request.httpBody = body
        for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
        do {
            let (data, response) = try await session.data(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            return (data, code)
        } catch {
            throw ProviderFailure(kind: .network, message: "Сеть недоступна")
        }
    }
}
```

Создать `Packages/Core/Sources/ClaudeProvider/ClaudeProfileResponse.swift`:

```swift
import Foundation
import ProviderKit

public struct ClaudeProfile: Sendable, Hashable {
    public let uuid: String
    public let displayName: String
    public let planLabel: String
}

public enum ClaudeProfileResponse {

    private struct Body: Decodable {
        let account: Account?
        let organization: Organization?

        struct Account: Decodable {
            let uuid: String?
            let displayName: String?
            let email: String?
            enum CodingKeys: String, CodingKey {
                case uuid, displayName = "display_name", email
            }
        }

        struct Organization: Decodable {
            let rateLimitTier: String?
            enum CodingKeys: String, CodingKey { case rateLimitTier = "rate_limit_tier" }
        }
    }

    public static func parse(_ data: Data) throws -> ClaudeProfile {
        guard let body = try? JSONDecoder().decode(Body.self, from: data),
              let uuid = body.account?.uuid
        else {
            throw ProviderFailure(kind: .malformed, message: "Профиль не разобран")
        }

        return ClaudeProfile(
            uuid: uuid,
            displayName: body.account?.email ?? body.account?.displayName ?? uuid,
            planLabel: planLabel(for: body.organization?.rateLimitTier)
        )
    }

    private static func planLabel(for tier: String?) -> String {
        switch tier {
        case "default_claude_max_20x": "Max 20x"
        case "default_claude_max_5x":  "Max 5x"
        case "default_claude_pro":     "Pro"
        case let other?:               other
        case nil:                      "—"
        }
    }
}
```

- [ ] **Step 4: Убедиться, что тесты профиля проходят**

Run: `cd Packages/Core && swift test --filter ClaudeProfileResponseTests`
Expected: PASS, 5 тестов.

- [ ] **Step 5: Написать падающий тест на провайдер**

Создать `Packages/Core/Tests/ClaudeProviderTests/ClaudeProviderTests.swift`:

```swift
import Testing
import Foundation
import ProviderKit
@testable import ClaudeProvider

private struct StubHTTP: HTTPClient {
    let byPath: [String: (Data, Int)]

    func get(_ url: URL, headers: [String: String]) async throws -> (Data, Int) {
        guard headers["Authorization"]?.hasPrefix("Bearer ") == true else {
            Issue.record("Запрос ушёл без токена")
            return (Data(), 401)
        }
        return byPath[url.path] ?? (Data(), 404)
    }

    func post(_ url: URL, headers: [String: String], body: Data) async throws -> (Data, Int) {
        byPath[url.path] ?? (Data(), 404)
    }
}

private struct StubTokens: ClaudeTokenSource {
    var token: String? = "tok"
    func accessToken(for handle: String) async throws -> String {
        guard let token else {
            throw ProviderFailure(kind: .needsLogin, message: "Нужен вход")
        }
        return token
    }
}

private func d(_ s: String) -> Data { s.data(using: .utf8)! }

private let profileBody = d("""
{"account":{"uuid":"u-1","email":"a@b.c"},"organization":{"rate_limit_tier":"default_claude_max_20x"}}
""")

private let usageBody = d("""
{"limits":[
  {"kind":"session","percent":5,"resets_at":"2026-08-30T14:00:00.277644+00:00","scope":null},
  {"kind":"weekly_all","percent":23,"resets_at":"2026-09-05T10:00:00.277667+00:00","scope":null}]}
""")

private func provider(_ http: StubHTTP, tokens: StubTokens = StubTokens()) -> ClaudeUsageProvider {
    ClaudeUsageProvider(
        http: http, tokens: tokens,
        knownAccounts: [AccountRef(id: "claude/u-1", provider: .claude, handle: "u-1")]
    )
}

@Test func buildsLiveSnapshot() async throws {
    let http = StubHTTP(byPath: [
        "/api/oauth/profile": (profileBody, 200),
        "/api/oauth/usage": (usageBody, 200),
    ])
    let ref = try await provider(http).discoverAccounts()[0]
    let snapshot = try await provider(http).fetch(ref)

    #expect(snapshot.displayName == "a@b.c")
    #expect(snapshot.planLabel == "Max 20x")
    #expect(snapshot.windows.count == 2)
    #expect(snapshot.windows[0].percent == 5)
    #expect(snapshot.windows[1].percent == 23)
    #expect(snapshot.failure == nil)
    #expect(snapshot.freshness.isStale == false)
}

@Test func reportsNeedsLoginOn401() async throws {
    let http = StubHTTP(byPath: [
        "/api/oauth/profile": (profileBody, 200),
        "/api/oauth/usage": (d("{}"), 401),
    ])
    let ref = AccountRef(id: "claude/u-1", provider: .claude, handle: "u-1")
    let snapshot = try await provider(http).fetch(ref)

    #expect(snapshot.failure?.kind == .needsLogin)
    #expect(snapshot.windows.isEmpty)
}

@Test func reportsNetworkFailureOn500() async throws {
    let http = StubHTTP(byPath: [
        "/api/oauth/profile": (profileBody, 200),
        "/api/oauth/usage": (d("{}"), 500),
    ])
    let ref = AccountRef(id: "claude/u-1", provider: .claude, handle: "u-1")
    let snapshot = try await provider(http).fetch(ref)
    #expect(snapshot.failure?.kind == .network)
}

@Test func reportsNeedsLoginWhenTokenIsGone() async throws {
    let http = StubHTTP(byPath: [:])
    let ref = AccountRef(id: "claude/u-1", provider: .claude, handle: "u-1")
    let snapshot = try await provider(http, tokens: StubTokens(token: nil)).fetch(ref)

    #expect(snapshot.failure?.kind == .needsLogin)
    #expect(snapshot.displayName == "claude/u-1")   // имени взять неоткуда
}

@Test func neverPutsTokenIntoFailureMessage() async throws {
    let http = StubHTTP(byPath: [
        "/api/oauth/profile": (profileBody, 200),
        "/api/oauth/usage": (d("{}"), 401),
    ])
    let ref = AccountRef(id: "claude/u-1", provider: .claude, handle: "u-1")
    let snapshot = try await provider(http).fetch(ref)
    #expect(snapshot.failure?.message.contains("tok") == false)
}
```

- [ ] **Step 6: Убедиться, что тест падает**

Run: `cd Packages/Core && swift test --filter ClaudeProviderTests`
Expected: FAIL, `cannot find 'ClaudeUsageProvider' in scope`.

- [ ] **Step 7: Реализовать провайдер**

Создать `Packages/Core/Sources/ClaudeProvider/ClaudeProvider.swift`:

```swift
import Foundation
import ProviderKit

/// Откуда провайдер берёт токен. Реализация живёт в `Credentials` (Task 7):
/// для зеркала CLI это чтение Keychain, для своего входа — продление по refresh.
public protocol ClaudeTokenSource: Sendable {
    func accessToken(for handle: String) async throws -> String
}

public struct ClaudeUsageProvider: UsageProvider {
    public let id: ProviderID = .claude

    private let http: any HTTPClient
    private let tokens: any ClaudeTokenSource
    private let knownAccounts: [AccountRef]

    private static let usageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    private static let profileURL = URL(string: "https://api.anthropic.com/api/oauth/profile")!

    public init(
        http: any HTTPClient = URLSessionHTTPClient(),
        tokens: any ClaudeTokenSource,
        knownAccounts: [AccountRef]
    ) {
        self.http = http
        self.tokens = tokens
        self.knownAccounts = knownAccounts
    }

    public func discoverAccounts() async throws -> [AccountRef] { knownAccounts }

    public func fetch(_ ref: AccountRef) async throws -> AccountSnapshot {
        let token: String
        do {
            token = try await tokens.accessToken(for: ref.handle)
        } catch {
            return broken(ref, name: ref.id, plan: "—", failure: failure(from: error))
        }

        let headers = [
            "Authorization": "Bearer \(token)",
            "anthropic-beta": "oauth-2025-04-20",
            "User-Agent": "claude-cli/2.0.0 (external, cli)",
        ]

        // Профиль нужен для имени и тарифа; без него аккаунт всё равно показываем.
        var name = ref.id
        var plan = "—"
        if let (data, code) = try? await http.get(Self.profileURL, headers: headers), code == 200,
           let profile = try? ClaudeProfileResponse.parse(data) {
            name = profile.displayName
            plan = profile.planLabel
        }

        do {
            let (data, code) = try await http.get(Self.usageURL, headers: headers)
            switch code {
            case 200:
                let windows = try ClaudeUsageResponse.windows(from: data)
                return AccountSnapshot(
                    id: ref.id, provider: .claude, displayName: name, planLabel: plan,
                    windows: windows, freshness: .live(Date()), failure: nil
                )
            case 401, 403:
                return broken(ref, name: name, plan: plan, failure: ProviderFailure(
                    kind: .needsLogin, message: "Нужен вход в аккаунт"
                ))
            default:
                return broken(ref, name: name, plan: plan, failure: ProviderFailure(
                    kind: .network, message: "Сервис ответил \(code)"
                ))
            }
        } catch {
            return broken(ref, name: name, plan: plan, failure: failure(from: error))
        }
    }

    private func broken(
        _ ref: AccountRef, name: String, plan: String, failure: ProviderFailure
    ) -> AccountSnapshot {
        AccountSnapshot(
            id: ref.id, provider: .claude, displayName: name, planLabel: plan,
            windows: [], freshness: .live(Date()), failure: failure
        )
    }

    /// Сообщение об ошибке всегда своё: посторонний текст может протащить токен.
    private func failure(from error: any Error) -> ProviderFailure {
        if let known = error as? ProviderFailure { return known }
        return ProviderFailure(kind: .network, message: "Не удалось получить данные")
    }
}
```

- [ ] **Step 8: Убедиться, что все тесты Claude проходят**

Run: `cd Packages/Core && swift test --filter ClaudeProviderTests`
Expected: PASS, 5 тестов провайдера.

- [ ] **Step 9: Прогнать весь пакет**

Run: `cd Packages/Core && swift test`
Expected: PASS, все тесты (ProviderKit 14, Codex 16, Claude 17).

- [ ] **Step 10: Commit**

```bash
git add Packages/Core
git commit -m "Провайдер Claude: профиль, лимиты и разбор ошибок"
```

---

### Task 7: Хранилище учётных данных

**Files:**
- Create: `Packages/Core/Sources/Credentials/KeychainAccess.swift`
- Create: `Packages/Core/Sources/Credentials/CredentialStore.swift`
- Delete: `Packages/Core/Sources/Credentials/Credentials.swift` (заглушка), `Packages/Core/Tests/CredentialsTests/Placeholder.swift`
- Test: `Packages/Core/Tests/CredentialsTests/CredentialStoreTests.swift`

**Interfaces:**
- Consumes: `ProviderFailure`, `AccountRef` из Task 2; `ClaudeTokenSource`, `HTTPClient` из Task 6.
- Produces:
  - `protocol KeychainAccess: Sendable` — `read(service:) async throws -> Data?`, `write(_:service:) async throws`
  - `struct SystemKeychain: KeychainAccess`
  - `struct StoredAccount: Sendable, Codable` — `id, handle, displayName, refreshToken?`
  - `protocol TokenRefreshing: Sendable` — `refresh(refreshToken:) async throws -> RefreshedTokens`
  - `struct RefreshedTokens: Sendable` — `accessToken: String, refreshToken: String?`
  - `struct AnthropicTokenRefresher: TokenRefreshing` — `init(http:)`
  - `actor CredentialStore: ClaudeTokenSource` — `init(keychain:refresher:)`, `load()`, `knownRefs()`, `syncWithCLI(profileUUID:displayName:)`, `currentCLIToken()`, `accessToken(for:)`

**Ключевое правило — от него зависит, что пользователь увидит все три подписки, и что при этом не сломается вход в CLI:**

- **Активный аккаунт** — тот, чей `uuid` совпадает с тем, что сейчас лежит в
  элементе Keychain `Claude Code-credentials`. Его токен берётся оттуда при
  каждом обращении и **никогда не продлевается**: ротация refresh-токена
  оставила бы CLI со старым токеном, и пользователь бы разлогинился.
- **Неактивные аккаунты** — те, куда пользователь заходил раньше. Их
  refresh-токен приложение сохранило себе, пока они были активны, и теперь
  продлевает само. CLI ими уже не пользуется, поэтому ротация никому не мешает.

Отсюда обязанность `syncWithCLI`: при каждом опросе снимать копию текущего
refresh-токена. Без этого при переключении на другой аккаунт предыдущий станет
недостижим — его токен в Keychain будет затёрт.

Адрес продления (проверен 2026-08-30): `POST https://api.anthropic.com/v1/oauth/token`,
тело `{"grant_type":"refresh_token","refresh_token":…,"client_id":…}`. На подложный
токен отвечает `400 {"error":"invalid_grant"}`, то есть форма запроса верна.
`client_id` — `9d1c250a-e61b-44d9-88ed-5944d1962f5e`.

- [ ] **Step 1: Написать падающий тест**

Создать `Packages/Core/Tests/CredentialsTests/CredentialStoreTests.swift`:

```swift
import Testing
import Foundation
import ProviderKit
@testable import Credentials

private actor MemoryKeychain: KeychainAccess {
    private var items: [String: Data] = [:]
    private(set) var writes: [String] = []

    init(_ seed: [String: Data] = [:]) { items = seed }

    func read(service: String) throws -> Data? { items[service] }
    func write(_ data: Data, service: String) throws {
        items[service] = data
        writes.append(service)
    }
    func writeCount(for service: String) -> Int { writes.filter { $0 == service }.count }

    /// Подложить значение «снаружи» — так, как это делает сам CLI.
    /// В отличие от `write`, в счётчик записей приложения не попадает.
    func seed(_ data: Data, service: String) { items[service] = data }
}

private actor SpyRefresher: TokenRefreshing {
    private(set) var calls: [String] = []
    var result: RefreshedTokens? = RefreshedTokens(accessToken: "fresh", refreshToken: "rot")

    func refresh(refreshToken: String) async throws -> RefreshedTokens {
        calls.append(refreshToken)
        guard let result else {
            throw ProviderFailure(kind: .needsLogin, message: "Нужен вход в аккаунт")
        }
        return result
    }
    func setResult(_ value: RefreshedTokens?) { result = value }
}

private func cliCredentials(token: String, refresh: String = "refresh-A") -> Data {
    let json: [String: Any] = ["claudeAiOauth": [
        "accessToken": token,
        "refreshToken": refresh,
        "expiresAt": 4_102_444_800_000,
        "subscriptionType": "max",
    ]]
    return try! JSONSerialization.data(withJSONObject: json)
}

private func makeStore(
    _ keychain: MemoryKeychain, _ refresher: SpyRefresher = SpyRefresher()
) async -> CredentialStore {
    let store = CredentialStore(keychain: keychain, refresher: refresher)
    await store.load()
    return store
}

@Test func activeAccountReadsTokenStraightFromCLI() async throws {
    let keychain = MemoryKeychain([CredentialStore.cliService: cliCredentials(token: "live-tok")])
    let store = await makeStore(keychain)
    try await store.syncWithCLI(profileUUID: "u-1", displayName: "a@b.c")

    #expect(try await store.accessToken(for: "u-1") == "live-tok")
}

@Test func activeAccountIsNeverRefreshedNorWrittenBack() async throws {
    let keychain = MemoryKeychain([CredentialStore.cliService: cliCredentials(token: "live-tok")])
    let refresher = SpyRefresher()
    let store = await makeStore(keychain, refresher)
    try await store.syncWithCLI(profileUUID: "u-1", displayName: "a@b.c")
    _ = try await store.accessToken(for: "u-1")

    // Продление активного аккаунта разлогинило бы CLI — его быть не должно.
    #expect(await refresher.calls.isEmpty)
    #expect(await keychain.writeCount(for: CredentialStore.cliService) == 0)
}

@Test func picksUpFreshTokenAfterCLIRefreshesItself() async throws {
    let keychain = MemoryKeychain([CredentialStore.cliService: cliCredentials(token: "old")])
    let store = await makeStore(keychain)
    try await store.syncWithCLI(profileUUID: "u-1", displayName: "a@b.c")
    #expect(try await store.accessToken(for: "u-1") == "old")

    await keychain.seed(cliCredentials(token: "new"), service: CredentialStore.cliService)
    #expect(try await store.accessToken(for: "u-1") == "new")
}

@Test func keepsRefreshTokenSoAccountSurvivesSwitching() async throws {
    let keychain = MemoryKeychain([
        CredentialStore.cliService: cliCredentials(token: "tok-A", refresh: "refresh-A")
    ])
    let refresher = SpyRefresher()
    let store = await makeStore(keychain, refresher)
    try await store.syncWithCLI(profileUUID: "u-1", displayName: "a@b.c")

    // Пользователь сделал /login во второй аккаунт: в Keychain теперь другой токен.
    await keychain.seed(
        cliCredentials(token: "tok-B", refresh: "refresh-B"), service: CredentialStore.cliService
    )
    try await store.syncWithCLI(profileUUID: "u-2", displayName: "b@b.c")

    // Первый аккаунт стал неактивным — его продлеваем сохранённым токеном.
    #expect(try await store.accessToken(for: "u-1") == "fresh")
    #expect(await refresher.calls == ["refresh-A"])

    // Второй теперь активный — читается напрямую, без продления.
    #expect(try await store.accessToken(for: "u-2") == "tok-B")
    #expect(await refresher.calls == ["refresh-A"])
}

@Test func storesRotatedRefreshTokenForNextTime() async throws {
    let keychain = MemoryKeychain([
        CredentialStore.cliService: cliCredentials(token: "tok-A", refresh: "refresh-A")
    ])
    let refresher = SpyRefresher()
    let store = await makeStore(keychain, refresher)
    try await store.syncWithCLI(profileUUID: "u-1", displayName: "a@b.c")
    await keychain.seed(cliCredentials(token: "tok-B", refresh: "refresh-B"),
                        service: CredentialStore.cliService)
    try await store.syncWithCLI(profileUUID: "u-2", displayName: "b@b.c")

    _ = try await store.accessToken(for: "u-1")
    _ = try await store.accessToken(for: "u-1")

    // Второй раз идём уже с новым токеном, а не со сгоревшим старым.
    #expect(await refresher.calls == ["refresh-A", "rot"])
}

@Test func bothAccountsStayVisibleAfterSwitching() async throws {
    let keychain = MemoryKeychain([CredentialStore.cliService: cliCredentials(token: "t")])
    let store = await makeStore(keychain)
    try await store.syncWithCLI(profileUUID: "u-1", displayName: "a@b.c")
    try await store.syncWithCLI(profileUUID: "u-2", displayName: "b@b.c")

    #expect(await store.knownRefs().map(\.handle).sorted() == ["u-1", "u-2"])
}

@Test func syncingSameAccountTwiceDoesNotDuplicate() async throws {
    let keychain = MemoryKeychain([CredentialStore.cliService: cliCredentials(token: "t")])
    let store = await makeStore(keychain)
    try await store.syncWithCLI(profileUUID: "u-1", displayName: "a@b.c")
    try await store.syncWithCLI(profileUUID: "u-1", displayName: "a@b.c")

    #expect(await store.knownRefs().count == 1)
}

@Test func remembersAccountsAcrossRestart() async throws {
    let keychain = MemoryKeychain([CredentialStore.cliService: cliCredentials(token: "t")])
    let first = await makeStore(keychain)
    try await first.syncWithCLI(profileUUID: "u-1", displayName: "a@b.c")

    let second = await makeStore(keychain)
    #expect(await second.knownRefs().map(\.handle) == ["u-1"])
}

@Test func deadRefreshTokenMeansNeedsLogin() async throws {
    let keychain = MemoryKeychain([CredentialStore.cliService: cliCredentials(token: "tok-A")])
    let refresher = SpyRefresher()
    await refresher.setResult(nil)
    let store = await makeStore(keychain, refresher)
    try await store.syncWithCLI(profileUUID: "u-1", displayName: "a@b.c")
    await keychain.seed(cliCredentials(token: "tok-B", refresh: "refresh-B"),
                        service: CredentialStore.cliService)
    try await store.syncWithCLI(profileUUID: "u-2", displayName: "b@b.c")

    await #expect(throws: ProviderFailure.self) {
        _ = try await store.accessToken(for: "u-1")
    }
}

@Test func unknownAccountMeansNeedsLogin() async {
    let store = await makeStore(MemoryKeychain())
    await #expect(throws: ProviderFailure.self) {
        _ = try await store.accessToken(for: "unknown")
    }
}
```

- [ ] **Step 2: Убедиться, что тест падает**

Run: `cd Packages/Core && swift test --filter CredentialStoreTests`
Expected: FAIL, `cannot find 'CredentialStore' in scope`.

- [ ] **Step 3: Реализовать**

```bash
rm Packages/Core/Sources/Credentials/Credentials.swift
rm Packages/Core/Tests/CredentialsTests/Placeholder.swift
```

Создать `Packages/Core/Sources/Credentials/KeychainAccess.swift`:

```swift
import Foundation
import Security
import ProviderKit

public protocol KeychainAccess: Sendable {
    func read(service: String) async throws -> Data?
    func write(_ data: Data, service: String) async throws
}

public struct SystemKeychain: KeychainAccess {
    public init() {}

    public func read(service: String) throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else {
            throw ProviderFailure(kind: .needsLogin, message: "Keychain недоступен")
        }
        return data
    }

    public func write(_ data: Data, service: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
        ]
        let attributes: [String: Any] = [kSecValueData as String: data]

        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var insert = query
            insert[kSecValueData as String] = data
            guard SecItemAdd(insert as CFDictionary, nil) == errSecSuccess else {
                throw ProviderFailure(kind: .needsLogin, message: "Не удалось записать в Keychain")
            }
            return
        }
        guard status == errSecSuccess else {
            throw ProviderFailure(kind: .needsLogin, message: "Не удалось обновить Keychain")
        }
    }
}
```

Создать `Packages/Core/Sources/Credentials/CredentialStore.swift`:

```swift
import Foundation
import ProviderKit
import ClaudeProvider

public struct StoredAccount: Sendable, Codable, Hashable {
    public let id: String
    public let handle: String
    public var displayName: String
    /// Копия refresh-токена, снятая пока аккаунт был активен в CLI.
    /// Ради неё и существует `syncWithCLI`.
    public var refreshToken: String?
}

public struct RefreshedTokens: Sendable, Hashable {
    public let accessToken: String
    public let refreshToken: String?

    public init(accessToken: String, refreshToken: String?) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
    }
}

public protocol TokenRefreshing: Sendable {
    func refresh(refreshToken: String) async throws -> RefreshedTokens
}

/// Продление сессии Anthropic. Адрес и форма тела проверены 2026-08-30:
/// на подложный токен приходит `400 invalid_grant`.
public struct AnthropicTokenRefresher: TokenRefreshing {
    private static let endpoint = URL(string: "https://api.anthropic.com/v1/oauth/token")!
    private static let clientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"

    private let http: any HTTPClient

    public init(http: any HTTPClient = URLSessionHTTPClient()) { self.http = http }

    public func refresh(refreshToken: String) async throws -> RefreshedTokens {
        let body = try JSONSerialization.data(withJSONObject: [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": Self.clientID,
        ])

        let (data, code) = try await http.post(
            Self.endpoint, headers: ["Content-Type": "application/json"], body: body
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

/// Список аккаунтов и выдача токенов.
///
/// Аккаунт, активный в CLI прямо сейчас, читается только на чтение: продление
/// по refresh-токену может привести к ротации на стороне сервера, и тогда CLI
/// останется со старым токеном и разлогинится. Неактивные аккаунты такой связи
/// с CLI не имеют, поэтому продлеваются своей сохранённой копией токена —
/// благодаря этому все подписки видны одновременно.
public actor CredentialStore: ClaudeTokenSource {
    public static let cliService = "Claude Code-credentials"
    public static let ownService = "StatusChecker-accounts"

    private let keychain: any KeychainAccess
    private let refresher: any TokenRefreshing
    private var accounts: [StoredAccount] = []

    public init(keychain: any KeychainAccess, refresher: any TokenRefreshing) {
        self.keychain = keychain
        self.refresher = refresher
    }

    /// Читает сохранённый список. Вызывается один раз сразу после создания.
    public func load() async {
        guard let data = try? await keychain.read(service: Self.ownService),
              let stored = try? JSONDecoder().decode([StoredAccount].self, from: data)
        else { return }
        accounts = stored
    }

    public func knownRefs() -> [AccountRef] {
        accounts.map { AccountRef(id: $0.id, provider: .claude, handle: $0.handle) }
    }

    /// Сверяется с тем, что сейчас в CLI: добавляет аккаунт, если он новый, и
    /// освежает копию его refresh-токена.
    ///
    /// Копию надо снимать при каждом опросе. Иначе, когда пользователь уйдёт в
    /// другой аккаунт, токен этого будет затёрт в Keychain и аккаунт пропадёт
    /// из списка навсегда.
    public func syncWithCLI(profileUUID: String, displayName: String) async throws {
        let refresh = try? await currentCLIRefreshToken()

        if let index = accounts.firstIndex(where: { $0.handle == profileUUID }) {
            accounts[index].displayName = displayName
            if let refresh { accounts[index].refreshToken = refresh }
        } else {
            accounts.append(StoredAccount(
                id: "claude/\(profileUUID)", handle: profileUUID,
                displayName: displayName, refreshToken: refresh
            ))
        }
        try await persist()
    }

    public func accessToken(for handle: String) async throws -> String {
        guard let index = accounts.firstIndex(where: { $0.handle == handle }) else {
            throw ProviderFailure(kind: .needsLogin, message: "Аккаунт не найден")
        }

        // Активный аккаунт узнаём по совпадению с тем, что лежит в Keychain CLI.
        if let active = try? await currentCLIAccountToken(), active.handle == handle {
            return active.token
        }

        guard let refresh = accounts[index].refreshToken else {
            throw ProviderFailure(kind: .needsLogin, message: "Нужен вход в аккаунт")
        }

        let fresh = try await refresher.refresh(refreshToken: refresh)
        if let rotated = fresh.refreshToken {
            accounts[index].refreshToken = rotated
            try? await persist()
        }
        return fresh.accessToken
    }

    /// Токен активной сессии CLI. Читается заново каждый раз — CLI мог его обновить.
    public func currentCLIToken() async throws -> String {
        guard let token = try await cliOAuth()["accessToken"] as? String else {
            throw ProviderFailure(kind: .needsLogin, message: "Claude Code не залогинен")
        }
        return token
    }

    private func currentCLIRefreshToken() async throws -> String {
        guard let token = try await cliOAuth()["refreshToken"] as? String else {
            throw ProviderFailure(kind: .needsLogin, message: "В Keychain нет refresh-токена")
        }
        return token
    }

    /// Какой аккаунт сейчас активен. Сопоставление идёт по refresh-токену:
    /// он у каждого аккаунта свой и, в отличие от access-токена, не меняется
    /// при каждом продлении.
    private func currentCLIAccountToken() async throws -> (handle: String, token: String) {
        let oauth = try await cliOAuth()
        guard let access = oauth["accessToken"] as? String,
              let refresh = oauth["refreshToken"] as? String,
              let match = accounts.first(where: { $0.refreshToken == refresh })
        else {
            throw ProviderFailure(kind: .needsLogin, message: "Активный аккаунт не опознан")
        }
        return (match.handle, access)
    }

    private func cliOAuth() async throws -> [String: Any] {
        guard let data = try await keychain.read(service: Self.cliService),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = root["claudeAiOauth"] as? [String: Any]
        else {
            throw ProviderFailure(kind: .needsLogin, message: "Claude Code не залогинен")
        }
        return oauth
    }

    private func persist() async throws {
        let data = try JSONEncoder().encode(accounts)
        try await keychain.write(data, service: Self.ownService)
    }
}
```

- [ ] **Step 4: Убедиться, что тесты проходят**

Run: `cd Packages/Core && swift test --filter CredentialStoreTests`
Expected: PASS, 10 тестов.

- [ ] **Step 5: Commit**

```bash
git add Packages/Core
git commit -m "Учётные данные: активный аккаунт только на чтение, остальные продлеваются сами"
```

---

### Task 8: Опрос и агрегация

**Files:**
- Create: `Packages/Core/Sources/Monitoring/UsagePoller.swift`
- Delete: `Packages/Core/Sources/Monitoring/Monitoring.swift` (заглушка), `Packages/Core/Tests/MonitoringTests/Placeholder.swift`
- Test: `Packages/Core/Tests/MonitoringTests/UsagePollerTests.swift`

**Interfaces:**
- Consumes: `UsageProvider`, `AccountSnapshot`, `orderedForDisplay` из Task 2.
- Produces:
  - `actor UsagePoller` — `init(providers: [any UsageProvider])`, `refresh() async -> [AccountSnapshot]`, `cached() async -> [AccountSnapshot]`
  - `func menuBarSummary(_ snapshots: [AccountSnapshot], now: Date) -> MenuBarSummary?`
  - `struct MenuBarSummary: Sendable { let percent: Double; let severity: Severity; let remaining: TimeInterval? }`

- [ ] **Step 1: Написать падающий тест**

Создать `Packages/Core/Tests/MonitoringTests/UsagePollerTests.swift`:

```swift
import Testing
import Foundation
import ProviderKit
@testable import Monitoring

private struct FakeProvider: UsageProvider {
    let id: ProviderID
    let refs: [AccountRef]
    let snapshots: [String: AccountSnapshot]
    var failDiscovery = false

    func discoverAccounts() async throws -> [AccountRef] {
        if failDiscovery { throw ProviderFailure(kind: .network, message: "нет сети") }
        return refs
    }

    func fetch(_ ref: AccountRef) async throws -> AccountSnapshot {
        guard let snapshot = snapshots[ref.id] else {
            throw ProviderFailure(kind: .noData, message: "нет данных")
        }
        return snapshot
    }
}

private func snap(
    _ id: String, provider: ProviderID = .claude, peak: Double, resetsIn: TimeInterval? = nil
) -> AccountSnapshot {
    AccountSnapshot(
        id: id, provider: provider, displayName: id, planLabel: "Max",
        windows: [LimitWindow(
            id: "weekly", label: "нед", percent: peak,
            resetsAt: resetsIn.map { Date(timeIntervalSince1970: 1_000_000 + $0) }
        )],
        freshness: .live(Date(timeIntervalSince1970: 1_000_000)), failure: nil
    )
}

private func makeProvider(_ items: [AccountSnapshot], id: ProviderID = .claude) -> FakeProvider {
    FakeProvider(
        id: id,
        refs: items.map { AccountRef(id: $0.id, provider: id, handle: $0.id) },
        snapshots: Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
    )
}

@Test func gathersFromEveryProviderInDisplayOrder() async {
    let poller = UsagePoller(providers: [
        makeProvider([snap("busy", peak: 88), snap("free", peak: 4)]),
        makeProvider([snap("codex", provider: .codex, peak: 32)], id: .codex),
    ])
    let result = await poller.refresh()
    #expect(result.map(\.id) == ["free", "codex", "busy"])
}

@Test func oneBrokenProviderDoesNotHideTheOthers() async {
    var broken = makeProvider([], id: .codex)
    broken.failDiscovery = true

    let poller = UsagePoller(providers: [makeProvider([snap("ok", peak: 10)]), broken])
    let result = await poller.refresh()
    #expect(result.map(\.id) == ["ok"])
}

@Test func failedFetchBecomesVisibleRowNotSilence() async {
    let provider = FakeProvider(
        id: .claude,
        refs: [AccountRef(id: "gone", provider: .claude, handle: "gone")],
        snapshots: [:]
    )
    let result = await UsagePoller(providers: [provider]).refresh()
    #expect(result.count == 1)
    #expect(result[0].failure?.kind == .noData)
    #expect(result[0].id == "gone")
}

@Test func cacheSurvivesUntilNextRefresh() async {
    let poller = UsagePoller(providers: [makeProvider([snap("a", peak: 10)])])
    #expect(await poller.cached().isEmpty)
    _ = await poller.refresh()
    #expect(await poller.cached().map(\.id) == ["a"])
}

@Test func menuBarShowsTheWindowClosestToExhaustion() {
    let now = Date(timeIntervalSince1970: 1_000_000)
    let summary = menuBarSummary([
        snap("free", peak: 5, resetsIn: 60),        // сбросится раньше, но он не важен
        snap("busy", peak: 92, resetsIn: 2_820),    // 47 минут
    ], now: now)

    #expect(summary?.percent == 92)
    #expect(summary?.severity == .critical)
    #expect(summary?.remaining == 2_820)
}

@Test func menuBarIsEmptyWithoutAccounts() {
    #expect(menuBarSummary([], now: Date()) == nil)
}
```

- [ ] **Step 2: Убедиться, что тест падает**

Run: `cd Packages/Core && swift test --filter UsagePollerTests`
Expected: FAIL, `cannot find 'UsagePoller' in scope`.

- [ ] **Step 3: Реализовать**

```bash
rm Packages/Core/Sources/Monitoring/Monitoring.swift
rm Packages/Core/Tests/MonitoringTests/Placeholder.swift
```

Создать `Packages/Core/Sources/Monitoring/UsagePoller.swift`:

```swift
import Foundation
import ProviderKit

public struct MenuBarSummary: Sendable, Hashable {
    public let percent: Double
    public let severity: Severity
    public let remaining: TimeInterval?
}

/// Обходит провайдеры и складывает результат. Ошибка одного провайдера
/// не должна прятать остальные, поэтому всё ловится на месте.
public actor UsagePoller {
    private let providers: [any UsageProvider]
    private var lastResult: [AccountSnapshot] = []

    public init(providers: [any UsageProvider]) {
        self.providers = providers
    }

    public func cached() -> [AccountSnapshot] { lastResult }

    public func refresh() async -> [AccountSnapshot] {
        var collected: [AccountSnapshot] = []

        for provider in providers {
            guard let refs = try? await provider.discoverAccounts() else { continue }
            for ref in refs {
                do {
                    collected.append(try await provider.fetch(ref))
                } catch {
                    collected.append(placeholder(for: ref, error: error))
                }
            }
        }

        lastResult = orderedForDisplay(collected)
        return lastResult
    }

    /// Аккаунт, по которому не удалось ничего получить, всё равно попадает в
    /// список — иначе он молча исчезнет, и это выглядит как «всё хорошо».
    private func placeholder(for ref: AccountRef, error: any Error) -> AccountSnapshot {
        let failure = error as? ProviderFailure
            ?? ProviderFailure(kind: .network, message: "Не удалось получить данные")
        return AccountSnapshot(
            id: ref.id, provider: ref.provider, displayName: ref.id, planLabel: "—",
            windows: [], freshness: .live(Date()), failure: failure
        )
    }
}

/// Что показать в строке меню: окно, ближайшее к исчерпанию.
/// Брать ближайший по времени сброс нельзя — у свободного аккаунта он ни о чём.
public func menuBarSummary(
    _ snapshots: [AccountSnapshot], now: Date
) -> MenuBarSummary? {
    let windows = snapshots.compactMap(\.peakWindow)
    guard let worst = windows.max(by: { $0.percent < $1.percent }) else { return nil }

    return MenuBarSummary(
        percent: worst.percent,
        severity: worst.severity,
        remaining: worst.remaining(from: now)
    )
}
```

- [ ] **Step 4: Убедиться, что тесты проходят**

Run: `cd Packages/Core && swift test --filter UsagePollerTests`
Expected: PASS, 6 тестов.

- [ ] **Step 5: Commit**

```bash
git add Packages/Core
git commit -m "Опрос провайдеров, кэш и сводка для строки меню"
```

---

### Task 9: Уведомления по порогам

**Files:**
- Create: `Packages/Core/Sources/Monitoring/ThresholdNotifier.swift`
- Test: `Packages/Core/Tests/MonitoringTests/ThresholdNotifierTests.swift`

**Interfaces:**
- Consumes: `AccountSnapshot`, `LimitWindow` из Task 2.
- Produces:
  - `struct ThresholdEvent: Sendable, Hashable { let accountID, windowID, accountName: String; let kind: Kind }`, `Kind` — `.crossed(Int)`, `.recovered`
  - `struct ThresholdTracker: Sendable { mutating func events(for: [AccountSnapshot]) -> [ThresholdEvent] }`

Правило: событие рождается только на **пересечении** снизу вверх. Первый в жизни замер событий не порождает — иначе при запуске приложения посыплются уведомления обо всём сразу.

- [ ] **Step 1: Написать падающий тест**

Создать `Packages/Core/Tests/MonitoringTests/ThresholdNotifierTests.swift`:

```swift
import Testing
import Foundation
import ProviderKit
@testable import Monitoring

private func snap(_ percent: Double) -> [AccountSnapshot] {
    [AccountSnapshot(
        id: "claude/u", provider: .claude, displayName: "a@b.c", planLabel: "Max",
        windows: [LimitWindow(id: "weekly", label: "нед", percent: percent, resetsAt: nil)],
        freshness: .live(Date(timeIntervalSince1970: 0)), failure: nil
    )]
}

@Test func firstReadingIsSilent() {
    var tracker = ThresholdTracker()
    #expect(tracker.events(for: snap(97)).isEmpty)
}

@Test func firesOnceWhenCrossingEighty() {
    var tracker = ThresholdTracker()
    _ = tracker.events(for: snap(70))

    let events = tracker.events(for: snap(81))
    #expect(events.count == 1)
    #expect(events[0].kind == .crossed(80))
    #expect(events[0].accountName == "a@b.c")
}

@Test func staysSilentWhileAboveThreshold() {
    var tracker = ThresholdTracker()
    _ = tracker.events(for: snap(70))
    _ = tracker.events(for: snap(81))

    #expect(tracker.events(for: snap(85)).isEmpty)
    #expect(tracker.events(for: snap(89)).isEmpty)
}

@Test func firesAgainForTheHigherThreshold() {
    var tracker = ThresholdTracker()
    _ = tracker.events(for: snap(70))
    _ = tracker.events(for: snap(81))

    let events = tracker.events(for: snap(96))
    #expect(events.map(\.kind) == [.crossed(95)])
}

@Test func jumpingPastBothReportsOnlyTheHigher() {
    var tracker = ThresholdTracker()
    _ = tracker.events(for: snap(10))

    let events = tracker.events(for: snap(99))
    #expect(events.map(\.kind) == [.crossed(95)])
}

@Test func reportsRecoveryAfterReset() {
    var tracker = ThresholdTracker()
    _ = tracker.events(for: snap(10))
    _ = tracker.events(for: snap(96))

    let events = tracker.events(for: snap(3))
    #expect(events.map(\.kind) == [.recovered])
}

@Test func canFireAgainAfterRecovery() {
    var tracker = ThresholdTracker()
    _ = tracker.events(for: snap(10))
    _ = tracker.events(for: snap(96))
    _ = tracker.events(for: snap(3))

    #expect(tracker.events(for: snap(82)).map(\.kind) == [.crossed(80)])
}

@Test func failedAccountProducesNoEvents() {
    var tracker = ThresholdTracker()
    _ = tracker.events(for: snap(10))

    let broken = [AccountSnapshot(
        id: "claude/u", provider: .claude, displayName: "a@b.c", planLabel: "Max",
        windows: [], freshness: .live(Date(timeIntervalSince1970: 0)),
        failure: ProviderFailure(kind: .network, message: "нет сети")
    )]
    #expect(tracker.events(for: broken).isEmpty)
}
```

- [ ] **Step 2: Убедиться, что тест падает**

Run: `cd Packages/Core && swift test --filter ThresholdNotifierTests`
Expected: FAIL, `cannot find 'ThresholdTracker' in scope`.

- [ ] **Step 3: Реализовать**

Создать `Packages/Core/Sources/Monitoring/ThresholdNotifier.swift`:

```swift
import Foundation
import ProviderKit

public struct ThresholdEvent: Sendable, Hashable {
    public enum Kind: Sendable, Hashable {
        case crossed(Int)   // перешагнули порог снизу вверх
        case recovered      // лимит сбросился, аккаунт снова свободен
    }

    public let accountID: String
    public let windowID: String
    public let accountName: String
    public let kind: Kind
}

/// Помнит предыдущий замер и выдаёт событие только на пересечении порога.
/// Без этого фоновый опрос раз в пять минут превратился бы в поток уведомлений.
public struct ThresholdTracker: Sendable {
    private static let thresholds = [95, 80]   // проверяем от старшего к младшему
    private static let recoveryLevel = 50.0

    private var previous: [Key: Double] = [:]
    private var seenAtLeastOnce = false

    private struct Key: Hashable { let account: String; let window: String }

    public init() {}

    public mutating func events(for snapshots: [AccountSnapshot]) -> [ThresholdEvent] {
        var events: [ThresholdEvent] = []
        var current: [Key: Double] = [:]

        for snapshot in snapshots where snapshot.failure == nil {
            for window in snapshot.windows {
                let key = Key(account: snapshot.id, window: window.id)
                current[key] = window.percent

                guard seenAtLeastOnce, let before = previous[key] else { continue }
                let now = window.percent

                if let crossed = Self.thresholds.first(where: {
                    before < Double($0) && now >= Double($0)
                }) {
                    events.append(ThresholdEvent(
                        accountID: snapshot.id, windowID: window.id,
                        accountName: snapshot.displayName, kind: .crossed(crossed)
                    ))
                } else if before >= Self.recoveryLevel && now < Self.recoveryLevel {
                    events.append(ThresholdEvent(
                        accountID: snapshot.id, windowID: window.id,
                        accountName: snapshot.displayName, kind: .recovered
                    ))
                }
            }
        }

        // Окна пропавших аккаунтов забываем, чтобы они не всплыли позже.
        previous = current
        seenAtLeastOnce = true
        return events
    }
}
```

- [ ] **Step 4: Убедиться, что тесты проходят**

Run: `cd Packages/Core && swift test --filter ThresholdNotifierTests`
Expected: PASS, 8 тестов.

- [ ] **Step 5: Прогнать весь пакет**

Run: `cd Packages/Core && swift test`
Expected: PASS, все тесты зелёные.

- [ ] **Step 6: Commit**

```bash
git add Packages/Core
git commit -m "Пороговые уведомления на пересечении"
```

---

### Task 10: Приложение, строка меню и сборка

**Files:**
- Create: `project.yml`
- Create: `App/Info.plist`
- Create: `App/AppModel.swift`
- Create: `App/StatusCheckerApp.swift`
- Create: `Makefile`

**Interfaces:**
- Consumes: `UsagePoller`, `menuBarSummary`, `ThresholdTracker` из Tasks 8–9; `CredentialStore` из Task 7; провайдеры из Tasks 4 и 6; `formatRemainingCompact` из Task 1.
- Produces: `@MainActor final class AppModel: ObservableObject` со свойствами `snapshots: [AccountSnapshot]`, `summary: MenuBarSummary?`, `isRefreshing: Bool` и методом `refresh() async`; собранный `StatusChecker.app`.

- [ ] **Step 1: Описать проект для XcodeGen**

Создать `project.yml`:

```yaml
name: StatusChecker
options:
  bundleIdPrefix: dev.example
  deploymentTarget:
    macOS: "14.0"
  createIntermediateGroups: true

packages:
  Core:
    path: Packages/Core

targets:
  StatusChecker:
    type: application
    platform: macOS
    sources:
      - path: App
    info:
      path: App/Info.plist
      properties:
        LSUIElement: true
        CFBundleName: StatusChecker
        CFBundleShortVersionString: "0.1"
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: dev.example.StatusChecker
        MARKETING_VERSION: "0.1"
        SWIFT_VERSION: "6.0"
        ENABLE_HARDENED_RUNTIME: YES
        CODE_SIGN_IDENTITY: "-"
        CODE_SIGN_STYLE: Manual
    dependencies:
      - package: Core
        product: ProviderKit
      - package: Core
        product: ClaudeProvider
      - package: Core
        product: CodexProvider
      - package: Core
        product: Credentials
      - package: Core
        product: Monitoring
```

`LSUIElement: true` убирает приложение из Dock — оно живёт только в строке меню.

- [ ] **Step 2: Создать модель приложения**

Создать `App/AppModel.swift`:

```swift
import Foundation
import SwiftUI
import UserNotifications
import ProviderKit
import ClaudeProvider
import CodexProvider
import Credentials
import Monitoring

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var snapshots: [AccountSnapshot] = []
    @Published private(set) var summary: MenuBarSummary?
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastUpdated: Date?

    private let store: CredentialStore
    private var poller: UsagePoller?
    private var tracker = ThresholdTracker()
    private var timer: Task<Void, Never>?

    /// Пока окно открыто — раз в минуту, в фоне — раз в пять минут.
    var isPopoverOpen = false { didSet { restartTimer() } }

    init(
        store: CredentialStore = CredentialStore(
            keychain: SystemKeychain(), refresher: AnthropicTokenRefresher()
        )
    ) {
        self.store = store
    }

    func start() async {
        await store.load()
        await refresh()
        restartTimer()
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        // Сверка с CLI идёт перед каждым опросом: так подхватывается аккаунт,
        // в который пользователь только что вошёл, и освежается копия его
        // refresh-токена, пока он ещё активен.
        await syncWithCLI()
        await rebuildPoller()

        guard let poller else { return }
        let result = await poller.refresh()
        snapshots = result
        summary = menuBarSummary(result, now: Date())
        lastUpdated = Date()

        for event in tracker.events(for: result) { post(event) }
    }

    /// Спрашивает у Anthropic, кто сейчас залогинен в CLI, и отдаёт ответ хранилищу.
    private func syncWithCLI() async {
        guard let token = try? await store.currentCLIToken() else { return }
        let headers = [
            "Authorization": "Bearer \(token)",
            "anthropic-beta": "oauth-2025-04-20",
            "User-Agent": "claude-cli/2.0.0 (external, cli)",
        ]
        guard
            let url = URL(string: "https://api.anthropic.com/api/oauth/profile"),
            let (data, code) = try? await URLSessionHTTPClient().get(url, headers: headers),
            code == 200,
            let profile = try? ClaudeProfileResponse.parse(data)
        else { return }

        try? await store.syncWithCLI(
            profileUUID: profile.uuid, displayName: profile.displayName
        )
    }

    private func rebuildPoller() async {
        let refs = await store.knownRefs()
        poller = UsagePoller(providers: [
            ClaudeUsageProvider(tokens: store, knownAccounts: refs),
            CodexUsageProvider(),
        ])
    }

    private func restartTimer() {
        timer?.cancel()
        let interval: UInt64 = isPopoverOpen ? 60 : 300
        timer = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Double(interval)))
                guard !Task.isCancelled else { return }
                await self?.refresh()
            }
        }
    }

    private func post(_ event: ThresholdEvent) {
        let content = UNMutableNotificationContent()
        switch event.kind {
        case .crossed(let level):
            content.title = "\(event.accountName): \(level) % лимита"
            content.body = level >= 95
                ? "Аккаунт почти исчерпан — пора переключаться."
                : "Осталось меньше пятой части."
        case .recovered:
            content.title = "\(event.accountName) снова свободен"
            content.body = "Лимит сбросился, можно возвращаться."
        }
        UNUserNotificationCenter.current().add(UNNotificationRequest(
            identifier: "\(event.accountID)/\(event.windowID)/\(event.kind)",
            content: content, trigger: nil
        ))
    }
}
```

- [ ] **Step 3: Создать точку входа со строкой меню**

Создать `App/StatusCheckerApp.swift`:

```swift
import SwiftUI
import UserNotifications
import ProviderKit
import Monitoring

@main
struct StatusCheckerApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            PopoverView(model: model)
        } label: {
            MenuBarLabel(summary: model.summary)
        }
        .menuBarExtraStyle(.window)
    }
}

private struct MenuBarLabel: View {
    let summary: MenuBarSummary?

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "gauge.with.needle")
            if let summary, let remaining = summary.remaining {
                Text(formatRemainingCompact(remaining))
                    .monospacedDigit()
            }
        }
    }
}

extension Severity {
    /// Цвет полосы и подписи. Пороги заданы в `Severity`.
    var tint: Color {
        switch self {
        case .ok:       .green
        case .warning:  .yellow
        case .hot:      .orange
        case .critical: .red
        }
    }
}
```

- [ ] **Step 4: Добавить Makefile**

Создать `Makefile`:

```makefile
.PHONY: test project build run lint

test:
	cd Packages/Core && swift test

project:
	xcodegen generate

build: project
	xcodebuild -project StatusChecker.xcodeproj -scheme StatusChecker \
		-configuration Debug -derivedDataPath build build | tail -5

run: build
	open build/Build/Products/Debug/StatusChecker.app

lint:
	swiftlint --quiet || true
```

- [ ] **Step 5: Проверить, что проект собирается**

Эта задача зависит от `PopoverView`, который появляется в Task 11. Чтобы сборка прошла уже сейчас, создать временную заглушку `App/PopoverView.swift`:

```swift
import SwiftUI

struct PopoverView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Text("Наполняется в следующей задаче")
            .padding()
            .task { await model.start() }
    }
}
```

Run: `make build`
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 6: Добавить сгенерированное в .gitignore и закоммитить**

```bash
printf 'StatusChecker.xcodeproj/\nbuild/\n' >> .gitignore
git add project.yml App Makefile .gitignore
git commit -m "Приложение в строке меню: каркас, опрос и уведомления"
```

---

### Task 11: Окно со списком аккаунтов (вариант A)

**Files:**
- Create: `App/AccountRowView.swift`
- Modify: `App/PopoverView.swift` (заменить заглушку из Task 10)

**Interfaces:**
- Consumes: `AppModel` из Task 10; `AccountSnapshot`, `LimitWindow`, `Severity`, `formatRemaining` из Tasks 1–2.
- Produces: `PopoverView`, `AccountRowView` — вёрстка варианта A из `docs/design/menu-window-variants.html`.

Строка аккаунта: логотип, `email` и `Сервис · тариф`, затем по одной полосе на окно — подпись, полоса, процент, остаток. Плашка возраста для снимка. Ширина окна 322 pt.

- [ ] **Step 1: Написать строку аккаунта**

Создать `App/AccountRowView.swift`:

```swift
import SwiftUI
import ProviderKit

struct AccountRowView: View {
    let snapshot: AccountSnapshot
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            header
            if let failure = snapshot.failure {
                Text(failure.message)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(snapshot.windows) { window in
                    meter(for: window)
                }
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 10)
    }

    private var header: some View {
        HStack(spacing: 9) {
            ProviderBadge(provider: snapshot.provider)
            VStack(alignment: .leading, spacing: 1) {
                Text(snapshot.displayName)
                    .font(.system(size: 12.5, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("\(snapshot.provider.title) · \(snapshot.planLabel)")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 4)
            if snapshot.freshness.isStale {
                Text(staleLabel)
                    .font(.system(size: 9.5, weight: .semibold))
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(Color.orange.opacity(0.16), in: RoundedRectangle(cornerRadius: 4))
                    .foregroundStyle(.orange)
            }
        }
    }

    /// Возраст снимка словами: «данные от 28 авг».
    private var staleLabel: String {
        let captured = snapshot.freshness.capturedAt
        guard captured > .distantPast else { return "нет данных" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.setLocalizedDateFormatFromTemplate("d MMM")
        return "данные от \(formatter.string(from: captured))"
    }

    private func meter(for window: LimitWindow) -> some View {
        HStack(spacing: 8) {
            Text(window.label)
                .font(.system(size: 10.5))
                .foregroundStyle(.tertiary)
                .frame(width: 26, alignment: .leading)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.11))
                    Capsule()
                        .fill(window.severity.tint)
                        .frame(width: max(2, geo.size.width * window.percent / 100))
                }
            }
            .frame(height: 4)

            Text("\(Int(window.percent.rounded()))%")
                .font(.system(size: 11))
                .monospacedDigit()
                .foregroundStyle(window.severity == .ok ? .secondary : window.severity.tint)
                .frame(width: 34, alignment: .trailing)

            Text(window.remaining(from: now).map(formatRemaining) ?? "—")
                .font(.system(size: 11))
                .monospacedDigit()
                .foregroundStyle(.tertiary)
                .frame(width: 56, alignment: .trailing)
        }
    }
}

private struct ProviderBadge: View {
    let provider: ProviderID

    var body: some View {
        RoundedRectangle(cornerRadius: 5)
            .fill(background)
            .frame(width: 19, height: 19)
            .overlay(
                Image(systemName: symbol)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
            )
    }

    private var background: Color {
        switch provider {
        case .claude:  Color(red: 0.85, green: 0.47, blue: 0.34)
        case .codex:   .black
        case .cursor:  .indigo
        case .copilot: .gray
        case .gemini:  .blue
        }
    }

    private var symbol: String {
        switch provider {
        case .claude:  "sparkle"
        case .codex:   "circle.circle"
        case .cursor:  "cube"
        case .copilot: "chevron.left.forwardslash.chevron.right"
        case .gemini:  "diamond"
        }
    }
}
```

- [ ] **Step 2: Собрать окно целиком**

Заменить содержимое `App/PopoverView.swift`:

```swift
import SwiftUI
import ProviderKit

struct PopoverView: View {
    @ObservedObject var model: AppModel

    /// Секундная стрелка для таймеров: пересчитывает остаток без запросов в сеть.
    @State private var now = Date()
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.5)

            if model.snapshots.isEmpty {
                empty
            } else {
                ForEach(Array(model.snapshots.enumerated()), id: \.element.id) { index, snapshot in
                    AccountRowView(snapshot: snapshot, now: now)
                    if index < model.snapshots.count - 1 { Divider().opacity(0.35) }
                }
            }

            Divider().opacity(0.5)
            footer
        }
        .frame(width: 322)
        .task { await model.start() }
        .onAppear { model.isPopoverOpen = true }
        .onDisappear { model.isPopoverOpen = false }
        .onReceive(tick) { now = $0 }
    }

    private var header: some View {
        HStack {
            Text("Лимиты подписок").font(.system(size: 12.5, weight: .semibold))
            Spacer()
            if model.isRefreshing {
                ProgressView().controlSize(.small)
            } else if let updated = model.lastUpdated {
                Text(updated, style: .time)
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 13)
        .padding(.top, 11).padding(.bottom, 9)
    }

    private var empty: some View {
        VStack(spacing: 6) {
            Text("Аккаунты не найдены").font(.system(size: 12, weight: .medium))
            Text("Войдите в Claude Code или запустите Codex")
                .font(.system(size: 11)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 22)
    }

    private var footer: some View {
        HStack {
            Button("Обновить") { Task { await model.refresh() } }
                .buttonStyle(.plain)
                .font(.system(size: 11.5))
                .keyboardShortcut("r")
            Spacer()
            Button("Выйти") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.plain)
                .font(.system(size: 11.5))
                .foregroundStyle(.tertiary)
                .keyboardShortcut("q")
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }
}
```

- [ ] **Step 3: Собрать**

Run: `make build`
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 4: Commit**

```bash
git add App
git commit -m "Окно со списком аккаунтов по варианту A"
```

---

### Task 12: Живой прогон и приёмка

**Files:**
- Modify: `README.md` (создать)

- [ ] **Step 1: Прогнать все тесты**

Run: `make test`
Expected: PASS, ни одного падения.

- [ ] **Step 2: Запустить приложение**

Run: `make run`

Проверить глазами:
- в строке меню появилась иконка с таймером;
- по клику открывается окно шириной 322 pt;
- виден аккаунт Claude с двумя полосами (`5ч`, `нед`) и настоящими процентами;
- виден аккаунт Codex с плашкой возраста снимка;
- наименее загруженный аккаунт стоит первым;
- таймеры пересчитываются раз в секунду;
- «Обновить» перезапрашивает данные.

- [ ] **Step 3: Сверить с настоящими числами**

Run:

```bash
TOK=$(security find-generic-password -s "Claude Code-credentials" -w \
  | python3 -c "import json,sys; print(json.load(sys.stdin)['claudeAiOauth']['accessToken'])")
curl -s https://api.anthropic.com/api/oauth/usage \
  -H "Authorization: Bearer $TOK" -H "anthropic-beta: oauth-2025-04-20" \
  -H "User-Agent: claude-cli/2.0.0 (external, cli)" \
  | python3 -c "import json,sys; d=json.load(sys.stdin); print('5ч', d['five_hour']['utilization'], '| нед', d['seven_day']['utilization'])"
```

Expected: проценты совпадают с показанными в окне.

- [ ] **Step 4: Проверить, что вход в CLI цел**

Run: `claude --version && echo "CLI на месте"`

Затем убедиться, что элемент Keychain не перезаписан приложением:

Run: `security find-generic-password -s "Claude Code-credentials" -w | head -c 40`
Expected: элемент читается, вход не слетел. Это главная проверка правила
«активный аккаунт только на чтение».

- [ ] **Step 5: Проверить накопление трёх подписок**

Это приёмка исходной задачи: увидеть все подписки сразу. Требует участия
пользователя, потому что аккаунты набираются по мере входа в них.

1. Приложение запущено, в окне один аккаунт Claude — текущий.
2. Выполнить `claude /login` и войти во **второй** аккаунт.
3. Нажать «Обновить» в окне.

Expected: в списке **два** аккаунта Claude — новый как активный, предыдущий
продлевается сохранённой копией refresh-токена. Повторить для третьего.

Если предыдущий аккаунт показывает «Нужен вход в аккаунт», значит продление не
сработало: снять ответ `POST /v1/oauth/token` и сверить с ожидаемым. Это
единственное место плана, которое не удалось проверить заранее, — живое
продление ротирует настоящий токен, поэтому испытывалось только на моках.

- [ ] **Step 6: Написать README**

Создать `README.md`:

```markdown
# StatusChecker

Приложение в строке меню macOS: остаток лимитов по подпискам Claude Code и
OpenAI Codex в одном окне.

## Сборка

    make test     # тесты логики, без Xcode
    make build    # собрать StatusChecker.app
    make run      # собрать и запустить

Нужны Xcode 26+ и `xcodegen` (`brew install xcodegen`).

## Как это устроено

Логика лежит в `Packages/Core` и не зависит от AppKit — она переносится на iOS
без изменений. Приложение в `App/` — тонкий слой SwiftUI поверх неё.

Данные Claude берутся живьём из `api.anthropic.com/api/oauth/usage`. Данные
Codex читаются из локальных файлов сессий `~/.codex/sessions`, поэтому это
снимок, а не живое значение — его возраст показан в окне.

## Несколько подписок Claude

Аккаунт, залогиненный в Claude Code прямо сейчас, используется **только на
чтение**: приложение никогда не продлевает его токен, иначе ротация
refresh-токена разлогинила бы CLI.

Пока аккаунт активен, приложение снимает копию его refresh-токена. Когда вы
уходите в другую подписку через `/login`, предыдущая остаётся видимой —
приложение продлевает её сохранённой копией, и CLI это не задевает. Так список
наполняется сам: зайдите по разу в каждую подписку, дальше все видны сразу.

Дизайн и решения: `docs/superpowers/specs/`, макет окна: `docs/design/`.
```

- [ ] **Step 7: Commit**

```bash
git add README.md
git commit -m "README и приёмка прототипа"
```

---

## Что осталось за рамками

Реализуется после приёмки прототипа, отдельными планами:

1. **OAuth-вход по PKCE** — кнопка «Добавить аккаунт», не требующая заходить в
   аккаунт через CLI. Для прототипа не нужна: три подписки набираются сами, по
   мере того как пользователь заходит в каждую через `/login`. Понадобится, если
   захочется добавить аккаунт, которого на этой машине никогда не было.
   Параметры запроса авторизации подтвердить не удалось — `claude.ai/oauth/authorize`
   закрыт бот-защитой, а обходить её нельзя. Перед реализацией их надо получить
   законным путём: снять с настоящего входа в CLI или взять из документации.
2. **Наблюдение за Keychain в реальном времени**, чтобы аккаунт появлялся сразу
   после `/login`, а не при следующем опросе (сейчас задержка до пяти минут).
3. **Живые данные Codex** вместо снимка: запрос к `chatgpt.com/backend-api/codex`
   с заголовками CLI проходит авторизацию, значит заголовки с лимитами, скорее
   всего, достижимы. Проверка потратит квоту, поэтому вынесена отдельно.
4. **Провайдеры Cursor, GitHub Copilot, Gemini CLI** — по одному типу на сервис.
5. **Приложение под iOS и виджет.**
