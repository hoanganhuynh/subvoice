# Gắn vùng đọc với cửa sổ và tự tạm dừng — Kế hoạch thực thi

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Vùng phụ đề nhớ cửa sổ đã sinh ra nó, và SubVoice tự ngưng phát hiện chữ khi cửa sổ đó bị che, bị thu nhỏ, bị kéo đi, hoặc đổi sang nội dung khác.

**Architecture:** Toàn bộ luật quyết định nằm ở hàm thuần trong `SubVoiceCore` (`RegionFocusPolicy`), nhận vào danh sách `WindowSnapshot` dựng tay được nên test được hết. Phần chạm hệ điều hành gói trong `WindowWatcher` ở `SubVoiceApp`: đọc `CGWindowListCopyWindowInfo` mỗi 0.4 giây, cộng thêm hai quan sát viên `NSWorkspace` để phản ứng tức thì lúc đổi app hoặc đổi Space. `AppCoordinator` nhận kết luận và bật/tắt một cờ mà `handleFrame` đọc trên hàng đợi bắt màn hình.

**Tech Stack:** Swift 6 (`SubVoiceCore`) và Swift 5 language mode (`SubVoiceApp`), SwiftUI, AppKit, CoreGraphics window API, swift-testing (`import Testing`).

**Spec:** `docs/design/2026-09-04-region-window-binding.md`

**Lệnh dùng suốt kế hoạch:**

- Chạy toàn bộ test: `swift test`
- Chạy một suite: `swift test --filter RegionFocusPolicyTests`
- Dịch app: `swift build`

---

## Bản đồ file

**Tạo mới**

| File | Trách nhiệm |
| --- | --- |
| `Sources/SubVoiceCore/RegionOwner.swift` | Kiểu dữ liệu chủ sở hữu vùng + chuẩn hoá tiêu đề |
| `Sources/SubVoiceCore/WindowSnapshot.swift` | Ảnh chụp một cửa sổ, thuần dữ liệu |
| `Sources/SubVoiceCore/RegionFocusPolicy.swift` | Ba hàm thuần: `evaluate`, `reanchor`, `owner(forGlobalRect:)` |
| `Sources/SubVoiceApp/WindowWatcher.swift` | Đọc `CGWindowListCopyWindowInfo`, timer, quan sát `NSWorkspace` |
| `Tests/SubVoiceCoreTests/RegionOwnerTests.swift` | Test chuẩn hoá tiêu đề |
| `Tests/SubVoiceCoreTests/RegionFocusPolicyTests.swift` | Test toàn bộ luật |

**Sửa**

| File | Thay đổi |
| --- | --- |
| `Sources/SubVoiceCore/Geometry.swift` | Thêm `toGlobalTopLeft` |
| `Sources/SubVoiceCore/SelectedRegion.swift` | Thêm `owner: RegionOwner?` |
| `Sources/SubVoiceCore/Settings.swift` | Thêm hai công tắc |
| `Sources/SubVoiceUI/AppViewState.swift` | Thêm `AppRunState.paused`, hai `AppIntent`, sửa `isCapturing` |
| `Sources/SubVoiceUI/DashboardContent.swift` | Nhánh cho trạng thái tạm dừng |
| `Sources/SubVoiceUI/StatusOrbView.swift` | Ba `switch` thêm nhánh |
| `Sources/SubVoiceUI/FocusDashboardView.swift` | Ba `switch` trong `TopBar` thêm nhánh |
| `Sources/SubVoiceUI/SettingsView.swift` | Mục "Vùng đọc" với hai `Toggle` |
| `Sources/SubVoiceApp/MenuBarController.swift` | `renderRunState` thêm nhánh |
| `Sources/SubVoiceApp/AppCoordinator.swift` | Ghi chủ lúc chọn vùng, neo lại + bật watcher, cờ tạm dừng, hai intent mới |
| `Tests/SubVoiceCoreTests/GeometryTests.swift` | Test `toGlobalTopLeft` |
| `Tests/SubVoiceCoreTests/SelectedRegionTests.swift` | Test `owner` qua JSON |
| `Tests/SubVoiceCoreTests/SettingsTests.swift` | Test hai công tắc mới |
| `Tests/SubVoiceUITests/DashboardContentTests.swift` | Test nhãn tạm dừng |

Thứ tự task đi từ trong ra ngoài: dữ liệu thuần trước, luật sau, giao diện, rồi mới nối dây. Sau mỗi task `swift build` vẫn phải xanh.

---

## Task 1: `RegionOwner` và chuẩn hoá tiêu đề

**Files:**
- Create: `Sources/SubVoiceCore/RegionOwner.swift`
- Test: `Tests/SubVoiceCoreTests/RegionOwnerTests.swift`

- [ ] **Step 1: Viết test đỏ**

Tạo `Tests/SubVoiceCoreTests/RegionOwnerTests.swift`:

```swift
import Testing
@testable import SubVoiceCore

@Suite("Region owner")
struct RegionOwnerTests {
    @Test func trimsSurroundingWhitespace() {
        #expect(RegionOwner.normalizedTitle("  Phim hay  ") == "Phim hay")
    }

    @Test func stripsNotificationCounterPrefix() {
        #expect(RegionOwner.normalizedTitle("(3) Phim hay - YouTube") == "Phim hay - YouTube")
    }

    @Test func stripsRepeatedCounterPrefixes() {
        #expect(RegionOwner.normalizedTitle("(12) (2) Phim hay") == "Phim hay")
    }

    @Test func keepsParenthesesThatAreNotCounters() {
        #expect(RegionOwner.normalizedTitle("(Trailer) Phim hay") == "(Trailer) Phim hay")
    }

    @Test func treatsMissingAndEmptyTitlesAsNil() {
        #expect(RegionOwner.normalizedTitle(nil) == nil)
        #expect(RegionOwner.normalizedTitle("   ") == nil)
        #expect(RegionOwner.normalizedTitle("(3)") == nil)
    }

    @Test func roundTripsThroughJSON() throws {
        let owner = RegionOwner(
            bundleIdentifier: "com.google.Chrome",
            applicationName: "Google Chrome",
            windowNumber: 7788,
            windowTitle: "Phim hay"
        )

        let data = try JSONEncoder().encode(owner)
        #expect(try JSONDecoder().decode(RegionOwner.self, from: data) == owner)
    }
}
```

- [ ] **Step 2: Chạy test cho chắc là đỏ**

Chạy: `swift test --filter RegionOwnerTests`
Chờ: FAIL, `cannot find 'RegionOwner' in scope`.

- [ ] **Step 3: Viết `RegionOwner`**

Tạo `Sources/SubVoiceCore/RegionOwner.swift`:

```swift
import Foundation

/// App và cửa sổ đã sinh ra vùng đọc.
///
/// `windowNumber` CHỈ có nghĩa trong phiên hiện tại: macOS cấp lại số hiệu cửa
/// sổ sau khi app đích khởi động lại, nên đầu mỗi phiên đọc đều phải neo lại
/// bằng `RegionFocusPolicy.reanchor`.
public struct RegionOwner: Codable, Equatable, Sendable {
    public var bundleIdentifier: String
    public var applicationName: String
    public var windowNumber: UInt32?
    /// Tiêu đề cửa sổ lúc khoanh vùng, đã chuẩn hoá. `nil` khi không đọc được.
    public var windowTitle: String?

    public init(
        bundleIdentifier: String,
        applicationName: String,
        windowNumber: UInt32?,
        windowTitle: String?
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.applicationName = applicationName
        self.windowNumber = windowNumber
        self.windowTitle = windowTitle
    }

    /// Cắt phần đếm thông báo `(3) ` mà web hay chèn vào đầu tiêu đề tab, rồi
    /// cắt khoảng trắng hai đầu. Không có gì còn lại thì trả `nil`.
    ///
    /// Chỉ cắt khi trong ngoặc toàn chữ số — `(Trailer)` là một phần của tên
    /// thật, cắt đi là so sánh sai.
    public static func normalizedTitle(_ raw: String?) -> String? {
        guard var text = raw?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return nil
        }
        while text.hasPrefix("("), let close = text.firstIndex(of: ")") {
            let digits = text[text.index(after: text.startIndex)..<close]
            guard !digits.isEmpty, digits.allSatisfy(\.isNumber) else { break }
            text = String(text[text.index(after: close)...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return text.isEmpty ? nil : text
    }
}
```

- [ ] **Step 4: Chạy test cho chắc là xanh**

Chạy: `swift test --filter RegionOwnerTests`
Chờ: PASS, 6 test.

- [ ] **Step 5: Commit**

```bash
git add Sources/SubVoiceCore/RegionOwner.swift Tests/SubVoiceCoreTests/RegionOwnerTests.swift
git commit -m "feat: them RegionOwner va chuan hoa tieu de cua so"
```

---

## Task 2: `WindowSnapshot`

**Files:**
- Create: `Sources/SubVoiceCore/WindowSnapshot.swift`

Kiểu này thuần dữ liệu, không có hành vi nào để test riêng. Nó được test gián tiếp qua toàn bộ `RegionFocusPolicyTests` ở các task sau.

- [ ] **Step 1: Viết `WindowSnapshot`**

Tạo `Sources/SubVoiceCore/WindowSnapshot.swift`:

```swift
import CoreGraphics

/// Ảnh chụp một cửa sổ đang hiện trên màn hình.
///
/// Tách khỏi CoreGraphics window API để luật xét vùng đọc test được bằng dữ
/// liệu dựng tay. Danh sách truyền vào `RegionFocusPolicy` LUÔN xếp từ trước ra
/// sau, đúng thứ tự `CGWindowListCopyWindowInfo` trả về.
public struct WindowSnapshot: Equatable, Sendable {
    public var windowNumber: UInt32
    public var bundleIdentifier: String?
    public var applicationName: String?
    public var title: String?
    /// Hệ toạ độ toàn cục gốc TRÊN-TRÁI, đúng như `kCGWindowBounds` trả về.
    public var frame: CGRect
    /// 0 là cửa sổ thường. Thanh menu, Dock và các lớp hệ thống khác có layer
    /// lớn hơn, và không bao giờ được tính là che vùng đọc.
    public var layer: Int
    public var alpha: CGFloat

    public init(
        windowNumber: UInt32,
        bundleIdentifier: String?,
        applicationName: String?,
        title: String?,
        frame: CGRect,
        layer: Int,
        alpha: CGFloat
    ) {
        self.windowNumber = windowNumber
        self.bundleIdentifier = bundleIdentifier
        self.applicationName = applicationName
        self.title = title
        self.frame = frame
        self.layer = layer
        self.alpha = alpha
    }
}
```

- [ ] **Step 2: Dịch cho chắc là xanh**

Chạy: `swift build`
Chờ: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add Sources/SubVoiceCore/WindowSnapshot.swift
git commit -m "feat: them WindowSnapshot cho luat xet vung doc"
```

---

## Task 3: `RegionFocusPolicy.evaluate` — luật cửa sổ

Bốn luật đầu: không có chủ, công tắc tắt, cửa sổ biến mất, vùng ra ngoài khung. Luật che và luật tiêu đề để Task 4 và Task 5.

**Files:**
- Create: `Sources/SubVoiceCore/RegionFocusPolicy.swift`
- Test: `Tests/SubVoiceCoreTests/RegionFocusPolicyTests.swift`

- [ ] **Step 1: Viết test đỏ**

Tạo `Tests/SubVoiceCoreTests/RegionFocusPolicyTests.swift`:

```swift
import CoreGraphics
import Testing
@testable import SubVoiceCore

@Suite("Region focus policy")
struct RegionFocusPolicyTests {

    // Vùng phụ đề nằm ở đáy cửa sổ Chrome toàn màn hình 1920x1080.
    static let region = CGRect(x: 400, y: 900, width: 1120, height: 120)
    static let chromeFrame = CGRect(x: 0, y: 0, width: 1920, height: 1080)
    static let ownBundle = "com.williens.subvoice"

    // Giá trị mặc định của tham số KHÔNG tra được thành viên tĩnh không đủ tên,
    // nên phải viết đủ `RegionFocusPolicyTests.chromeFrame`.
    static func chrome(
        number: UInt32 = 7788,
        title: String? = "Phim hay",
        frame: CGRect = RegionFocusPolicyTests.chromeFrame
    ) -> WindowSnapshot {
        WindowSnapshot(
            windowNumber: number,
            bundleIdentifier: "com.google.Chrome",
            applicationName: "Google Chrome",
            title: title,
            frame: frame,
            layer: 0,
            alpha: 1
        )
    }

    static func owner(
        number: UInt32? = 7788,
        title: String? = "Phim hay"
    ) -> RegionOwner {
        RegionOwner(
            bundleIdentifier: "com.google.Chrome",
            applicationName: "Google Chrome",
            windowNumber: number,
            windowTitle: title
        )
    }

    static func verdict(
        owner: RegionOwner?,
        windows: [WindowSnapshot],
        pauseWhenWindowInactive: Bool = true,
        pauseOnTitleChange: Bool = true
    ) -> RegionFocusVerdict {
        RegionFocusPolicy.evaluate(
            owner: owner,
            regionGlobalRect: region,
            windows: windows,
            ownBundleIdentifier: ownBundle,
            pauseWhenWindowInactive: pauseWhenWindowInactive,
            pauseOnTitleChange: pauseOnTitleChange
        )
    }

    @Test func regionWithoutAnOwnerAlwaysReads() {
        #expect(Self.verdict(owner: nil, windows: []) == .active)
    }

    @Test func masterToggleOffAlwaysReads() {
        #expect(
            Self.verdict(
                owner: Self.owner(),
                windows: [],
                pauseWhenWindowInactive: false
            ) == .active
        )
    }

    @Test func ownerThatFailedToReanchorAlwaysReads() {
        #expect(Self.verdict(owner: Self.owner(number: nil), windows: []) == .active)
    }

    @Test func missingWindowPauses() {
        #expect(
            Self.verdict(owner: Self.owner(), windows: [Self.chrome(number: 9999)])
                == .paused(.windowGone("Google Chrome"))
        )
    }

    @Test func recycledWindowNumberOnAnotherAppPauses() {
        let slack = WindowSnapshot(
            windowNumber: 7788,
            bundleIdentifier: "com.tinyspeck.slackmacgap",
            applicationName: "Slack",
            title: "Slack",
            frame: Self.chromeFrame,
            layer: 0,
            alpha: 1
        )
        #expect(
            Self.verdict(owner: Self.owner(), windows: [slack])
                == .paused(.windowGone("Google Chrome"))
        )
    }

    @Test func windowMovedAwayFromTheRegionPauses() {
        let moved = Self.chrome(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        #expect(
            Self.verdict(owner: Self.owner(), windows: [moved])
                == .paused(.regionOutsideWindow("Google Chrome"))
        )
    }

    @Test func frontmostOwnerWindowReads() {
        #expect(Self.verdict(owner: Self.owner(), windows: [Self.chrome()]) == .active)
    }
}
```

- [ ] **Step 2: Chạy test cho chắc là đỏ**

Chạy: `swift test --filter RegionFocusPolicyTests`
Chờ: FAIL, `cannot find 'RegionFocusPolicy' in scope`.

- [ ] **Step 3: Viết `RegionFocusPolicy` bản đầu**

Tạo `Sources/SubVoiceCore/RegionFocusPolicy.swift`:

```swift
import CoreGraphics

/// Vì sao vùng đọc đang bị tạm dừng. Chuỗi đi kèm là tên app chủ, để giao diện
/// nói được "cửa sổ Google Chrome" thay vì một câu chung chung.
public enum RegionPauseReason: Equatable, Sendable {
    case windowGone(String)
    case windowCovered(String)
    case regionOutsideWindow(String)
    case contentChanged(String)
}

public enum RegionFocusVerdict: Equatable, Sendable {
    case active
    case paused(RegionPauseReason)
}

/// Toàn bộ luật quyết định vùng đọc còn đáng tin hay không.
///
/// Thuần hoàn toàn: nhận ảnh chụp danh sách cửa sổ, trả về kết luận. Phần đọc
/// `CGWindowListCopyWindowInfo` và chạy timer nằm ở `WindowWatcher`.
public enum RegionFocusPolicy {

    /// - Parameter windows: xếp TỪ TRƯỚC RA SAU.
    public static func evaluate(
        owner: RegionOwner?,
        regionGlobalRect: CGRect,
        windows: [WindowSnapshot],
        ownBundleIdentifier: String?,
        pauseWhenWindowInactive: Bool,
        pauseOnTitleChange: Bool
    ) -> RegionFocusVerdict {
        // Neo lại thất bại thì phiên này chạy không khoá cửa sổ, chứ không tạm
        // dừng vĩnh viễn — người dùng vẫn phải nghe được phụ đề.
        guard pauseWhenWindowInactive,
              let owner,
              let number = owner.windowNumber
        else { return .active }

        let name = owner.applicationName

        // Kiểm cả bundle: macOS có cấp lại số hiệu cửa sổ cũ cho app khác.
        guard let index = windows.firstIndex(where: {
            $0.windowNumber == number && $0.bundleIdentifier == owner.bundleIdentifier
        }) else { return .paused(.windowGone(name)) }

        let target = windows[index]

        guard target.frame.contains(regionGlobalRect) else {
            return .paused(.regionOutsideWindow(name))
        }

        return .active
    }
}
```

- [ ] **Step 4: Chạy test cho chắc là xanh**

Chạy: `swift test --filter RegionFocusPolicyTests`
Chờ: PASS, 7 test.

- [ ] **Step 5: Commit**

```bash
git add Sources/SubVoiceCore/RegionFocusPolicy.swift Tests/SubVoiceCoreTests/RegionFocusPolicyTests.swift
git commit -m "feat: luat xet cua so cho vung doc, phan cua so bien mat va doi vi tri"
```

---

## Task 4: Luật cửa sổ khác che vùng đọc

**Files:**
- Modify: `Sources/SubVoiceCore/RegionFocusPolicy.swift`
- Test: `Tests/SubVoiceCoreTests/RegionFocusPolicyTests.swift`

- [ ] **Step 1: Viết test đỏ**

Chèn vào cuối `struct RegionFocusPolicyTests`, ngay trước dấu `}` đóng struct:

```swift
    static func overlay(
        bundleIdentifier: String? = "com.tinyspeck.slackmacgap",
        applicationName: String? = "Slack",
        frame: CGRect,
        layer: Int = 0,
        alpha: CGFloat = 1
    ) -> WindowSnapshot {
        WindowSnapshot(
            windowNumber: 4242,
            bundleIdentifier: bundleIdentifier,
            applicationName: applicationName,
            title: "Slack",
            frame: frame,
            layer: layer,
            alpha: alpha
        )
    }

    @Test func windowInFrontCoveringTheRegionPauses() {
        let slack = Self.overlay(frame: CGRect(x: 300, y: 850, width: 900, height: 400))
        #expect(
            Self.verdict(owner: Self.owner(), windows: [slack, Self.chrome()])
                == .paused(.windowCovered("Google Chrome"))
        )
    }

    @Test func windowInFrontThatMissesTheRegionReads() {
        // Slack nằm góc trên bên trái, không chạm dải phụ đề ở đáy.
        let slack = Self.overlay(frame: CGRect(x: 0, y: 0, width: 400, height: 300))
        #expect(Self.verdict(owner: Self.owner(), windows: [slack, Self.chrome()]) == .active)
    }

    @Test func windowBehindTheOwnerNeverCovers() {
        let slack = Self.overlay(frame: Self.chromeFrame)
        #expect(Self.verdict(owner: Self.owner(), windows: [Self.chrome(), slack]) == .active)
    }

    @Test func invisibleWindowInFrontDoesNotCover() {
        let ghost = Self.overlay(frame: Self.chromeFrame, alpha: 0)
        #expect(Self.verdict(owner: Self.owner(), windows: [ghost, Self.chrome()]) == .active)
    }

    @Test func systemLayersInFrontDoNotCover() {
        // Thanh menu và Dock luôn nằm trước mọi cửa sổ thường.
        let menuBar = Self.overlay(
            bundleIdentifier: "com.apple.controlcenter",
            applicationName: "Control Center",
            frame: Self.chromeFrame,
            layer: 24
        )
        #expect(Self.verdict(owner: Self.owner(), windows: [menuBar, Self.chrome()]) == .active)
    }

    @Test func subVoiceOwnWindowInFrontDoesNotCover() {
        let ourWindow = Self.overlay(
            bundleIdentifier: Self.ownBundle,
            applicationName: "SubVoice",
            frame: Self.chromeFrame
        )
        #expect(Self.verdict(owner: Self.owner(), windows: [ourWindow, Self.chrome()]) == .active)
    }
```

- [ ] **Step 2: Chạy test cho chắc là đỏ**

Chạy: `swift test --filter RegionFocusPolicyTests`
Chờ: FAIL ở `windowInFrontCoveringTheRegionPauses` — nhận `.active`, chờ `.paused(.windowCovered(...))`. Năm test còn lại xanh sẵn.

- [ ] **Step 3: Thêm luật che**

Trong `Sources/SubVoiceCore/RegionFocusPolicy.swift`, thay dòng `return .active` cuối hàm `evaluate` bằng:

```swift
        // Cố ý KHÔNG hỏi app nào đang ở trước. Mở Slack ở một góc màn hình mà
        // nó không che vùng phụ đề thì phim vẫn hiện, chữ trong vùng vẫn là
        // phụ đề — không có gì để đọc nhầm. Chỉ thứ gì thực sự đè lên vùng đọc
        // mới đáng dừng.
        let isCovered = windows.prefix(index).contains { window in
            window.layer == 0
                && window.alpha > 0
                && (ownBundleIdentifier == nil || window.bundleIdentifier != ownBundleIdentifier)
                && window.frame.intersects(regionGlobalRect)
        }
        if isCovered { return .paused(.windowCovered(name)) }

        return .active
```

- [ ] **Step 4: Chạy test cho chắc là xanh**

Chạy: `swift test --filter RegionFocusPolicyTests`
Chờ: PASS, 13 test.

- [ ] **Step 5: Commit**

```bash
git add Sources/SubVoiceCore/RegionFocusPolicy.swift Tests/SubVoiceCoreTests/RegionFocusPolicyTests.swift
git commit -m "feat: tam dung khi co cua so khac de len vung doc"
```

---

## Task 5: Luật tiêu đề cửa sổ

**Files:**
- Modify: `Sources/SubVoiceCore/RegionFocusPolicy.swift`
- Test: `Tests/SubVoiceCoreTests/RegionFocusPolicyTests.swift`

- [ ] **Step 1: Viết test đỏ**

Chèn vào cuối `struct RegionFocusPolicyTests`, ngay trước dấu `}` đóng struct:

```swift
    @Test func changedTitlePauses() {
        #expect(
            Self.verdict(owner: Self.owner(), windows: [Self.chrome(title: "Tin tức")])
                == .paused(.contentChanged("Google Chrome"))
        )
    }

    @Test func changedTitleReadsWhenTheToggleIsOff() {
        #expect(
            Self.verdict(
                owner: Self.owner(),
                windows: [Self.chrome(title: "Tin tức")],
                pauseOnTitleChange: false
            ) == .active
        )
    }

    @Test func notificationCounterAloneIsNotAContentChange() {
        #expect(
            Self.verdict(owner: Self.owner(), windows: [Self.chrome(title: "(3) Phim hay")])
                == .active
        )
    }

    @Test func unreadableTitleDoesNotPause() {
        // Không đọc được tiêu đề là thiếu thông tin, không phải bằng chứng nội
        // dung đã đổi.
        #expect(Self.verdict(owner: Self.owner(), windows: [Self.chrome(title: nil)]) == .active)
    }

    @Test func ownerWithoutARecordedTitleNeverPausesOnTitle() {
        #expect(
            Self.verdict(
                owner: Self.owner(title: nil),
                windows: [Self.chrome(title: "Tin tức")]
            ) == .active
        )
    }

    @Test func coveringWindowWinsOverTitleChange() {
        let slack = Self.overlay(frame: CGRect(x: 300, y: 850, width: 900, height: 400))
        #expect(
            Self.verdict(
                owner: Self.owner(),
                windows: [slack, Self.chrome(title: "Tin tức")]
            ) == .paused(.windowCovered("Google Chrome"))
        )
    }
```

- [ ] **Step 2: Chạy test cho chắc là đỏ**

Chạy: `swift test --filter RegionFocusPolicyTests`
Chờ: FAIL ở `changedTitlePauses` — nhận `.active`, chờ `.paused(.contentChanged(...))`.

- [ ] **Step 3: Thêm luật tiêu đề**

Trong `Sources/SubVoiceCore/RegionFocusPolicy.swift`, thay dòng `return .active` cuối hàm `evaluate` bằng:

```swift
        // Đọc không ra tiêu đề hiện tại thì bỏ qua bước này: thiếu thông tin
        // không phải là bằng chứng nội dung đã đổi.
        if pauseOnTitleChange,
           let expected = owner.windowTitle,
           let actual = RegionOwner.normalizedTitle(target.title),
           actual != expected {
            return .paused(.contentChanged(name))
        }

        return .active
```

- [ ] **Step 4: Chạy test cho chắc là xanh**

Chạy: `swift test --filter RegionFocusPolicyTests`
Chờ: PASS, 19 test.

- [ ] **Step 5: Commit**

```bash
git add Sources/SubVoiceCore/RegionFocusPolicy.swift Tests/SubVoiceCoreTests/RegionFocusPolicyTests.swift
git commit -m "feat: tam dung khi tieu de cua so doi"
```

---

## Task 6: `reanchor` và `owner(forGlobalRect:)`

**Files:**
- Modify: `Sources/SubVoiceCore/RegionFocusPolicy.swift`
- Test: `Tests/SubVoiceCoreTests/RegionFocusPolicyTests.swift`

- [ ] **Step 1: Viết test đỏ**

Chèn vào cuối `struct RegionFocusPolicyTests`, ngay trước dấu `}` đóng struct:

```swift
    @Test func reanchorMatchesByTitleEvenWhenTheNumberChanged() {
        let anchored = RegionFocusPolicy.reanchor(
            owner: Self.owner(number: 1111),
            regionGlobalRect: Self.region,
            windows: [Self.chrome(number: 5555, title: "Phim hay")],
            ownBundleIdentifier: Self.ownBundle
        )

        #expect(anchored?.windowNumber == 5555)
        #expect(anchored?.windowTitle == "Phim hay")
    }

    @Test func reanchorFallsBackToTheWindowContainingTheRegion() {
        let anchored = RegionFocusPolicy.reanchor(
            owner: Self.owner(number: 1111, title: "Tên cũ"),
            regionGlobalRect: Self.region,
            windows: [Self.chrome(number: 5555, title: "Tên mới")],
            ownBundleIdentifier: Self.ownBundle
        )

        #expect(anchored?.windowNumber == 5555)
        // Đi đường dự phòng thì tiêu đề cũ đã vô nghĩa, phải lấy lại tiêu đề
        // đang có, nếu không luật tiêu đề sẽ dừng ngay lập tức.
        #expect(anchored?.windowTitle == "Tên mới")
    }

    @Test func reanchorReturnsNilWhenTheAppIsNotRunning() {
        #expect(
            RegionFocusPolicy.reanchor(
                owner: Self.owner(),
                regionGlobalRect: Self.region,
                windows: [Self.overlay(frame: Self.chromeFrame)],
                ownBundleIdentifier: Self.ownBundle
            ) == nil
        )
    }

    @Test func reanchorIgnoresWindowsThatDoNotHoldTheRegion() {
        let small = Self.chrome(
            number: 5555,
            title: "Tên mới",
            frame: CGRect(x: 0, y: 0, width: 400, height: 300)
        )
        #expect(
            RegionFocusPolicy.reanchor(
                owner: Self.owner(number: 1111, title: "Tên cũ"),
                regionGlobalRect: Self.region,
                windows: [small],
                ownBundleIdentifier: Self.ownBundle
            ) == nil
        )
    }

    @Test func ownerLookupPicksTheFrontmostWindowHoldingTheWholeRegion() {
        let owner = RegionFocusPolicy.owner(
            forGlobalRect: Self.region,
            windows: [
                Self.overlay(frame: CGRect(x: 0, y: 0, width: 400, height: 300)),
                Self.chrome(),
            ],
            ownBundleIdentifier: Self.ownBundle
        )

        #expect(owner?.bundleIdentifier == "com.google.Chrome")
        #expect(owner?.applicationName == "Google Chrome")
        #expect(owner?.windowNumber == 7788)
        #expect(owner?.windowTitle == "Phim hay")
    }

    @Test func ownerLookupSkipsSubVoiceOwnWindows() {
        let ourOverlay = Self.overlay(
            bundleIdentifier: Self.ownBundle,
            applicationName: "SubVoice",
            frame: Self.chromeFrame
        )
        let owner = RegionFocusPolicy.owner(
            forGlobalRect: Self.region,
            windows: [ourOverlay, Self.chrome()],
            ownBundleIdentifier: Self.ownBundle
        )

        #expect(owner?.bundleIdentifier == "com.google.Chrome")
    }

    @Test func ownerLookupReturnsNilWhenTheRegionSpillsOutsideEveryWindow() {
        let small = Self.chrome(frame: CGRect(x: 0, y: 0, width: 800, height: 950))
        #expect(
            RegionFocusPolicy.owner(
                forGlobalRect: Self.region,
                windows: [small],
                ownBundleIdentifier: Self.ownBundle
            ) == nil
        )
    }
```

- [ ] **Step 2: Chạy test cho chắc là đỏ**

Chạy: `swift test --filter RegionFocusPolicyTests`
Chờ: FAIL, `type 'RegionFocusPolicy' has no member 'reanchor'`.

- [ ] **Step 3: Thêm hai hàm**

Chèn vào trong `enum RegionFocusPolicy` ở `Sources/SubVoiceCore/RegionFocusPolicy.swift`, sau hàm `evaluate`:

```swift
    /// Tìm lại cửa sổ chủ ở đầu mỗi phiên đọc, vì số hiệu cửa sổ đã lưu không
    /// sống qua lần khởi động lại của app đích.
    ///
    /// - Returns: `owner` với số hiệu mới, hoặc `nil` khi không tìm được — lúc
    ///   đó phiên này chạy không khoá cửa sổ.
    public static func reanchor(
        owner: RegionOwner,
        regionGlobalRect: CGRect,
        windows: [WindowSnapshot],
        ownBundleIdentifier: String?
    ) -> RegionOwner? {
        let candidates = windows.filter {
            $0.bundleIdentifier == owner.bundleIdentifier
                && $0.layer == 0
                && $0.alpha > 0
                && (ownBundleIdentifier == nil || $0.bundleIdentifier != ownBundleIdentifier)
        }

        if let title = owner.windowTitle,
           let match = candidates.first(where: {
               RegionOwner.normalizedTitle($0.title) == title
           }) {
            var anchored = owner
            anchored.windowNumber = match.windowNumber
            return anchored
        }

        guard let fallback = candidates.first(where: {
            $0.frame.contains(regionGlobalRect)
        }) else { return nil }

        // Tiêu đề cũ đã vô nghĩa ở đường này. Không lấy lại tiêu đề đang có thì
        // luật tiêu đề sẽ tạm dừng ngay từ vòng xét đầu tiên.
        var anchored = owner
        anchored.windowNumber = fallback.windowNumber
        anchored.windowTitle = RegionOwner.normalizedTitle(fallback.title)
        return anchored
    }

    /// Cửa sổ nào đã sinh ra vùng vừa khoanh.
    ///
    /// Đòi khung cửa sổ chứa TRỌN vùng, đúng bằng điều kiện mà `evaluate` dùng.
    /// Nếu ở đây chỉ đòi chứa tâm vùng thì một vùng khoanh tràn mép sẽ nhận chủ
    /// rồi bị `evaluate` cho tạm dừng ngay và không đọc được câu nào.
    public static func owner(
        forGlobalRect rect: CGRect,
        windows: [WindowSnapshot],
        ownBundleIdentifier: String?
    ) -> RegionOwner? {
        guard let window = windows.first(where: {
            $0.layer == 0
                && $0.alpha > 0
                && (ownBundleIdentifier == nil || $0.bundleIdentifier != ownBundleIdentifier)
                && $0.frame.contains(rect)
        }), let bundleIdentifier = window.bundleIdentifier else { return nil }

        return RegionOwner(
            bundleIdentifier: bundleIdentifier,
            applicationName: window.applicationName ?? bundleIdentifier,
            windowNumber: window.windowNumber,
            windowTitle: RegionOwner.normalizedTitle(window.title)
        )
    }
```

- [ ] **Step 4: Chạy test cho chắc là xanh**

Chạy: `swift test --filter RegionFocusPolicyTests`
Chờ: PASS, 26 test.

- [ ] **Step 5: Commit**

```bash
git add Sources/SubVoiceCore/RegionFocusPolicy.swift Tests/SubVoiceCoreTests/RegionFocusPolicyTests.swift
git commit -m "feat: neo lai cua so chu va nhan dien chu luc khoanh vung"
```

---

## Task 7: `Geometry.toGlobalTopLeft`

**Files:**
- Modify: `Sources/SubVoiceCore/Geometry.swift`
- Test: `Tests/SubVoiceCoreTests/GeometryTests.swift`

- [ ] **Step 1: Viết test đỏ**

Chèn vào cuối `Tests/SubVoiceCoreTests/GeometryTests.swift`:

```swift
@Test func convertsDisplayLocalRectToGlobalTopLeftOnPrimaryDisplay() {
    // CGDisplayBounds của màn hình chính luôn có gốc (0, 0).
    let bounds = CGRect(x: 0, y: 0, width: 1920, height: 1080)
    let local = CGRect(x: 100, y: 120, width: 400, height: 60)

    let global = Geometry.toGlobalTopLeft(displayLocalRect: local, displayBounds: bounds)

    #expect(global == CGRect(x: 100, y: 120, width: 400, height: 60))
}

@Test func convertsDisplayLocalRectToGlobalTopLeftOnSecondaryDisplay() {
    // Màn hình phụ đặt bên PHẢI màn hình chính, trong hệ CGDisplayBounds.
    let bounds = CGRect(x: 1920, y: 0, width: 2560, height: 1440)
    let local = CGRect(x: 100, y: 1300, width: 400, height: 60)

    let global = Geometry.toGlobalTopLeft(displayLocalRect: local, displayBounds: bounds)

    #expect(global == CGRect(x: 2020, y: 1300, width: 400, height: 60))
}

@Test func convertsDisplayLocalRectOnDisplayAbovePrimary() {
    // Phía TRÊN màn hình chính -> y âm trong hệ CGDisplayBounds.
    let bounds = CGRect(x: 0, y: -1440, width: 2560, height: 1440)
    let local = CGRect(x: 50, y: 1380, width: 400, height: 60)

    let global = Geometry.toGlobalTopLeft(displayLocalRect: local, displayBounds: bounds)

    #expect(global == CGRect(x: 50, y: -60, width: 400, height: 60))
}
```

- [ ] **Step 2: Chạy test cho chắc là đỏ**

Chạy: `swift test --filter GeometryTests`
Chờ: FAIL, `type 'Geometry' has no member 'toGlobalTopLeft'`.

- [ ] **Step 3: Thêm hàm**

Chèn vào trong `enum Geometry` ở `Sources/SubVoiceCore/Geometry.swift`, sau `toDisplayLocalTopLeft`:

```swift
    /// Đường ngược cho việc đối chiếu với danh sách cửa sổ.
    ///
    /// - Parameters:
    ///   - displayLocalRect: vùng ở hệ cục bộ của display, gốc trên-trái —
    ///     đúng dạng `SelectedRegion.rect` đang lưu.
    ///   - displayBounds: `CGDisplayBounds` của chính display đó. Giá trị này
    ///     ĐÃ ở hệ toàn cục gốc trên-trái, cùng hệ mà `kCGWindowBounds` dùng,
    ///     nên phép chuyển chỉ là cộng gốc của display. Không đụng `NSScreen`,
    ///     không phải lật trục y.
    public static func toGlobalTopLeft(
        displayLocalRect: CGRect,
        displayBounds: CGRect
    ) -> CGRect {
        displayLocalRect.offsetBy(dx: displayBounds.minX, dy: displayBounds.minY)
    }
```

- [ ] **Step 4: Chạy test cho chắc là xanh**

Chạy: `swift test --filter GeometryTests`
Chờ: PASS, 9 test.

- [ ] **Step 5: Commit**

```bash
git add Sources/SubVoiceCore/Geometry.swift Tests/SubVoiceCoreTests/GeometryTests.swift
git commit -m "feat: doi vung doc sang he toa do toan cuc cua danh sach cua so"
```

---

## Task 8: `SelectedRegion.owner`

**Files:**
- Modify: `Sources/SubVoiceCore/SelectedRegion.swift`
- Test: `Tests/SubVoiceCoreTests/SelectedRegionTests.swift`

- [ ] **Step 1: Viết test đỏ**

Chèn vào cuối `Tests/SubVoiceCoreTests/SelectedRegionTests.swift`:

```swift
@Test func regionDefaultsToHavingNoOwner() {
    let region = SelectedRegion(
        displayID: 1,
        rect: CGRect(x: 0, y: 0, width: 100, height: 40),
        scale: 2
    )
    #expect(region.owner == nil)
}

@Test func regionRoundTripsItsOwner() throws {
    let region = SelectedRegion(
        displayID: 1,
        rect: CGRect(x: 0, y: 0, width: 100, height: 40),
        scale: 2,
        owner: RegionOwner(
            bundleIdentifier: "com.google.Chrome",
            applicationName: "Google Chrome",
            windowNumber: 7788,
            windowTitle: "Phim hay"
        )
    )

    let data = try JSONEncoder().encode(region)
    let decoded = try JSONDecoder().decode(SelectedRegion.self, from: data)

    #expect(decoded == region)
    #expect(decoded.owner?.windowTitle == "Phim hay")
}

@Test func regionSavedBeforeThisFeatureStillDecodes() throws {
    // Vùng do bản cũ ghi xuống UserDefaults, chưa hề có khoá `owner`.
    let legacy = Data(#"""
    {"displayID":3,"rect":[[100,120],[400,60]],"scale":2}
    """#.utf8)

    let region = try JSONDecoder().decode(SelectedRegion.self, from: legacy)

    #expect(region.displayID == 3)
    #expect(region.rect == CGRect(x: 100, y: 120, width: 400, height: 60))
    #expect(region.owner == nil)
}
```

- [ ] **Step 2: Chạy test cho chắc là đỏ**

Chạy: `swift test --filter SelectedRegionTests`
Chờ: FAIL, `value of type 'SelectedRegion' has no member 'owner'`.

- [ ] **Step 3: Thêm trường**

Trong `Sources/SubVoiceCore/SelectedRegion.swift`, thay phần khai báo và init bằng:

```swift
public struct SelectedRegion: Codable, Equatable, Sendable {
    public var displayID: UInt32
    public var rect: CGRect
    public var scale: CGFloat
    /// Cửa sổ đã sinh ra vùng này. `nil` với vùng lưu từ bản cũ, hoặc khi
    /// khoanh lên desktop — lúc đó app đọc liên tục như trước.
    ///
    /// `Codable` tự sinh dùng `decodeIfPresent` cho thuộc tính Optional, nên
    /// JSON cũ thiếu khoá này vẫn giải mã được.
    public var owner: RegionOwner?

    public init(
        displayID: UInt32,
        rect: CGRect,
        scale: CGFloat,
        owner: RegionOwner? = nil
    ) {
        self.displayID = displayID
        self.rect = rect
        self.scale = scale
        self.owner = owner
    }
```

Giữ nguyên `pixelWidth` và `pixelHeight` phía dưới.

- [ ] **Step 4: Chạy test cho chắc là xanh**

Chạy: `swift test --filter SelectedRegionTests`
Chờ: PASS, gồm cả ba test mới.

- [ ] **Step 5: Commit**

```bash
git add Sources/SubVoiceCore/SelectedRegion.swift Tests/SubVoiceCoreTests/SelectedRegionTests.swift
git commit -m "feat: vung doc nho cua so da sinh ra no"
```

---

## Task 9: Hai công tắc trong `Settings`

**Files:**
- Modify: `Sources/SubVoiceCore/Settings.swift`
- Test: `Tests/SubVoiceCoreTests/SettingsTests.swift`

- [ ] **Step 1: Viết test đỏ**

Chèn vào trong `struct SettingsTests` ở `Tests/SubVoiceCoreTests/SettingsTests.swift`, trước dấu `}` đóng struct:

```swift
    @Test func windowPauseTogglesDefaultToOn() {
        let settings = Settings()
        #expect(settings.pauseWhenWindowInactive)
        #expect(settings.pauseOnWindowTitleChange)
    }

    @Test func oldPayloadWithoutWindowPauseTogglesDefaultsToOn() throws {
        let data = Data(#"{"storedRate":0.55,"storedVolume":1}"#.utf8)
        let settings = try JSONDecoder().decode(Settings.self, from: data)
        #expect(settings.pauseWhenWindowInactive)
        #expect(settings.pauseOnWindowTitleChange)
    }

    @Test func windowPauseTogglesSurviveARoundTrip() throws {
        var settings = Settings()
        settings.pauseWhenWindowInactive = false
        settings.pauseOnWindowTitleChange = false

        let restored = try JSONDecoder().decode(
            Settings.self,
            from: JSONEncoder().encode(settings)
        )

        #expect(restored.pauseWhenWindowInactive == false)
        #expect(restored.pauseOnWindowTitleChange == false)
    }
```

- [ ] **Step 2: Chạy test cho chắc là đỏ**

Chạy: `swift test --filter SettingsTests`
Chờ: FAIL, `value of type 'Settings' has no member 'pauseWhenWindowInactive'`.

- [ ] **Step 3: Thêm hai khoá**

Trong `Sources/SubVoiceCore/Settings.swift` làm bốn sửa đổi.

Sau `private var storedHasCompletedOnboarding = false`, thêm:

```swift
    private var storedPauseWhenWindowInactive = true
    private var storedPauseOnWindowTitleChange = true
```

Trong `enum CodingKeys`, sau `case storedHasCompletedOnboarding`, thêm:

```swift
        case storedPauseWhenWindowInactive
        case storedPauseOnWindowTitleChange
```

Trong `init(from:)`, sau khối gán `hasCompletedOnboarding`, thêm:

```swift
        // Người dùng nâng cấp app không thấy hành vi đổi ngay: vùng đã lưu của
        // họ có `owner == nil` nên vẫn đọc liên tục cho tới khi khoanh lại vùng.
        pauseWhenWindowInactive = try values.decodeIfPresent(
            Bool.self,
            forKey: .storedPauseWhenWindowInactive
        ) ?? true
        pauseOnWindowTitleChange = try values.decodeIfPresent(
            Bool.self,
            forKey: .storedPauseOnWindowTitleChange
        ) ?? true
```

Trong `encode(to:)`, sau dòng mã hoá `storedHasCompletedOnboarding`, thêm:

```swift
        try values.encode(storedPauseWhenWindowInactive, forKey: .storedPauseWhenWindowInactive)
        try values.encode(storedPauseOnWindowTitleChange, forKey: .storedPauseOnWindowTitleChange)
```

Cuối struct, sau `hasCompletedOnboarding`, thêm hai thuộc tính:

```swift
    /// Ngưng phát hiện chữ khi cửa sổ đã sinh ra vùng đọc không còn hiện.
    public var pauseWhenWindowInactive: Bool {
        get { storedPauseWhenWindowInactive }
        set { storedPauseWhenWindowInactive = newValue }
    }

    /// Coi việc cửa sổ đổi tiêu đề là đổi nội dung. Chỉ có tác dụng khi
    /// `pauseWhenWindowInactive` đang bật.
    public var pauseOnWindowTitleChange: Bool {
        get { storedPauseOnWindowTitleChange }
        set { storedPauseOnWindowTitleChange = newValue }
    }
```

- [ ] **Step 4: Chạy test cho chắc là xanh**

Chạy: `swift test --filter SettingsTests`
Chờ: PASS, 7 test.

- [ ] **Step 5: Commit**

```bash
git add Sources/SubVoiceCore/Settings.swift Tests/SubVoiceCoreTests/SettingsTests.swift
git commit -m "feat: hai cong tac cho viec tam dung theo cua so"
```

---

## Task 10: Trạng thái `paused` và chữ hiển thị

**Files:**
- Modify: `Sources/SubVoiceUI/AppViewState.swift`
- Modify: `Sources/SubVoiceUI/DashboardContent.swift`
- Test: `Tests/SubVoiceUITests/DashboardContentTests.swift`

- [ ] **Step 1: Viết test đỏ**

`RegionPauseReason` sống ở `SubVoiceCore`, và import không bắc cầu qua module,
nên thêm dòng này vào đầu `Tests/SubVoiceUITests/DashboardContentTests.swift`:

```swift
import SubVoiceCore
```

Rồi chèn vào trong `struct DashboardContentTests`, trước dấu `}` đóng struct:

```swift
    @Test func pausedContentNamesTheAppAndKeepsTheStopButton() {
        let content = DashboardContent(runState: .paused(.windowGone("Google Chrome")))
        #expect(content.title == "SubVoice đang chờ")
        #expect(content.detail == "Tạm dừng — cửa sổ Google Chrome không còn hiện")
        #expect(content.primaryActionTitle == "Dừng đọc")
        #expect(content.symbolName == "pause.circle")
        #expect(content.recoveryTitle == nil)
    }

    @Test func eachPauseReasonHasItsOwnWording() {
        #expect(
            DashboardContent(runState: .paused(.windowCovered("Google Chrome"))).detail
                == "Tạm dừng — vùng đọc đang bị che"
        )
        #expect(
            DashboardContent(runState: .paused(.regionOutsideWindow("Google Chrome"))).detail
                == "Tạm dừng — cửa sổ Google Chrome đã đổi vị trí"
        )
        #expect(
            DashboardContent(runState: .paused(.contentChanged("Google Chrome"))).detail
                == "Tạm dừng — cửa sổ Google Chrome đã đổi nội dung"
        )
    }

    @Test func pausedStillCountsAsCapturing() {
        var state = AppViewState()
        state.runState = .paused(.windowCovered("Google Chrome"))
        #expect(state.isCapturing)
    }
```

- [ ] **Step 2: Chạy test cho chắc là đỏ**

Chạy: `swift test --filter DashboardContentTests`
Chờ: FAIL, `type 'AppRunState' has no member 'paused'`.

- [ ] **Step 3: Thêm trạng thái, hai intent và chữ**

Trong `Sources/SubVoiceUI/AppViewState.swift`, thay `enum AppRunState` bằng:

```swift
/// Trạng thái chạy dùng chung cho cửa sổ chính và menu bar.
public enum AppRunState: Equatable, Sendable {
    case stopped
    case listening
    case speaking
    /// Vẫn đang bắt màn hình, nhưng cửa sổ chủ của vùng đọc đã khuất nên không
    /// phát hiện chữ nữa.
    case paused(RegionPauseReason)
    case warning(AppWarning)
}
```

Trong cùng file, sửa `isCapturing`:

```swift
    public var isCapturing: Bool {
        switch runState {
        case .listening, .speaking, .paused: return true
        case .stopped, .warning: return false
        }
    }
```

Và trong `enum AppIntent`, sau `case setLaunchAtLogin(Bool)`, thêm:

```swift
    case setPauseWhenWindowInactive(Bool)
    case setPauseOnWindowTitleChange(Bool)
```

Trong `Sources/SubVoiceUI/DashboardContent.swift`, thêm nhánh vào `switch runState`, đặt trước `case .warning`:

```swift
        case .paused(let reason):
            title = "SubVoice đang chờ"
            detail = Self.detail(for: reason)
            primaryActionTitle = "Dừng đọc"
            symbolName = "pause.circle"
            recoveryTitle = nil
            recoveryAction = nil
```

Và thêm hàm phụ cạnh `label(for:)`:

```swift
    private static func detail(for reason: RegionPauseReason) -> String {
        switch reason {
        case .windowGone(let app): "Tạm dừng — cửa sổ \(app) không còn hiện"
        case .windowCovered: "Tạm dừng — vùng đọc đang bị che"
        case .regionOutsideWindow(let app): "Tạm dừng — cửa sổ \(app) đã đổi vị trí"
        case .contentChanged(let app): "Tạm dừng — cửa sổ \(app) đã đổi nội dung"
        }
    }
```

- [ ] **Step 4: Chạy dịch cho chắc là đỏ ở chỗ khác**

Chạy: `swift build`
Chờ: FAIL — `switch must be exhaustive` ở `StatusOrbView.swift`,
`FocusDashboardView.swift` và `MenuBarController.swift`. Đúng như dự tính: thêm
một case vào `AppRunState` bắt mọi nơi vẽ trạng thái phải nói nó hiện cái gì.
Task 11 và Task 12 vá.

- [ ] **Step 5: Commit sau khi Task 11 và Task 12 xong**

Không commit ở đây: cây nguồn đang không dịch được. Task 11 làm tiếp ngay.

---

## Task 11: Giao diện cửa sổ chính

**Files:**
- Modify: `Sources/SubVoiceUI/StatusOrbView.swift`
- Modify: `Sources/SubVoiceUI/FocusDashboardView.swift:100-125`

- [ ] **Step 1: Vá ba `switch` trong `StatusOrbView`**

Trong `Sources/SubVoiceUI/StatusOrbView.swift`:

```swift
    private var tint: Color {
        switch runState {
        case .stopped: theme.accent
        case .listening, .speaking: theme.status
        case .paused: theme.secondaryText
        case .warning: theme.warning
        }
    }

    private var accessibilityText: String {
        switch runState {
        case .stopped: "Trạng thái: đang dừng"
        case .listening: "Trạng thái: đang nghe"
        case .speaking: "Trạng thái: đang đọc"
        case .paused: "Trạng thái: tạm dừng. \(content.detail)"
        case .warning(let warning): "Trạng thái: cảnh báo. \(warning.message)"
        }
    }

    private var isActive: Bool {
        switch runState {
        case .listening, .speaking: true
        case .stopped, .paused, .warning: false
        }
    }
```

Orb ngừng đập trong lúc tạm dừng vì `isActive` trả `false`. Màu không phải kênh
thông tin duy nhất: icon `pause.circle` từ `DashboardContent` và nhãn
accessibility ở trên đều nói rõ trạng thái.

- [ ] **Step 2: Vá ba `switch` trong `TopBar`**

Trong `Sources/SubVoiceUI/FocusDashboardView.swift`, ở `private struct TopBar`:

```swift
    private var statusLabel: String {
        switch state.runState {
        case .stopped: "Đang dừng"
        case .listening: "Đang nghe"
        case .speaking: "Đang đọc"
        case .paused: "Tạm dừng"
        case .warning: "Cần xử lý"
        }
    }

    private var statusSymbol: String {
        switch state.runState {
        case .stopped: "pause.circle"
        case .listening: "waveform"
        case .speaking: "speaker.wave.2.fill"
        case .paused: "pause.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        }
    }

    private var statusColor: Color {
        switch state.runState {
        case .stopped: theme.secondaryText
        case .listening, .speaking: theme.status
        case .paused: theme.secondaryText
        case .warning: theme.warning
        }
    }
```

- [ ] **Step 3: Dịch riêng module giao diện**

Chạy: `swift build --target SubVoiceUI`
Chờ: `Build complete!`

KHÔNG chạy `swift test` ở đây: nó dựng mọi target, mà `SubVoiceApp` còn thiếu
nhánh `.paused` nên sẽ hỏng ở `MenuBarController`. Task 12 vá nốt rồi mới chạy.

- [ ] **Step 4: Chưa commit**

Task 12 làm tiếp ngay để cây nguồn dịch lại được.

---

## Task 12: Menu bar

**Files:**
- Modify: `Sources/SubVoiceApp/MenuBarController.swift:59-83`

- [ ] **Step 1: Thêm nhánh vào `renderRunState`**

Trong `Sources/SubVoiceApp/MenuBarController.swift`, thêm vào `switch runState` của
`renderRunState`, đặt trước `case .warning`:

```swift
        case .paused:
            // Lấy đúng câu chữ mà cửa sổ chính đang hiện, để hai nơi không nói
            // lệch nhau về cùng một trạng thái.
            let detail = DashboardContent(runState: runState).detail
            setSymbol("pause.circle", description: detail)
            toggleItem.title = "Tắt đọc"
            warningItem.isHidden = true
```

- [ ] **Step 2: Dịch cho chắc là xanh**

Chạy: `swift build`
Chờ: `Build complete!`

- [ ] **Step 3: Chạy toàn bộ test**

Chạy: `swift test`
Chờ: PASS toàn bộ.

- [ ] **Step 4: Commit cả Task 10, 11, 12**

```bash
git add Sources/SubVoiceUI/AppViewState.swift Sources/SubVoiceUI/DashboardContent.swift \
        Sources/SubVoiceUI/StatusOrbView.swift Sources/SubVoiceUI/FocusDashboardView.swift \
        Sources/SubVoiceApp/MenuBarController.swift \
        Tests/SubVoiceUITests/DashboardContentTests.swift
git commit -m "feat: trang thai tam dung hien ro o cua so chinh va menu bar"
```

---

## Task 13: Hai `Toggle` trong Cài đặt

**Files:**
- Modify: `Sources/SubVoiceUI/SettingsView.swift:38-40`

Không có test tự động: đây là bố cục SwiftUI thuần, và chữ hiển thị đã được
`DashboardContentTests` phủ ở tầng dưới. Kiểm bằng mắt ở Task 16.

- [ ] **Step 1: Thêm mục "Vùng đọc"**

Trong `Sources/SubVoiceUI/SettingsView.swift`, chèn giữa mục `section("Khởi động")`
và mục `section("Chẩn đoán")`:

```swift
                    section("Vùng đọc") {
                        Toggle(
                            "Chỉ đọc khi cửa sổ gốc đang hiện",
                            isOn: Binding(
                                get: { state.settings.pauseWhenWindowInactive },
                                set: { viewModel.send(.setPauseWhenWindowInactive($0)) }
                            )
                        )
                        .toggleStyle(.switch)

                        Toggle(
                            "Dừng khi tiêu đề cửa sổ đổi",
                            isOn: Binding(
                                get: { state.settings.pauseOnWindowTitleChange },
                                set: { viewModel.send(.setPauseOnWindowTitleChange($0)) }
                            )
                        )
                        .toggleStyle(.switch)
                        .disabled(!state.settings.pauseWhenWindowInactive)

                        Text("Vùng đọc nhớ cửa sổ đã sinh ra nó và ngưng đọc khi "
                            + "cửa sổ đó bị che hoặc đổi nội dung. Khoanh lại vùng "
                            + "để gắn với cửa sổ khác.")
                            .font(.footnote)
                            .foregroundStyle(theme.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
```

- [ ] **Step 2: Dịch cho chắc là xanh**

Chạy: `swift build`
Chờ: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add Sources/SubVoiceUI/SettingsView.swift
git commit -m "feat: cong tac tam dung theo cua so trong Cai dat"
```

---

## Task 14: `WindowWatcher`

**Files:**
- Create: `Sources/SubVoiceApp/WindowWatcher.swift`

Không có unit test: file này chỉ làm hai việc, đọc `CGWindowListCopyWindowInfo`
và chạy timer, cả hai đều cần màn hình thật. Toàn bộ luật nó gọi đã được
`RegionFocusPolicyTests` phủ. Kiểm bằng tay ở Task 16.

- [ ] **Step 1: Viết `WindowWatcher`**

Tạo `Sources/SubVoiceApp/WindowWatcher.swift`:

```swift
import AppKit
import CoreGraphics
import SubVoiceCore

/// Theo dõi cửa sổ chủ của vùng đọc và báo khi nào được đọc, khi nào phải chờ.
///
/// Poll là bắt buộc: đổi tab và bị cửa sổ khác che đều không bắn ra thông báo
/// hệ thống nào. Hai quan sát viên `NSWorkspace` chỉ để phản ứng tức thì lúc
/// đổi app hoặc đổi Space, không thay được poll.
@MainActor
final class WindowWatcher {

    /// Chỉ bắn khi kết luận đổi so với lần xét trước.
    var onVerdictChange: ((RegionFocusVerdict) -> Void)?

    private static let interval: TimeInterval = 0.4

    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var owner: RegionOwner?
    private var regionGlobalRect: CGRect = .zero
    private var settings = Settings()
    private var lastVerdict: RegionFocusVerdict = .active

    func start(owner: RegionOwner, regionGlobalRect: CGRect, settings: Settings) {
        stop()
        self.owner = owner
        self.regionGlobalRect = regionGlobalRect
        self.settings = settings

        let timer = Timer.scheduledTimer(withTimeInterval: Self.interval, repeats: true) { _ in
            MainActor.assumeIsolated { [weak self] in self?.evaluate() }
        }
        // .common để vòng poll không chết trong lúc người dùng đang kéo cửa sổ
        // hay cuộn menu.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer

        let center = NSWorkspace.shared.notificationCenter
        for name in [
            NSWorkspace.didActivateApplicationNotification,
            NSWorkspace.activeSpaceDidChangeNotification,
        ] {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { [weak self] in self?.evaluate() }
            }
            observers.append(token)
        }

        evaluate()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        let center = NSWorkspace.shared.notificationCenter
        observers.forEach { center.removeObserver($0) }
        observers.removeAll()
        owner = nil
        lastVerdict = .active
    }

    private func evaluate() {
        guard let owner else { return }

        let ownBundleIdentifier = Bundle.main.bundleIdentifier

        // Người dùng mở cửa sổ SubVoice để chỉnh giọng giữa chừng không phải là
        // chuyển app: bỏ qua vòng này và giữ nguyên kết luận cũ.
        if let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
           front == ownBundleIdentifier {
            return
        }

        // Danh sách rỗng là lỗi đọc, không phải bằng chứng vùng đọc bị che.
        let windows = Self.snapshot()
        guard !windows.isEmpty else { return }

        let verdict = RegionFocusPolicy.evaluate(
            owner: owner,
            regionGlobalRect: regionGlobalRect,
            windows: windows,
            ownBundleIdentifier: ownBundleIdentifier,
            pauseWhenWindowInactive: settings.pauseWhenWindowInactive,
            pauseOnTitleChange: settings.pauseOnWindowTitleChange
        )

        guard verdict != lastVerdict else { return }
        lastVerdict = verdict
        onVerdictChange?(verdict)
    }

    /// Danh sách cửa sổ đang hiện, xếp TỪ TRƯỚC RA SAU — đúng thứ tự mà
    /// `CGWindowListCopyWindowInfo` trả về.
    ///
    /// `kCGWindowName` chỉ có giá trị khi app đã được cấp quyền Screen
    /// Recording. App này luôn có quyền đó trước khi bắt đầu đọc.
    static func snapshot() -> [WindowSnapshot] {
        guard let raw = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else { return [] }

        // Một app hay có hàng chục cửa sổ; tra bundle ID theo PID đúng một lần.
        var bundleByPID: [pid_t: String?] = [:]

        return raw.compactMap { entry -> WindowSnapshot? in
            guard let number = entry[kCGWindowNumber as String] as? NSNumber,
                  let boundsDict = entry[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: boundsDict)
            else { return nil }

            let pid = (entry[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value ?? 0
            let bundleIdentifier: String?
            if let cached = bundleByPID[pid] {
                bundleIdentifier = cached
            } else {
                let resolved = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
                bundleByPID[pid] = resolved
                bundleIdentifier = resolved
            }

            return WindowSnapshot(
                windowNumber: number.uint32Value,
                bundleIdentifier: bundleIdentifier,
                applicationName: entry[kCGWindowOwnerName as String] as? String,
                title: entry[kCGWindowName as String] as? String,
                frame: frame,
                layer: (entry[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0,
                alpha: CGFloat((entry[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1)
            )
        }
    }
}
```

- [ ] **Step 2: Dịch cho chắc là xanh**

Chạy: `swift build`
Chờ: `Build complete!` Chưa có ai gọi tới `WindowWatcher`; Task 15 nối dây.

- [ ] **Step 3: Commit**

```bash
git add Sources/SubVoiceApp/WindowWatcher.swift
git commit -m "feat: WindowWatcher doc danh sach cua so va bao ket luan"
```

---

## Task 15: Nối dây vào `AppCoordinator`

**Files:**
- Modify: `Sources/SubVoiceApp/AppCoordinator.swift`

- [ ] **Step 1: Thêm thuộc tính và cờ tạm dừng**

Trong `Sources/SubVoiceApp/AppCoordinator.swift`, sau dòng
`private let regionSelector = RegionSelector()`, thêm:

```swift
    private let windowWatcher = WindowWatcher()
```

Sau `nonisolated(unsafe) private var changeDetectedAt: Date?`, thêm:

```swift
    // Đọc từ hàng đợi bắt màn hình, ghi từ main. Cùng khuôn với changeDetectedAt.
    nonisolated private let pauseLock = NSLock()
    nonisolated(unsafe) private var isWindowPaused = false
```

Và thêm hai hàm phụ, đặt ngay dưới `private var isPreviewing: Bool { ... }`:

```swift
    nonisolated private func windowPaused() -> Bool {
        pauseLock.lock()
        defer { pauseLock.unlock() }
        return isWindowPaused
    }

    private func setWindowPaused(_ paused: Bool) {
        pauseLock.lock()
        isWindowPaused = paused
        pauseLock.unlock()
    }

    /// Đang đọc dở một câu bắt từ màn hình.
    private var isSpeakingCapturedText: Bool {
        if case .capture = speechActivity { return true }
        return false
    }
```

- [ ] **Step 2: Bỏ khung hình trong lúc tạm dừng**

Trong `handleFrame`, chèn ngay dòng đầu tiên của hàm, trước
`CVPixelBufferLockBaseAddress`:

```swift
        // Cửa sổ chủ đang khuất -> bỏ khung, và reset mốc so sánh để khung đầu
        // tiên sau khi quay lại là mốc mới chứ không bị so với trước lúc dừng.
        guard !windowPaused() else {
            captureState.reset()
            return
        }
```

- [ ] **Step 3: Thêm hàm đổi toạ độ, bật watcher và nhận kết luận**

Chèn ba hàm này vào ngay sau `private func stop()`:

```swift
    /// `SelectedRegion.rect` ở hệ cục bộ của display; danh sách cửa sổ ở hệ
    /// toàn cục gốc trên-trái mà `CGDisplayBounds` dùng.
    private func globalRect(for region: SelectedRegion) -> CGRect {
        Geometry.toGlobalTopLeft(
            displayLocalRect: region.rect,
            displayBounds: CGDisplayBounds(region.displayID)
        )
    }

    /// Neo lại cửa sổ chủ rồi bật watcher. Neo thất bại thì phiên này chạy
    /// không khoá cửa sổ — người dùng vẫn nghe được phụ đề, đó mới là việc chính.
    private func startWindowWatcherIfNeeded(for region: SelectedRegion) {
        guard settings.pauseWhenWindowInactive, let owner = region.owner else { return }
        let rect = globalRect(for: region)
        guard let anchored = RegionFocusPolicy.reanchor(
            owner: owner,
            regionGlobalRect: rect,
            windows: WindowWatcher.snapshot(),
            ownBundleIdentifier: Bundle.main.bundleIdentifier
        ) else { return }

        // Số hiệu mới chỉ giữ trong bộ nhớ: ghi xuống Store cũng vô nghĩa vì
        // phiên sau lại phải neo lại từ đầu.
        self.region?.owner = anchored

        windowWatcher.onVerdictChange = { [weak self] verdict in
            self?.handleFocusVerdict(verdict)
        }
        windowWatcher.start(owner: anchored, regionGlobalRect: rect, settings: settings)
    }

    private func handleFocusVerdict(_ verdict: RegionFocusVerdict) {
        guard isRunning else { return }
        switch verdict {
        case .paused(let reason):
            setWindowPaused(true)
            publishSnapshot(runState: .paused(reason))
        case .active:
            setWindowPaused(false)
            publishSnapshot(runState: isSpeakingCapturedText ? .speaking : .listening)
        }
    }
```

- [ ] **Step 4: Bật và tắt watcher đúng chỗ**

Trong `startCapturing`, sau `activeNotice = nil` và trước `isRunning = true`, thêm:

```swift
        setWindowPaused(false)
```

Và sau `publishSnapshot(runState: .listening)`, trước khối `Task { ... }`, thêm:

```swift
        startWindowWatcherIfNeeded(for: region)
```

Trong `stop()`, thêm hai dòng ngay sau `isRunning = false`:

```swift
        windowWatcher.stop()
        setWindowPaused(false)
```

- [ ] **Step 5: Ghi chủ sở hữu lúc chọn xong vùng**

Trong `reselectRegion`, thay khối closure `regionSelector.begin { ... }` bằng:

```swift
        regionSelector.begin { [weak self] selected in
            guard let self else { return }
            self.isSelectingRegion = false
            guard var selected else {
                if shouldResume { self.startCapturing() }
                else { self.refreshIdleState() }
                return
            }
            // Cửa sổ nằm dưới vùng vừa khoanh chính là thứ vùng này thuộc về.
            selected.owner = RegionFocusPolicy.owner(
                forGlobalRect: self.globalRect(for: selected),
                windows: WindowWatcher.snapshot(),
                ownBundleIdentifier: Bundle.main.bundleIdentifier
            )
            self.region = selected
            Store.saveRegion(selected)
            if shouldResume {
                self.startCapturing()
            } else {
                self.refreshIdleState()
            }
        }
```

- [ ] **Step 6: Không để trạng thái đọc đè lên trạng thái tạm dừng**

Trong `handleSpeechStarted`, thay dòng
`publishSnapshot(runState: (isRunning || isPreviewing) ? .speaking : .stopped)` bằng:

```swift
        // Câu bắt trước lúc tạm dừng vẫn được đọc hết, nhưng không được kéo
        // giao diện khỏi trạng thái tạm dừng.
        if !windowPaused() {
            publishSnapshot(runState: (isRunning || isPreviewing) ? .speaking : .stopped)
        }
```

Trong `handleSpeechFinished`, ở nhánh `.capture`, thay
`publishSnapshot(runState: .listening)` bằng:

```swift
                if !windowPaused() { publishSnapshot(runState: .listening) }
```

- [ ] **Step 7: Nối hai intent mới**

Trong `handle(_:)`, sau `case .setLaunchAtLogin(let enabled):` và phần thân của nó,
thêm:

```swift
        case .setPauseWhenWindowInactive(let enabled):
            settings.pauseWhenWindowInactive = enabled
            Store.saveSettings(settings)
            applyWindowWatchSettings()
            publishSnapshot()
        case .setPauseOnWindowTitleChange(let enabled):
            settings.pauseOnWindowTitleChange = enabled
            Store.saveSettings(settings)
            applyWindowWatchSettings()
            publishSnapshot()
```

Và thêm hàm này ngay sau `handleFocusVerdict`:

```swift
    /// Đổi công tắc giữa chừng phải có hiệu lực ngay: tắt công tắc tổng là
    /// thoát tạm dừng lập tức, không bắt người dùng dừng rồi bật lại.
    private func applyWindowWatchSettings() {
        guard isRunning else { return }
        windowWatcher.stop()
        handleFocusVerdict(.active)
        guard settings.pauseWhenWindowInactive, let region else { return }
        startWindowWatcherIfNeeded(for: region)
    }
```

- [ ] **Step 8: Dịch và chạy toàn bộ test**

Chạy: `swift build && swift test`
Chờ: `Build complete!` rồi PASS toàn bộ.

- [ ] **Step 9: Chạy hai smoke test hiện có**

Chạy: `Scripts/smoke-overlay.sh`
Chờ: in ra `OVERLAY-SMOKE-OK`.

Chạy: `Scripts/smoke-window.sh`
Chờ: `WINDOW-SMOKE-OK`.

Hai script này bảo vệ vòng đời cửa sổ overlay và cửa sổ chính. Task 15 có sửa
closure của `regionSelector.begin`, nên phải chạy lại cả hai.

- [ ] **Step 10: Commit**

```bash
git add Sources/SubVoiceApp/AppCoordinator.swift
git commit -m "feat: tu tam dung doc khi cua so chu cua vung khong con hien"
```

---

## Task 16: Kiểm bằng tay

**Files:** không sửa file nào.

Phần này không tự động hoá được: nó cần một cửa sổ thật, một video thật và một
người bấm chuột. Làm theo đúng thứ tự.

- [ ] **Step 1: Dựng bản app và mở**

Chạy: `Scripts/bundle.sh`
Rồi mở bundle vừa dựng bằng Finder, không chạy binary thẳng từ Terminal — quyền
Screen Recording bị TCC quy cho Terminal nếu chạy kiểu đó.

- [ ] **Step 2: Gắn vùng vào một cửa sổ Chrome**

Mở một video có phụ đề trong Chrome, khoanh vùng phụ đề, bấm Bắt đầu đọc.
Chờ: app đọc phụ đề bình thường, trạng thái là "Đang nghe" hoặc "Đang đọc".

- [ ] **Step 3: Che vùng đọc**

Kéo một cửa sổ Finder đè lên dải phụ đề.
Chờ: trong khoảng 0.4 giây, orb chuyển sang dạng ngủ và chữ ghi
`Tạm dừng — vùng đọc đang bị che`. Kéo cửa sổ Finder đi chỗ khác thì app đọc lại.

- [ ] **Step 4: Mở một app khác nhưng không che phim**

Mở Notes ở một góc màn hình trống, không đè lên dải phụ đề.
Chờ: app VẪN đọc tiếp. Đây là hành vi đã chốt trong spec, không phải lỗi.

- [ ] **Step 5: Đổi tab**

Bấm sang một tab khác trong cùng cửa sổ Chrome.
Chờ: chữ ghi `Tạm dừng — cửa sổ Google Chrome đã đổi nội dung`. Bấm về đúng tab
cũ thì app đọc lại.

- [ ] **Step 6: Thu nhỏ cửa sổ**

Thu nhỏ cửa sổ Chrome xuống Dock.
Chờ: chữ ghi `Tạm dừng — cửa sổ Google Chrome không còn hiện`. Mở lại thì đọc
tiếp.

- [ ] **Step 7: Mở cửa sổ SubVoice giữa chừng**

Trong lúc đang đọc, mở cửa sổ chính SubVoice từ menu bar.
Chờ: app KHÔNG tạm dừng. Đây là ca mà `evaluate` cố ý bỏ qua.

- [ ] **Step 8: Tắt công tắc giữa chừng**

Trong lúc đang tạm dừng vì bị che, mở Cài đặt và tắt
"Chỉ đọc khi cửa sổ gốc đang hiện".
Chờ: app đọc lại ngay, không phải bấm Dừng rồi Bắt đầu.

Bật lại công tắc, rồi tắt riêng "Dừng khi tiêu đề cửa sổ đổi", đổi tab.
Chờ: app đọc tiếp dù đã đổi tab.

- [ ] **Step 9: Vùng cũ vẫn chạy như trước**

Chạy: `defaults read com.williens.subvoice subvoice.region` để xem vùng đang lưu.
Nếu máy còn vùng lưu từ bản trước bản này (không có khoá `owner`), bấm Bắt đầu.
Chờ: app đọc liên tục, không bao giờ tạm dừng — đúng như bản cũ. Khoanh lại vùng
thì tính năng mới có hiệu lực.

- [ ] **Step 10: Commit ghi chú nếu có phát hiện**

Nếu bước nào lệch với mô tả trên, ghi lại vào phần "Hạn chế đã biết" của
`docs/design/2026-09-04-region-window-binding.md` rồi commit:

```bash
git add docs/design/2026-09-04-region-window-binding.md
git commit -m "docs: ghi lai han che phat hien khi kiem tay"
```

Nếu mọi bước đều đúng thì không commit gì thêm ở task này.

---

## Task 17: Cập nhật README

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Đọc README để tìm chỗ đặt**

Chạy: `grep -n "vùng" README.md`
Tìm mục nói về việc chọn vùng đọc, và mục liệt kê cài đặt.

- [ ] **Step 2: Viết thêm một đoạn**

Thêm vào mục nói về vùng đọc, theo đúng giọng văn đang có trong README:

```markdown
Vùng đọc nhớ cửa sổ đã sinh ra nó. Khi cửa sổ đó bị cửa sổ khác che, bị thu nhỏ,
bị kéo đi hoặc đổi sang tab khác, SubVoice ngưng phát hiện chữ và hiện lý do,
rồi tự đọc lại khi cửa sổ trở về như cũ. Mở một app khác ở góc màn hình mà nó
không che vùng phụ đề thì app vẫn đọc bình thường.

Tắt được ở Cài đặt bằng "Chỉ đọc khi cửa sổ gốc đang hiện". Trang web tự đổi tiêu
đề của nó — Netflix sang tập mới chẳng hạn — có thể bị tính là đổi nội dung; lúc
đó tắt riêng "Dừng khi tiêu đề cửa sổ đổi".

Vùng đã khoanh từ bản cũ không có thông tin cửa sổ nên vẫn đọc liên tục như
trước. Khoanh lại vùng để gắn nó với cửa sổ hiện tại.
```

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "docs: mo ta viec vung doc gan voi cua so"
```

---

## Xong

Chạy lần cuối:

```bash
swift build && swift test
```

Chờ: `Build complete!` và toàn bộ test PASS.
