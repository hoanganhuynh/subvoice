# SubVoice Desktop App UI Implementation Plan

**Goal:** Build a native macOS window with the approved Cinematic Aurora / Focus First experience while preserving the existing menu bar, capture, OCR, hotkey and speech pipeline.

**Architecture:** Keep `SubVoiceApp` as the AppKit lifecycle and service owner. Add a testable `SubVoiceUI` Swift package target containing presentation state and SwiftUI views; `AppCoordinator` remains the single source of truth and sends one state snapshot to both the window and menu bar.

**Tech stack:** Swift 6, SwiftUI, AppKit, Swift Testing, ScreenCaptureKit, Vision, AVFoundation, ServiceManagement.

**Spec:** `docs/design/2026-09-01-desktop-app-ui.md`

## Global constraints

- macOS 14.0 remains the minimum supported version.
- Add no third-party UI dependency.
- Preserve `ScreenCapturer`, `OCREngine`, `TextGate`, `SpeechQueue`, `RegionSelector`, `HotKeyManager` and both speech backends unless a task explicitly names a narrow integration edit.
- App always launches stopped; closing the main window does not stop capture or terminate the process.
- Session transcript is memory-only, newest first and capped at exactly 200 entries.
- Theme modes are exactly `system`, `light` and `dark`; the default is `system`.
- Use the exact credit `Made by Anthony with ⌨️`.
- All interactive controls must support keyboard operation, visible focus and VoiceOver labels.
- Respect Increase Contrast and Reduce Motion; never communicate state by colour alone.
- Do not add development-tool metadata, generated instruction folders or unrelated repository files.

## File map

### New production files

- `Sources/SubVoiceCore/SessionTranscript.swift` — memory-only transcript collection.
- `Sources/SubVoiceCore/SpeechVoiceOption.swift` — shared selectable voice value.
- `Sources/SubVoiceUI/AppViewState.swift` — presentation state, diagnostics and intents.
- `Sources/SubVoiceUI/AppViewModel.swift` — observable state and intent dispatch.
- `Sources/SubVoiceUI/AuroraTheme.swift` — semantic colours, spacing and appearance helpers.
- `Sources/SubVoiceUI/DashboardContent.swift` — state-to-copy mapping for the hero.
- `Sources/SubVoiceUI/SubVoiceRootView.swift` — root composition and sheets.
- `Sources/SubVoiceUI/FocusDashboardView.swift` — Focus First dashboard.
- `Sources/SubVoiceUI/StatusOrbView.swift` — animated, accessible status indicator.
- `Sources/SubVoiceUI/ControlDockView.swift` — region, voice and latest-text cards.
- `Sources/SubVoiceUI/VoiceStudioView.swift` — engine, voice, rate, volume and preview.
- `Sources/SubVoiceUI/TranscriptDrawerView.swift` — session history search/copy/clear UI.
- `Sources/SubVoiceUI/SettingsView.swift` — theme, startup, diagnostics and About.
- `Sources/SubVoiceApp/ApplicationMenu.swift` — standard macOS application menu.
- `Sources/SubVoiceApp/MainWindowController.swift` — AppKit window hosting SwiftUI.

### New test files

- `Tests/SubVoiceCoreTests/SessionTranscriptTests.swift`
- `Tests/SubVoiceCoreTests/SettingsTests.swift`
- `Tests/SubVoiceUITests/AppViewModelTests.swift`
- `Tests/SubVoiceUITests/DashboardContentTests.swift`
- `Scripts/smoke-window.sh`

### Existing files modified

- `Package.swift`
- `Sources/SubVoiceCore/Settings.swift`
- `Sources/SubVoiceApp/SystemSpeechBackend.swift`
- `Sources/SubVoiceApp/App.swift`
- `Sources/SubVoiceApp/AppDelegate.swift`
- `Sources/SubVoiceApp/AppCoordinator.swift`
- `Sources/SubVoiceApp/MenuBarController.swift`
- `Resources/Info.plist`
- `README.md`

---

### Task 1: Add persisted theme and memory-only transcript models

**Files:**

- Create: `Sources/SubVoiceCore/SessionTranscript.swift`
- Create: `Sources/SubVoiceCore/SpeechVoiceOption.swift`
- Modify: `Sources/SubVoiceCore/Settings.swift`
- Modify: `Sources/SubVoiceApp/SystemSpeechBackend.swift`
- Create: `Tests/SubVoiceCoreTests/SessionTranscriptTests.swift`
- Create: `Tests/SubVoiceCoreTests/SettingsTests.swift`

**Interfaces:**

- Produces: `ThemeMode`, `SpeechVoiceOption`, `TranscriptEntry`, `SessionTranscript`.
- `SessionTranscript.maximumEntries` is exactly `200`.
- `SessionTranscript.matching(_:)` returns newest-first entries and treats an all-whitespace query as empty.

- [ ] **Step 1: Write failing transcript and settings tests**

```swift
import Foundation
import Testing
@testable import SubVoiceCore

@Suite("Session transcript")
struct SessionTranscriptTests {
    @Test func newestEntryIsFirst() {
        var history = SessionTranscript()
        history.append(text: "Câu một", at: Date(timeIntervalSince1970: 1))
        history.append(text: "Câu hai", at: Date(timeIntervalSince1970: 2))
        #expect(history.entries.map(\.text) == ["Câu hai", "Câu một"])
    }

    @Test func historyKeepsOnlyTwoHundredEntries() {
        var history = SessionTranscript()
        for index in 0..<205 {
            history.append(text: "Câu \(index)", at: Date(timeIntervalSince1970: Double(index)))
        }
        #expect(history.entries.count == 200)
        #expect(history.entries.first?.text == "Câu 204")
        #expect(history.entries.last?.text == "Câu 5")
    }

    @Test func matchingIsCaseInsensitiveAndWhitespaceSafe() {
        var history = SessionTranscript()
        history.append(text: "Xin Chào", at: .now)
        history.append(text: "Tạm biệt", at: .now)
        #expect(history.matching(" chào ").map(\.text) == ["Xin Chào"])
        #expect(history.matching("   ") == history.entries)
    }
}

@Suite("Settings")
struct SettingsTests {
    @Test func themeDefaultsToSystem() {
        #expect(Settings().themeMode == .system)
    }

    @Test func oldPayloadWithoutThemeMigratesToSystem() throws {
        let data = Data(#"{"storedRate":0.55,"storedVolume":1}"#.utf8)
        let settings = try JSONDecoder().decode(Settings.self, from: data)
        #expect(settings.themeMode == .system)
    }
}
```

- [ ] **Step 2: Run the focused tests and confirm the new symbols are missing**

Run: `swift test --filter 'SessionTranscriptTests|SettingsTests'`

Expected: compilation fails because `SessionTranscript` and `ThemeMode` do not exist.

- [ ] **Step 3: Add the exact core models**

```swift
public enum ThemeMode: String, Codable, CaseIterable, Equatable, Sendable {
    case system, light, dark
}

public struct SpeechVoiceOption: Identifiable, Equatable, Sendable {
    public let identifier: String
    public let name: String
    public var id: String { identifier }

    public init(identifier: String, name: String) {
        self.identifier = identifier
        self.name = name
    }
}

public struct TranscriptEntry: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let timestamp: Date
    public let text: String

    public init(id: UUID = UUID(), timestamp: Date, text: String) {
        self.id = id
        self.timestamp = timestamp
        self.text = text
    }
}

public struct SessionTranscript: Equatable, Sendable {
    public static let maximumEntries = 200
    public private(set) var entries: [TranscriptEntry] = []

    public init() {}

    public mutating func append(text: String, at timestamp: Date = .now) {
        entries.insert(TranscriptEntry(timestamp: timestamp, text: text), at: 0)
        if entries.count > Self.maximumEntries {
            entries.removeLast(entries.count - Self.maximumEntries)
        }
    }

    public mutating func clear() { entries.removeAll(keepingCapacity: true) }

    public func matching(_ query: String) -> [TranscriptEntry] {
        let value = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return entries }
        return entries.filter { $0.text.localizedCaseInsensitiveContains(value) }
    }
}
```

Move `SpeechVoiceOption` out of `SystemSpeechBackend.swift` into `Sources/SubVoiceCore/SpeechVoiceOption.swift` and import it where used. Extend `Settings.CodingKeys`, decoding and encoding with `storedThemeMode`; expose a validated `themeMode` property defaulting to `.system`.

- [ ] **Step 4: Run core tests**

Run: `swift test --filter 'SessionTranscriptTests|SettingsTests|SpeechQueueTests'`

Expected: all selected tests pass.

- [ ] **Step 5: Commit the core data contract**

```bash
git add Sources/SubVoiceCore/SessionTranscript.swift Sources/SubVoiceCore/SpeechVoiceOption.swift Sources/SubVoiceCore/Settings.swift Sources/SubVoiceApp/SystemSpeechBackend.swift Tests/SubVoiceCoreTests/SessionTranscriptTests.swift Tests/SubVoiceCoreTests/SettingsTests.swift
git commit -m "feat: add desktop UI state models"
```

---

### Task 2: Create the testable presentation state target

**Files:**

- Modify: `Package.swift`
- Create: `Sources/SubVoiceUI/AppViewState.swift`
- Create: `Sources/SubVoiceUI/AppViewModel.swift`
- Create: `Tests/SubVoiceUITests/AppViewModelTests.swift`

**Interfaces:**

- Consumes: `Settings`, `SpeechVoiceOption`, `SelectedRegion`, `SessionTranscript` from `SubVoiceCore`.
- Produces: `AppRunState`, `AppWarning`, `RecoveryAction`, `RegionSummary`, `DiagnosticStatus`, `AppViewState`, `AppIntent`, `AppViewModel`.
- `AppViewModel.apply(_:)` is the only coordinator-facing state mutation API.
- `AppViewModel.send(_:)` is the only view-facing command API.

- [ ] **Step 1: Add `SubVoiceUI` and `SubVoiceUITests` targets, then write failing view-model tests**

```swift
.target(name: "SubVoiceUI", dependencies: ["SubVoiceCore"]),
.executableTarget(
    name: "SubVoiceApp",
    dependencies: ["SubVoiceCore", "SubVoiceUI"],
    swiftSettings: [.swiftLanguageMode(.v5)]
),
.testTarget(name: "SubVoiceUITests", dependencies: ["SubVoiceUI", "SubVoiceCore"]),
```

```swift
import Testing
@testable import SubVoiceUI

@MainActor
@Suite("App view model")
struct AppViewModelTests {
    @Test func sendForwardsOneIntent() {
        let model = AppViewModel(state: AppViewState())
        var received: [AppIntent] = []
        model.onIntent = { received.append($0) }
        model.send(.toggleCapture)
        #expect(received == [.toggleCapture])
    }

    @Test func applyPublishesACompleteSnapshot() {
        let model = AppViewModel(state: AppViewState())
        model.apply { state in state.runState = .listening }
        #expect(model.state.runState == .listening)
    }
}
```

- [ ] **Step 2: Run the focused test and confirm the presentation types are missing**

Run: `swift test --filter AppViewModelTests`

Expected: compilation fails because `AppViewModel` and `AppViewState` do not exist.

- [ ] **Step 3: Implement the presentation contract**

Use these exact cases and value types:

```swift
public enum RecoveryAction: Equatable, Sendable {
    case openScreenRecordingSettings
    case openSpokenContentSettings
    case retry
}

public struct AppWarning: Equatable, Sendable {
    public let message: String
    public let recovery: RecoveryAction?

    public init(message: String, recovery: RecoveryAction?) {
        self.message = message
        self.recovery = recovery
    }
}

public enum AppRunState: Equatable, Sendable {
    case stopped
    case listening
    case speaking
    case warning(AppWarning)
}

public struct RegionSummary: Equatable, Sendable {
    public let displayID: UInt32
    public let pixelWidth: Int
    public let pixelHeight: Int

    public init(displayID: UInt32, pixelWidth: Int, pixelHeight: Int) {
        self.displayID = displayID
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
    }
}

public enum DiagnosticStatus: Equatable, Sendable {
    case ready(String)
    case unavailable(String)
}

public struct AppViewState: Equatable, Sendable {
    public var runState: AppRunState = .stopped
    public var settings = Settings()
    public var voices: [SpeechVoiceOption] = []
    public var region: RegionSummary?
    public var transcript = SessionTranscript()
    public var screenRecordingGranted = false
    public var systemVoiceStatus: DiagnosticStatus = .unavailable("Chưa kiểm tra")
    public var kokoroStatus: DiagnosticStatus = .unavailable("Chưa kiểm tra")
    public var kokoroAvailable = false
    public var launchAtLoginEnabled = false
    public init() {}
}

public enum AppIntent: Equatable, Sendable {
    case toggleCapture
    case selectRegion
    case changeEngine(SpeechEngine)
    case changeVoice(String)
    case changeRate(Float)
    case changeVolume(Float)
    case previewVoice
    case clearTranscript
    case copyTranscript([UUID])
    case setTheme(ThemeMode)
    case setLaunchAtLogin(Bool)
    case recover(RecoveryAction)
    case showMainWindow
    case quit
}
```

Implement `AppViewModel` as `@MainActor public final class AppViewModel: ObservableObject`, with `@Published public private(set) var state`, `public var onIntent`, `public init(state: AppViewState)`, `send(_:)`, and `apply(_ update: (inout AppViewState) -> Void)`.

Every value type consumed by `SubVoiceApp` exposes an explicit public initializer. `SubVoiceRootView` in Task 5 is `public` and exposes `public init(viewModel: AppViewModel)`; leaf views remain internal to `SubVoiceUI`.

- [ ] **Step 4: Run presentation and core tests**

Run: `swift test --filter 'AppViewModelTests|SessionTranscriptTests|SettingsTests'`

Expected: all selected tests pass.

- [ ] **Step 5: Commit the presentation contract**

```bash
git add Package.swift Sources/SubVoiceUI/AppViewState.swift Sources/SubVoiceUI/AppViewModel.swift Tests/SubVoiceUITests/AppViewModelTests.swift
git commit -m "feat: add shared desktop presentation state"
```

---

### Task 3: Make the coordinator and menu bar use one state snapshot

**Files:**

- Modify: `Sources/SubVoiceApp/AppCoordinator.swift`
- Modify: `Sources/SubVoiceApp/MenuBarController.swift`
- Modify: `Tests/SubVoiceUITests/AppViewModelTests.swift`

**Interfaces:**

- Consumes: `AppViewModel.apply(_:)` and `AppIntent` from Task 2.
- Produces: `AppCoordinator.viewModel`, `AppCoordinator.handle(_:)`, `MenuBarController.render(_:)`, `MenuBarController.onOpenWindow`.
- The existing `MenuBarController.State` enum is removed; `AppRunState` becomes the shared state type.

- [ ] **Step 1: Extend the intent test to cover every menu/UI command**

```swift
@Test func sendPreservesIntentPayloads() {
    let model = AppViewModel(state: AppViewState())
    var received: [AppIntent] = []
    model.onIntent = { received.append($0) }
    model.send(.changeEngine(.kokoro))
    model.send(.changeVoice("diem_trinh"))
    model.send(.changeRate(0.625))
    model.send(.changeVolume(0.75))
    #expect(received == [
        .changeEngine(.kokoro), .changeVoice("diem_trinh"),
        .changeRate(0.625), .changeVolume(0.75),
    ])
}
```

- [ ] **Step 2: Run the focused tests before integration**

Run: `swift test --filter AppViewModelTests`

Expected: tests pass, proving the command contract before wiring side effects.

- [ ] **Step 3: Create the coordinator-owned view model and initial snapshot**

Add:

```swift
let viewModel = AppViewModel(state: AppViewState())

private func regionSummary() -> RegionSummary? {
    region.map {
        RegionSummary(displayID: $0.displayID, pixelWidth: $0.pixelWidth, pixelHeight: $0.pixelHeight)
    }
}

private func publishSnapshot(runState: AppRunState? = nil) {
    viewModel.apply { state in
        if let runState { state.runState = runState }
        state.settings = settings
        state.voices = voicesForCurrentEngine()
        state.region = regionSummary()
        state.screenRecordingGranted = PermissionHelper.hasScreenRecordingAccess
        state.systemVoiceStatus = systemSpeech.hasVietnameseVoice
            ? .ready("Giọng tiếng Việt đã sẵn sàng")
            : .unavailable("Thiếu giọng tiếng Việt")
        state.kokoroAvailable = kokoroSpeech.isAvailable
        state.kokoroStatus = kokoroSpeech.isAvailable
            ? .ready("Kokoro đã sẵn sàng")
            : .unavailable(kokoroSpeech.unavailableReason ?? "Chưa cài Kokoro")
        state.launchAtLoginEnabled = SMAppService.mainApp.status == .enabled
    }
    menuBar?.render(viewModel.state)
}
```

Set `viewModel.onIntent` once in `start()` and route every case through `handle(_:)`. Move launch-at-login registration out of `MenuBarController` into coordinator intent handling. Use `NSPasteboard.general` for `.copyTranscript` and copy selected entries in their current display order.

- [ ] **Step 4: Publish state at every existing transition**

Replace direct menu state mutations in `refreshIdleState`, `switchSpeechEngine`, `fallbackFromKokoro`, `startCapturing`, `stop`, `reselectRegion`, `handleSpeechStarted`, `handleSpeechFinished` and capture failure callbacks with `publishSnapshot(runState:)`.

In `handleText`, after `gate.admit` returns `.speak(let sentence)` and before enqueueing, add:

```swift
viewModel.apply { $0.transcript.append(text: sentence) }
menuBar.render(viewModel.state)
```

Implement `.previewVoice` only when `isRunning == false`, speaking the approved sample with the current rate and volume. Clear the transcript on `.clearTranscript`; do not write it through `Store`.

- [ ] **Step 5: Refactor menu rendering**

Add `render(_ state: AppViewState)` to update symbol, toggle title, warning item, engine checks, voices, rate checks, volume checks and launch-at-login check. Menu click handlers only invoke callbacks; they no longer mutate their own `Settings` copy. Add **Mở SubVoice** as the first normal menu item and emit `onOpenWindow`.

- [ ] **Step 6: Run all tests and compile the app target**

Run: `swift test && swift build --product SubVoiceApp`

Expected: all tests pass and `SubVoiceApp` builds with no duplicate `SpeechVoiceOption` or stale `MenuBarController.State` references.

- [ ] **Step 7: Commit unified state wiring**

```bash
git add Sources/SubVoiceApp/AppCoordinator.swift Sources/SubVoiceApp/MenuBarController.swift Tests/SubVoiceUITests/AppViewModelTests.swift
git commit -m "refactor: unify app and menu bar state"
```

---

### Task 4: Add the Dock lifecycle, application menu and hosted window

**Files:**

- Create: `Sources/SubVoiceApp/ApplicationMenu.swift`
- Create: `Sources/SubVoiceApp/MainWindowController.swift`
- Modify: `Sources/SubVoiceApp/App.swift`
- Modify: `Sources/SubVoiceApp/AppDelegate.swift`
- Modify: `Sources/SubVoiceApp/AppCoordinator.swift`
- Modify: `Resources/Info.plist`
- Create: `Scripts/smoke-window.sh`

**Interfaces:**

- Consumes: `AppViewModel` from Task 2.
- Produces: `MainWindowController.show()`, `MainWindowController.apply(theme:)`, `ApplicationMenu.install()`, `AppCoordinator.showMainWindow()`.

- [ ] **Step 1: Write a failing window smoke script**

```bash
#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
rm -f /tmp/subvoice-window-smoke.txt
./Scripts/bundle.sh debug
open "$HOME/Applications/SubVoice.app" --args --smoke-window
for _ in $(seq 1 30); do
    if [ -f /tmp/subvoice-window-smoke.txt ]; then
        grep -q '^WINDOW-SMOKE-OK$' /tmp/subvoice-window-smoke.txt
        exit 0
    fi
    sleep 0.2
done
echo "Window smoke test timed out" >&2
exit 1
```

Run: `chmod +x Scripts/smoke-window.sh && ./Scripts/smoke-window.sh`

Expected: failure because `--smoke-window` does not create the report.

- [ ] **Step 2: Install a standard app menu and regular activation policy**

`ApplicationMenu.install()` creates the application menu with **About SubVoice**, **Hide SubVoice**, **Hide Others**, **Show All** and **Quit SubVoice** (`⌘Q`). In `App.main()`, call it before `application.run()` and change the policy to `.regular`.

Set `LSUIElement` to `false` in `Resources/Info.plist`.

- [ ] **Step 3: Implement the hosted window controller**

```swift
@MainActor
final class MainWindowController: NSObject, NSWindowDelegate {
    private let window: NSWindow

    init(viewModel: AppViewModel) {
        let root = SubVoiceRootView(viewModel: viewModel)
        let host = NSHostingController(rootView: root)
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 620),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        super.init()
        window.delegate = self
        window.contentMinSize = NSSize(width: 720, height: 540)
        window.contentViewController = host
        window.title = "SubVoice"
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("SubVoice.MainWindow")
        window.center()
    }

    func show() {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func apply(theme: ThemeMode) {
        window.appearance = switch theme {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }
}
```

- [ ] **Step 4: Wire reopen and smoke behavior**

Create the window after coordinator initialization, show it on normal launch, and expose `showMainWindow()`. `AppDelegate.applicationShouldHandleReopen` calls that method and returns `true`. Menu bar **Mở SubVoice** calls the same method.

For `--smoke-window`, show the window, verify `window.isVisible`, write exactly `WINDOW-SMOKE-OK\n` to `/tmp/subvoice-window-smoke.txt`, then terminate after the main run loop renders once.

- [ ] **Step 5: Run lifecycle verification**

Run: `swift test && ./Scripts/smoke-window.sh`

Expected: tests pass and the script exits zero with `WINDOW-SMOKE-OK`.

- [ ] **Step 6: Commit the desktop lifecycle**

```bash
git add Sources/SubVoiceApp/ApplicationMenu.swift Sources/SubVoiceApp/MainWindowController.swift Sources/SubVoiceApp/App.swift Sources/SubVoiceApp/AppDelegate.swift Sources/SubVoiceApp/AppCoordinator.swift Resources/Info.plist Scripts/smoke-window.sh
git commit -m "feat: add desktop window lifecycle"
```

---

### Task 5: Build the Cinematic Aurora Focus First dashboard

**Files:**

- Create: `Sources/SubVoiceUI/AuroraTheme.swift`
- Create: `Sources/SubVoiceUI/DashboardContent.swift`
- Create: `Sources/SubVoiceUI/StatusOrbView.swift`
- Create: `Sources/SubVoiceUI/ControlDockView.swift`
- Create: `Sources/SubVoiceUI/FocusDashboardView.swift`
- Create: `Sources/SubVoiceUI/SubVoiceRootView.swift`
- Create: `Tests/SubVoiceUITests/DashboardContentTests.swift`

**Interfaces:**

- Consumes: `AppViewModel`, `AppRunState`, `AppIntent`.
- Produces: `DashboardContent.init(runState:)`, `SubVoiceRootView.init(viewModel:)`.
- Main button emits only `.toggleCapture`; dock cards emit `.selectRegion` or open local sheets.

- [ ] **Step 1: Write failing copy-mapping tests**

```swift
import Testing
@testable import SubVoiceUI

@Suite("Dashboard content")
struct DashboardContentTests {
    @Test func stoppedContentInvitesStarting() {
        let content = DashboardContent(runState: .stopped)
        #expect(content.title == "Nghe phụ đề. Không rời mắt.")
        #expect(content.primaryActionTitle == "Bắt đầu đọc")
        #expect(content.symbolName == "speaker.wave.2")
    }

    @Test func warningUsesMessageAndRecoveryLabel() {
        let content = DashboardContent(runState: .warning(.init(
            message: "Cần quyền Screen Recording",
            recovery: .openScreenRecordingSettings
        )))
        #expect(content.title == "SubVoice cần bạn hỗ trợ")
        #expect(content.detail == "Cần quyền Screen Recording")
        #expect(content.recoveryTitle == "Mở System Settings")
    }
}
```

- [ ] **Step 2: Run the focused tests and confirm `DashboardContent` is missing**

Run: `swift test --filter DashboardContentTests`

Expected: compilation fails with `cannot find 'DashboardContent' in scope`.

- [ ] **Step 3: Implement semantic design tokens and dashboard copy**

`AuroraTheme` defines semantic background, surface, primary text, secondary text, purple accent, cyan status, warning, error, focus colour, radii `8/16/24` and spacing based on multiples of eight. Colours resolve from `Color(nsColor:)` or light/dark variants; views never hard-code component colours.

`DashboardContent` maps states exactly:

| State | Title | Detail | Primary action |
| --- | --- | --- | --- |
| stopped | Nghe phụ đề. Không rời mắt. | Sẵn sàng khi bạn sẵn sàng. | Bắt đầu đọc |
| listening | SubVoice đang nghe | Đang theo dõi vùng phụ đề đã chọn. | Dừng đọc |
| speaking | Đang đọc phụ đề | Câu mới đã được đưa tới loa. | Dừng đọc |
| warning | SubVoice cần bạn hỗ trợ | Warning message | Recovery action or Thử lại |

- [ ] **Step 4: Implement the Focus First composition**

Use this root hierarchy:

```swift
ZStack {
    AuroraBackground()
    VStack(spacing: 24) {
        TopBar(state: viewModel.state)
        Spacer(minLength: 8)
        StatusOrbView(runState: viewModel.state.runState)
        HeroCopyView(content: DashboardContent(runState: viewModel.state.runState))
        PrimaryCaptureButton(state: viewModel.state.runState) {
            viewModel.send(.toggleCapture)
        }
        Spacer(minLength: 8)
        ControlDockView(state: viewModel.state, viewModel: viewModel)
        Text("Made by Anthony with ⌨️")
    }
    .padding(32)
}
```

Status orb uses icon plus accessible status text, not colour alone. Pulse only while listening or speaking and only when `accessibilityReduceMotion == false`. Use native `Button` for all three cards, `.buttonStyle(.plain)`, visible hover/focus treatment and minimum 44-point hit targets.

- [ ] **Step 5: Run UI-model tests and compile the view target**

Run: `swift test --filter 'DashboardContentTests|AppViewModelTests' && swift build --product SubVoiceApp`

Expected: tests and compilation pass in both debug and release configurations.

- [ ] **Step 6: Commit the dashboard**

```bash
git add Sources/SubVoiceUI/AuroraTheme.swift Sources/SubVoiceUI/DashboardContent.swift Sources/SubVoiceUI/StatusOrbView.swift Sources/SubVoiceUI/ControlDockView.swift Sources/SubVoiceUI/FocusDashboardView.swift Sources/SubVoiceUI/SubVoiceRootView.swift Tests/SubVoiceUITests/DashboardContentTests.swift
git commit -m "feat: build focus first dashboard"
```

---

### Task 6: Add Voice Studio, settings, diagnostics and About

**Files:**

- Create: `Sources/SubVoiceUI/VoiceStudioView.swift`
- Create: `Sources/SubVoiceUI/SettingsView.swift`
- Modify: `Sources/SubVoiceUI/SubVoiceRootView.swift`
- Modify: `Sources/SubVoiceUI/ControlDockView.swift`
- Modify: `Sources/SubVoiceApp/AppCoordinator.swift`
- Modify: `Sources/SubVoiceApp/MainWindowController.swift`
- Modify: `Tests/SubVoiceUITests/AppViewModelTests.swift`

**Interfaces:**

- Voice Studio emits `.changeEngine`, `.changeVoice`, `.changeRate`, `.changeVolume`, `.previewVoice`.
- Settings emits `.setTheme`, `.setLaunchAtLogin`, `.recover`.
- `MainWindowController.apply(theme:)` is called after theme state changes.

- [ ] **Step 1: Add intent payload tests for preview, theme, login and recovery**

```swift
@Test func settingsIntentsRemainExplicit() {
    let model = AppViewModel(state: AppViewState())
    var received: [AppIntent] = []
    model.onIntent = { received.append($0) }
    model.send(.previewVoice)
    model.send(.setTheme(.dark))
    model.send(.setLaunchAtLogin(true))
    model.send(.recover(.openScreenRecordingSettings))
    #expect(received == [
        .previewVoice, .setTheme(.dark), .setLaunchAtLogin(true),
        .recover(.openScreenRecordingSettings),
    ])
}
```

- [ ] **Step 2: Run intent tests**

Run: `swift test --filter AppViewModelTests`

Expected: pass before UI wiring.

- [ ] **Step 3: Implement Voice Studio with native controls**

Use a labelled `Picker` for engine, `Picker` for voice, `Slider` for `Settings.minimumRate...Settings.maximumRate`, `Slider` for `0...1`, value labels and a native **Thử giọng** button. The preview button is disabled whenever `runState` is listening or speaking and exposes the help text `Dừng đọc phụ đề trước khi thử giọng.`

The five visible rate labels remain `Rất chậm`, `Chậm`, `Vừa`, `Nhanh`, `Rất nhanh`; display Kokoro's mapped multiplier from `SpeechRateMapping.kokoroSpeed(for:)` next to the label when Kokoro is selected.

- [ ] **Step 4: Implement settings and diagnostics**

Theme is a visible three-button group: **System**, **Light**, **Dark**. Each button changes theme only when activated. Selected and focused styles remain distinct.

Diagnostics rows use icon, title, status text and optional action:

- Screen Recording → **Mở System Settings** when missing.
- Giọng hệ thống → **Mở Spoken Content** when missing.
- Kokoro → reason text when unavailable; no dead action.

Include launch-at-login toggle and About section with bundle version, existing Kokoro acknowledgements and `Made by Anthony with ⌨️`.

- [ ] **Step 5: Wire side effects in coordinator**

- `.previewVoice`: guard `!isRunning`, then `speech.speak("Xin chào, đây là giọng đọc của SubVoice.", rate:settings.speechRate, volume:settings.volume)`.
- `.setTheme`: mutate settings, save, publish, call `mainWindow.apply(theme:)`.
- `.setLaunchAtLogin`: register/unregister `SMAppService.mainApp`, then publish actual service status; on error publish a non-blocking warning.
- `.recover(.openScreenRecordingSettings)`: call `PermissionHelper.openScreenRecordingSettings()`.
- `.recover(.openSpokenContentSettings)`: open the existing Spoken Content settings URL.
- `.recover(.retry)`: call `refreshIdleState()`.

- [ ] **Step 6: Verify theme and Voice Studio**

Run: `swift test && swift build -c release --product SubVoiceApp`

Manual check: System follows macOS appearance; Light and Dark override only after activation; tabbing does not change theme; preview is disabled while running; every slider exposes its current value to VoiceOver.

- [ ] **Step 7: Commit controls and settings**

```bash
git add Sources/SubVoiceUI/VoiceStudioView.swift Sources/SubVoiceUI/SettingsView.swift Sources/SubVoiceUI/SubVoiceRootView.swift Sources/SubVoiceUI/ControlDockView.swift Sources/SubVoiceApp/AppCoordinator.swift Sources/SubVoiceApp/MainWindowController.swift Tests/SubVoiceUITests/AppViewModelTests.swift
git commit -m "feat: add voice studio and app settings"
```

---

### Task 7: Add searchable session transcript drawer

**Files:**

- Create: `Sources/SubVoiceUI/TranscriptDrawerView.swift`
- Modify: `Sources/SubVoiceUI/SubVoiceRootView.swift`
- Modify: `Sources/SubVoiceUI/ControlDockView.swift`
- Modify: `Sources/SubVoiceApp/AppCoordinator.swift`
- Modify: `Tests/SubVoiceCoreTests/SessionTranscriptTests.swift`

**Interfaces:**

- Consumes: `SessionTranscript.matching(_:)`, `.copyTranscript([UUID])`, `.clearTranscript`.
- Produces: latest-text card, searchable newest-first list and clear confirmation.

- [ ] **Step 1: Add a failing clear-and-filter ordering test**

```swift
@Test func clearRemovesFilteredAndUnfilteredEntries() {
    var history = SessionTranscript()
    history.append(text: "Một", at: .now)
    history.append(text: "Hai", at: .now)
    #expect(history.matching("hai").count == 1)
    history.clear()
    #expect(history.entries.isEmpty)
    #expect(history.matching("hai").isEmpty)
}
```

- [ ] **Step 2: Run the focused history tests**

Run: `swift test --filter SessionTranscriptTests`

Expected: pass using Task 1's `clear()` contract.

- [ ] **Step 3: Implement the transcript drawer**

Use a local `@State private var query = ""` and compute `state.transcript.matching(query)`. Build the sheet with:

```swift
VStack(spacing: 16) {
    HStack {
        Text("Lịch sử phiên").font(.title2.weight(.semibold))
        Spacer()
        Button("Sao chép kết quả") {
            viewModel.send(.copyTranscript(filtered.map(\.id)))
        }
        .disabled(filtered.isEmpty)
    }
    TextField("Tìm trong phiên", text: $query)
        .textFieldStyle(.roundedBorder)
    transcriptListOrEmptyState
    Button("Xoá lịch sử", role: .destructive) { confirmClear = true }
        .disabled(state.transcript.entries.isEmpty)
}
```

Each row exposes its timestamp, full text and a **Sao chép câu này** button. The clear confirmation states `Xoá 200 câu trong phiên này?` using the actual current count. Escape closes the drawer and focus returns to the latest-text card.

- [ ] **Step 4: Wire clipboard and clear behavior**

For `.copyTranscript(ids)`, preserve the visible order passed by the view, join texts with newline, clear the pasteboard and write one string. `.clearTranscript` mutates only `viewModel.state.transcript`; it never calls `Store.saveSettings`.

- [ ] **Step 5: Verify transcript privacy and accessibility**

Run: `swift test && swift build --product SubVoiceApp`

Manual check: accepted sentences appear once; rejected/duplicate OCR does not appear; search is case-insensitive; copying preserves order; quitting/relaunching starts empty; keyboard can open, search, copy, clear, cancel and close the drawer.

- [ ] **Step 6: Commit the transcript experience**

```bash
git add Sources/SubVoiceUI/TranscriptDrawerView.swift Sources/SubVoiceUI/SubVoiceRootView.swift Sources/SubVoiceUI/ControlDockView.swift Sources/SubVoiceApp/AppCoordinator.swift Tests/SubVoiceCoreTests/SessionTranscriptTests.swift
git commit -m "feat: add private session transcript"
```

---

### Task 8: Polish, document, install and verify the release

**Files:**

- Modify: `README.md`
- Create: `Resources/Screenshots/main-window.png`
- Modify only if verification finds a packaging omission: `Scripts/bundle.sh`

**Interfaces:**

- Consumes: the completed app and existing bundle script.
- Produces: installed `~/Applications/SubVoice.app`, README screenshot and release verification evidence.

- [ ] **Step 1: Run formatting and repository hygiene checks**

Run:

```bash
git diff --check
git status --short --branch
```

Expected: no whitespace errors and only the intended product files are modified.

- [ ] **Step 2: Run the complete automated suite**

Run:

```bash
swift test
./Scripts/smoke-overlay.sh
./Scripts/smoke-window.sh
```

Expected: all unit/performance tests pass and both smoke scripts exit zero.

- [ ] **Step 3: Build, sign and install the release bundle**

Run: `SUBVOICE_INCLUDE_KOKORO=1 ./Scripts/bundle.sh release`

Then verify:

```bash
codesign --verify --deep --strict "$HOME/Applications/SubVoice.app"
plutil -extract LSUIElement raw "$HOME/Applications/SubVoice.app/Contents/Info.plist"
```

Expected: signature verification succeeds and `LSUIElement` prints `false`.

- [ ] **Step 4: Complete the manual acceptance pass**

Verify all of these before documentation capture:

- Launch opens the main window in stopped state.
- Dock icon and menu bar icon are both present.
- Closing the window leaves the app running; Dock and menu bar reopen it.
- `⌥⌘V`, `⌥⌘R` and `⌘Q` work.
- Region selection, System voice, Kokoro voice, five speeds and volume work.
- Kokoro speed differences are audible on newly generated samples.
- Missing permissions and unavailable Kokoro show useful recovery UI.
- Transcript never survives quit/relaunch.
- System/Light/Dark, Increase Contrast, Reduce Motion, keyboard and VoiceOver pass.

- [ ] **Step 5: Capture the real app window and update README**

Capture only the SubVoice window in Dark mode with harmless Vietnamese sample content. Save it as `Resources/Screenshots/main-window.png`. Update README:

- Replace “chạy gọn trên menu bar” and “không cần cửa sổ chính”.
- Put the screenshot below the introduction.
- Update usage steps to start from the main window.
- Explain that menu bar remains available for quick controls.
- Add Voice Studio, session-only history and diagnostics to highlights.
- Update architecture tree with `SubVoiceUI`.
- Keep privacy and Kokoro attribution sections intact.

- [ ] **Step 6: Commit release polish**

```bash
git add README.md Resources/Screenshots/main-window.png Scripts/bundle.sh
git commit -m "docs: present the SubVoice desktop app"
```

If `Scripts/bundle.sh` did not change, omit it from `git add`.

- [ ] **Step 7: Final clean-tree and commit-author verification**

Run:

```bash
git status --short --branch
git log --format='%h %an <%ae> %s' origin/feat/subvoice..HEAD
```

Expected: clean worktree; all new commits show `Anthony <creative@williens.com>` and describe only product work.

- [ ] **Step 8: Push the completed branch**

Run: `git push origin feat/subvoice`

Expected: remote branch advances without a force push and GitHub displays the completed desktop-app commits.
