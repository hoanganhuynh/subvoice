# Gắn vùng đọc với cửa sổ và tự tạm dừng

Ngày chốt thiết kế: 2026-09-04

Trạng thái: Đã duyệt

## Mục tiêu

Vùng phụ đề hiện chỉ là một hình chữ nhật trên một màn hình. SubVoice không biết
vùng đó thuộc về cửa sổ nào, nên khi người dùng chuyển sang cửa sổ khác, đổi tab
hoặc thu nhỏ trình duyệt, app vẫn tiếp tục OCR đúng toạ độ đó và đọc lên bất cứ
chữ gì rơi vào — nội dung hoàn toàn không liên quan tới bộ phim.

Bản này gắn vùng đọc với cửa sổ đã sinh ra nó, theo dõi cửa sổ đó trong lúc chạy,
và tự ngưng phát hiện chữ khi vùng đọc không còn hiển thị nội dung ban đầu.

## Phạm vi

Trong phạm vi:

- Ghi nhận cửa sổ chủ của vùng ngay lúc người dùng khoanh vùng.
- Neo lại cửa sổ chủ ở đầu mỗi phiên đọc, vì số hiệu cửa sổ không sống qua lần
  khởi động lại của app đích.
- Theo dõi cửa sổ chủ trong lúc đang đọc và tự chuyển giữa đọc và tạm dừng.
- Trạng thái giao diện riêng cho lúc tạm dừng, nói rõ lý do.
- Hai công tắc trong Cài đặt.

Ngoài phạm vi:

- Nhiều vùng đọc cùng lúc, hoặc hồ sơ vùng riêng cho từng app.
- Tự dời vùng đọc theo cửa sổ khi cửa sổ bị kéo đi. Bản này tạm dừng, không đuổi
  theo.
- Nhận diện nội dung bên trong tab. Tín hiệu duy nhất về nội dung là tiêu đề cửa
  sổ.

## Quyết định nền

**Đọc `CGWindowListCopyWindowInfo` theo chu kỳ, không dùng Accessibility API.**
Danh sách cửa sổ dùng chung quyền Screen Recording mà app đã xin, và trả về đủ
mọi thứ cần: thứ tự trước sau, khung cửa sổ, tiêu đề, cửa sổ nào đang hiện.
Accessibility API hướng sự kiện và không phải poll, nhưng buộc người dùng qua
thêm một hộp thoại cấp quyền nữa, và `AXObserver` hay chết âm thầm khi app đích
bận. Không xin thêm quyền là điểm quyết định.

Phải poll vì đổi tab và bị cửa sổ khác che đều không bắn ra thông báo hệ thống
nào. Chu kỳ 0.4 giây, chỉ chạy trong lúc đang đọc. Bù thêm bằng
`NSWorkspace.didActivateApplicationNotification` và `activeSpaceDidChangeNotification`
để xét lại tức thì lúc đổi app hoặc đổi Space, khỏi chờ hết chu kỳ.

**Tạm dừng là bỏ khung hình, không tắt luồng bắt màn hình.** Tắt rồi bật lại
`SCStream` mất vài trăm mili giây, đủ để nuốt câu phụ đề đầu tiên lúc quay lại.
Đổi lại phải trả giá một chút CPU cho compositor trong lúc tạm dừng.

## Kiến trúc

Luật quyết định nằm trọn trong hàm thuần ở `SubVoiceCore`, phần chạm hệ điều hành
nằm riêng ở `SubVoiceApp`. Cùng kiểu tách như `CaptureTogglePolicy` với
`AppCoordinator` hiện tại, và nhờ vậy toàn bộ luật test được bằng unit test.

### `SubVoiceCore/RegionOwner.swift`

```swift
public struct RegionOwner: Codable, Equatable, Sendable {
    public var bundleIdentifier: String
    public var applicationName: String
    /// Chỉ có giá trị trong phiên hiện tại. Không tin được sau khi app đích
    /// khởi động lại; đầu mỗi phiên đọc đều neo lại.
    public var windowNumber: UInt32?
    /// Tiêu đề cửa sổ lúc khoanh vùng, đã chuẩn hoá. `nil` khi không đọc được.
    public var windowTitle: String?
}
```

Kèm `RegionOwner.normalizedTitle(_:) -> String?`: cắt phần đếm thông báo `(3) `
ở đầu, cắt khoảng trắng hai đầu, chuỗi rỗng trả về `nil`.

### `SubVoiceCore/WindowSnapshot.swift`

Ảnh chụp một cửa sổ, đủ để xét luật mà không kéo theo CoreGraphics API:

```swift
public struct WindowSnapshot: Equatable, Sendable {
    public var windowNumber: UInt32
    public var bundleIdentifier: String?
    public var title: String?
    /// Hệ toạ độ toàn cục gốc TRÊN-TRÁI, đúng như `kCGWindowBounds` trả về.
    public var frame: CGRect
    public var layer: Int
    public var alpha: CGFloat
}
```

Danh sách truyền vào policy luôn xếp từ trước ra sau.

### `SubVoiceCore/RegionFocusPolicy.swift`

```swift
public enum RegionPauseReason: Equatable, Sendable {
    case windowGone(String)          // tên app
    case windowCovered(String)
    case regionOutsideWindow(String)
    case contentChanged(String)
}

public enum RegionFocusVerdict: Equatable, Sendable {
    case active
    case paused(RegionPauseReason)
}
```

Hai hàm thuần:

```swift
public static func evaluate(
    owner: RegionOwner?,
    regionGlobalRect: CGRect,
    windows: [WindowSnapshot],          // xếp từ trước ra sau
    ownBundleIdentifier: String?,
    pauseWhenWindowInactive: Bool,
    pauseOnTitleChange: Bool
) -> RegionFocusVerdict

public static func reanchor(
    owner: RegionOwner,
    regionGlobalRect: CGRect,
    windows: [WindowSnapshot],
    ownBundleIdentifier: String?
) -> RegionOwner?
```

Luật của `evaluate`, xét theo đúng thứ tự:

1. `owner == nil` hoặc `pauseWhenWindowInactive == false` → `.active`.
2. `owner.windowNumber == nil` → `.active`. Neo lại thất bại thì phiên này chạy
   không khoá cửa sổ, chứ không tạm dừng vĩnh viễn.
3. Không tìm thấy `windowNumber` trong `windows`, hoặc tìm thấy nhưng
   `bundleIdentifier` đã khác → `.paused(.windowGone)`. Danh sách chỉ gồm cửa sổ
   đang hiện, nên thu nhỏ, đóng, hoặc nằm ở Space khác đều rơi vào nhánh này;
   phần kiểm tra bundle chặn ca hệ điều hành cấp lại số hiệu cửa sổ cũ cho một
   app khác.
4. `regionGlobalRect` không nằm gọn trong khung cửa sổ đích →
   `.paused(.regionOutsideWindow)`.
5. Có cửa sổ nào đứng trước cửa sổ đích trong danh sách, `layer == 0`,
   `alpha > 0`, không thuộc `ownBundleIdentifier`, và khung của nó cắt
   `regionGlobalRect` → `.paused(.windowCovered)`.
6. `pauseOnTitleChange` bật, `owner.windowTitle != nil`, cửa sổ đích có tiêu đề
   khác sau khi chuẩn hoá → `.paused(.contentChanged)`. Tiêu đề hiện tại đọc ra
   `nil` thì bỏ qua bước này — không đọc được tiêu đề là thiếu thông tin, không
   phải bằng chứng nội dung đã đổi.
7. Còn lại → `.active`.

Bước 5 cố ý không kiểm tra app nào đang ở trước. Mở Slack ở một góc màn hình mà
nó không che vùng phụ đề thì phim vẫn hiện, chữ trong vùng vẫn là phụ đề, không
có gì để đọc nhầm — SubVoice đọc tiếp. Chỉ khi có thứ gì đó thực sự đè lên vùng
đọc mới dừng.

Luật của `reanchor`, xét theo thứ tự, bỏ qua cửa sổ của chính SubVoice:

1. Cửa sổ cùng `bundleIdentifier` và cùng tiêu đề đã chuẩn hoá → dùng cửa sổ đó.
2. Cửa sổ cùng `bundleIdentifier` mà khung chứa `regionGlobalRect` → dùng cửa sổ
   đó, và cập nhật `windowTitle` theo tiêu đề hiện tại của nó.
3. Không có → trả `nil`, phiên này chạy không khoá cửa sổ.

### `SubVoiceCore/Geometry.swift`

Thêm một hàm thuần, vì `SelectedRegion.rect` ở hệ cục bộ của display còn
`kCGWindowBounds` ở hệ toàn cục:

```swift
public static func toGlobalTopLeft(
    displayLocalRect: CGRect,
    displayBounds: CGRect       // CGDisplayBounds, cùng gốc TRÊN-TRÁI
) -> CGRect
```

`CGDisplayBounds` đã ở đúng hệ toạ độ toàn cục gốc trên-trái mà `kCGWindowBounds`
dùng, nên phép chuyển chỉ là cộng gốc của display. Không đụng tới `NSScreen`,
không phải lật trục y.

### `SubVoiceApp/WindowWatcher.swift`

Phần chạm hệ điều hành, cố ý mỏng:

```swift
@MainActor
final class WindowWatcher {
    var onVerdictChange: ((RegionFocusVerdict) -> Void)?

    /// Đọc `CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID)`
    /// và dịch sang `[WindowSnapshot]`, giữ nguyên thứ tự trước-sau.
    static func snapshot() -> [WindowSnapshot]

    func start(owner: RegionOwner, regionGlobalRect: CGRect, settings: Settings)
    func stop()
}
```

`snapshot()` lấy `kCGWindowNumber`, `kCGWindowOwnerPID`, `kCGWindowName`,
`kCGWindowBounds`, `kCGWindowLayer`, `kCGWindowAlpha`. Bundle ID suy ra từ PID
qua `NSRunningApplication(processIdentifier:)`, có nhớ đệm PID → bundle ID trong
một lần chụp để không tra lại cho từng cửa sổ của cùng một app.

`start` chạy `Timer` 0.4 giây trên main, và đăng ký hai quan sát viên trên
`NSWorkspace.shared.notificationCenter` để xét lại ngay lúc đổi app hoặc đổi
Space. Watcher chỉ bỏ qua một vòng xét khi `snapshot()` trả về danh sách rỗng;
ngoài ca đó thì luôn gọi `RegionFocusPolicy.evaluate`. `onVerdictChange` chỉ bắn
khi kết luận đổi so với lần trước.

Watcher KHÔNG hỏi app nào đang ở trước. Bản nháp đầu có thêm luật "SubVoice đang
ở trước thì bỏ qua vòng xét", nhưng nó tắt hẳn tính năng: người dùng bấm Bắt đầu
từ cửa sổ chính thì SubVoice là app ở trước, và watcher không xét lấy một lần
nào. Luật đó cũng thừa — `evaluate` vốn đã loại cửa sổ của chính SubVoice khỏi
phép kiểm che, nên mở cửa sổ SubVoice giữa chừng không bao giờ gây tạm dừng.

`stop` huỷ timer, gỡ quan sát viên, xoá kết luận cũ.

Và hàm dùng lúc khoanh vùng xong, đặt cùng file vì cùng họ luật thuần:

```swift
public static func owner(
    forGlobalRect rect: CGRect,
    windows: [WindowSnapshot],
    ownBundleIdentifier: String?
) -> RegionOwner?
```

Lấy cửa sổ đầu tiên trong danh sách có `layer == 0`, `alpha > 0`, không thuộc
SubVoice, và khung **chứa trọn** `rect`. Không tìm thấy thì trả `nil` — khoanh
vùng lên desktop, hay khoanh tràn ra ngoài mép cửa sổ, thì vùng không có chủ và
mọi thứ chạy y như trước bản này.

Điều kiện "chứa trọn" cố ý khớp với bước 4 của `evaluate`. Nếu ở đây chỉ đòi
chứa tâm vùng thì một vùng thò ra ngoài mép cửa sổ sẽ có chủ, rồi bị bước 4 cho
tạm dừng ngay lập tức và không bao giờ đọc được.

## Luồng dữ liệu

**Khoanh vùng.** `RegionSelector.finish` dựng `SelectedRegion` như hiện tại.
`AppCoordinator` nhận vùng, đổi sang toạ độ toàn cục, gọi `WindowWatcher.snapshot()`
rồi `RegionFocusPolicy.owner(forGlobalRect:)`, gắn kết quả vào `region.owner` và
lưu xuống `Store`.

**Bắt đầu đọc.** `startCapturing` tính `regionGlobalRect` từ
`CGDisplayBounds(region.displayID)`. Nếu có `owner` và công tắc tổng đang bật thì
neo lại bằng `RegionFocusPolicy.reanchor`, cập nhật `owner` trong bộ nhớ (không
ghi xuống `Store` — số hiệu cửa sổ vô nghĩa ở phiên sau), rồi `windowWatcher.start`.

**Trong lúc chạy.** `onVerdictChange` chạy trên main:

- Sang `.paused` → bật cờ tạm dừng, `publishSnapshot(runState: .paused(lý do))`.
- Về `.active` → tắt cờ, `publishSnapshot` về `.listening` hoặc `.speaking` tuỳ
  hàng đợi đọc còn gì không.

Cờ tạm dừng là `nonisolated(unsafe) var isWindowPaused`, đọc và ghi dưới một
`NSLock` riêng, theo đúng khuôn `changeDetectedAt` với `latencyLock` đang có.
`handleFrame` chạy trên `capturer.captureQueue` và thoát ngay ở đầu khi cờ bật,
đồng thời gọi `captureState.reset()` để khung đầu tiên sau khi quay lại là mốc so
sánh mới chứ không bị so với khung trước lúc tạm dừng.

`TextGate` giữ nguyên qua đợt tạm dừng: quay lại mà câu phụ đề cũ vẫn còn trên
màn hình thì không đọc lại câu đã đọc. Câu đang phát dở lúc chuyển sang tạm dừng
được để đọc hết — cắt giữa chừng khó chịu hơn là thừa một câu.

Trạng thái tạm dừng ưu tiên hơn `.speaking` khi hiển thị.

**Đổi công tắc giữa chừng.** Bật hoặc tắt một trong hai công tắc trong lúc đang
đọc sẽ đẩy `Settings` mới xuống watcher và xét lại ngay, nên tắt công tắc tổng là
thoát khỏi trạng thái tạm dừng lập tức.

**Dừng đọc.** `stop()` gọi `windowWatcher.stop()` và tắt cờ. Phím tắt bật/tắt vẫn
hoạt động bình thường trong lúc tạm dừng, và bấm Dừng thì dừng hẳn.

## Lưu trữ và tương thích ngược

`SelectedRegion` thêm `public var owner: RegionOwner?`, giải mã bằng
`decodeIfPresent` như khuôn đang dùng trong `Settings`. Vùng đã lưu từ bản cũ vẫn
giải mã được và có `owner == nil`, nghĩa là chạy y hệt hiện tại. Người dùng nâng
cấp app sẽ không thấy hành vi đổi cho tới khi họ khoanh lại vùng — đây là chủ ý,
để bản nâng cấp không tự dưng câm.

`Settings` thêm hai khoá, cùng khuôn `decodeIfPresent` với mặc định:

- `pauseWhenWindowInactive: Bool = true`
- `pauseOnWindowTitleChange: Bool = true`

## Giao diện

`AppRunState` thêm `case paused(RegionPauseReason)`. `AppViewState.isCapturing`
trả `true` cho trạng thái này, nên nút chính vẫn là "Dừng đọc".

`DashboardContent` thêm nhánh tương ứng: tiêu đề "SubVoice đang chờ", phần mô tả
lấy từ lý do, `primaryActionTitle` là "Dừng đọc", `symbolName` là `pause.circle`,
không có nút khắc phục. Chữ theo từng lý do:

- `windowGone` → `Tạm dừng — cửa sổ Google Chrome không còn hiện`
- `windowCovered` → `Tạm dừng — vùng đọc đang bị che`
- `regionOutsideWindow` → `Tạm dừng — cửa sổ Google Chrome đã đổi vị trí`
- `contentChanged` → `Tạm dừng — cửa sổ Google Chrome đã đổi nội dung`

`StatusOrbView` thêm nhánh: `tint` dùng `theme.accent`, `isActive` bằng `false`
nên orb ngừng đập, nhãn accessibility là "Trạng thái: tạm dừng" kèm lý do. Màu
vẫn không phải kênh thông tin duy nhất — icon và nhãn accessibility đều riêng.

`FocusDashboardView` và `MenuBarController` thêm nhánh cho trạng thái mới;
menu bar đổi icon status item theo.

`SettingsView` thêm hai `Toggle`. Công tắc tiêu đề mờ đi (`.disabled`) khi công
tắc tổng đang tắt. Kèm hai `AppIntent` mới:
`setPauseWhenWindowInactive(Bool)` và `setPauseOnWindowTitleChange(Bool)`.

## Xử lý lỗi

- Không đọc được tiêu đề cửa sổ (thường là do Screen Recording bị thu hồi giữa
  chừng) → bỏ qua bước xét tiêu đề, không tạm dừng vì thiếu thông tin.
- Neo lại cửa sổ thất bại lúc bắt đầu đọc → chạy không khoá cửa sổ, không cảnh
  báo. Người dùng vẫn nghe được phụ đề, đó mới là việc chính.
- `CGDisplayBounds` trả về hình rỗng vì màn hình đã rút → `ScreenCapturer` vốn đã
  báo lỗi `displayNotFound` ở đường khác; watcher không khởi động và capture thất
  bại như hiện tại.
- Danh sách cửa sổ rỗng (`CGWindowListCopyWindowInfo` trả `nil`) → coi như không
  đổi, giữ nguyên kết luận cũ thay vì tạm dừng oan.

## Test

Toàn bộ luật nằm ở hàm thuần nên test bằng `WindowSnapshot` dựng tay, không cần
màn hình thật.

`RegionFocusPolicyTests`:

- `owner` bằng `nil` → `.active`
- công tắc tổng tắt → `.active`
- `windowNumber` bằng `nil` → `.active`
- cửa sổ đích không có trong danh sách → `.windowGone`
- vùng đọc thò ra ngoài khung cửa sổ → `.regionOutsideWindow`
- cửa sổ layer 0 đứng trước và đè lên vùng → `.windowCovered`
- cửa sổ đứng trước nhưng không đè lên vùng → `.active`
- cửa sổ đứng trước có `alpha == 0` → `.active`
- cửa sổ đứng trước thuộc SubVoice → `.active`
- cửa sổ đứng trước có `layer != 0` (thanh menu, Dock) → `.active`
- tiêu đề đổi, công tắc bật → `.contentChanged`
- tiêu đề đổi, công tắc tắt → `.active`
- tiêu đề hiện tại `nil` → `.active`
- tiêu đề chỉ khác phần đếm `(3) ` ở đầu → `.active`
- `reanchor` khớp theo tiêu đề; khớp theo bundle và khung chứa vùng; không khớp
  trả `nil`; bỏ qua cửa sổ của SubVoice
- cửa sổ đích bị cấp lại số hiệu cho app khác → `.windowGone`
- `owner(forGlobalRect:)` lấy cửa sổ trên cùng chứa trọn vùng; bỏ qua cửa sổ của
  SubVoice; vùng tràn ra ngoài mép mọi cửa sổ thì trả `nil`

`GeometryTests`: thêm ca cho `toGlobalTopLeft`, gồm display phụ có gốc khác không.

`SelectedRegionTests`: JSON cũ không có `owner` vẫn giải mã; vòng mã hoá và giải
mã giữ nguyên `owner`.

`SettingsTests`: hai khoá mới mặc định bật; JSON cũ thiếu khoá vẫn ra mặc định.

`DashboardContentTests`: nhãn của bốn lý do tạm dừng.

Ngoài phạm vi unit test, và chấp nhận kiểm bằng tay: `WindowWatcher.snapshot()`
dịch đúng từ `CGWindowListCopyWindowInfo`, và timer chạy đúng nhịp.

## Hạn chế đã biết

- App nào giữ một cửa sổ layer 0 trong suốt phủ toàn màn hình (một số công cụ vẽ
  lên màn hình, một số tiện ích menu bar) sẽ bị tính là che vùng đọc và làm
  SubVoice tạm dừng oan. Lối thoát là tắt công tắc tổng. Bộ lọc `alpha > 0` gạt
  được phần lớn nhóm này nhưng không phải tất cả.
- Trang web tự đổi tiêu đề của nó — Netflix sang tập mới, YouTube thêm phần đếm
  thông báo — sẽ bị tính là đổi nội dung. Cắt phần đếm `(n) ` gạt được ca hay gặp
  nhất; còn lại thì tắt công tắc tiêu đề.
- Đổi tab về đúng tab cũ thì tiêu đề khớp lại và app tự đọc tiếp, nhưng nếu tab
  cũ đã đổi tiêu đề trong lúc đó thì phải khoanh lại vùng.
- Khoanh vùng tràn ra ngoài mép cửa sổ thì vùng không có chủ và tính năng này
  không hoạt động với nó. Người dùng không được báo gì; họ chỉ thấy app đọc như
  bản cũ.
- Poll 0.4 giây nghĩa là chậm nhất 0.4 giây mới dừng sau khi bị che. Đổi app và
  đổi Space thì phản ứng ngay nhờ thông báo của `NSWorkspace`.
