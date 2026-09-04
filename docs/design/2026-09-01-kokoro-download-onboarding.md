# SubVoice — Tải Kokoro theo yêu cầu và onboarding lần đầu

Ngày chốt thiết kế: 2026-09-01

Trạng thái: Đã duyệt

## Mục tiêu

Làm cho SubVoice cài được trên máy người khác. Hiện tại không cài được: gói Kokoro chỉ chạy trên máy đã build nó, và người dùng mới không có gì dẫn họ qua bước cấp quyền.

Bản này giải quyết hai việc:

- Đóng gói Kokoro thành một archive tự chứa, tải theo yêu cầu, cài xong là dùng được ngay mà không cần khởi động lại app.
- Thêm một wizard lần đầu chạy, dẫn người dùng qua quyền Screen Recording, giọng đọc và vùng phụ đề.

## Bối cảnh — vì sao bản hiện tại không share được

Ba vấn đề độc lập, đã kiểm chứng trên máy build:

1. **Venv trỏ đường dẫn tuyệt đối.** `Kokoro/.venv/bin/python` là symlink tới
   `/Users/anthony/.local/share/uv/python/cpython-3.12-macos-aarch64-none/bin/python3.12`,
   và `pyvenv.cfg` cũng ghi `home` về đó. Trên máy khác đường dẫn này không tồn tại,
   `KokoroRuntime.discover()` trả về failure, app im lặng lùi về giọng hệ thống.
2. **1,3 GB không thể nằm trong app bundle.** Trong đó `torch` chiếm ~430 MB nhưng
   chỉ được dùng cho đúng một lời gọi `torch.load` để nạp voicepack; `gradio`,
   `fastapi` và `PIL` (~50 MB) là web UI của upstream, không liên quan gì tới SubVoice.
3. **Không có onboarding.** Người mới không biết phải cấp quyền Screen Recording,
   và cũng không biết quyền đó chỉ có hiệu lực sau khi thoát và mở lại app.

## Phạm vi

Trong phạm vi:

- Script đóng gói Kokoro thành archive tự chứa, do người bảo trì chạy.
- Phân phối archive qua GitHub Releases.
- Tải, kiểm tra chữ ký, giải nén và cài trong app.
- Tái tạo speech backend sau khi cài để Kokoro dùng được ngay.
- Wizard onboarding năm bước, bỏ qua được.
- Hiển thị tiến trình tải ở cả ba nơi: onboarding, Voice Studio và Settings.
- Tải tiếp sau khi thoát app giữa chừng.

Ngoài phạm vi:

- Ký Developer ID và notarization.
- Kiến trúc Intel x86_64. Bản này chỉ hỗ trợ Apple Silicon.
- Tự động cập nhật runtime Kokoro khi có phiên bản mới.
- Đa ngôn ngữ giao diện.
- Thay đổi detector, OCR, TextGate, SpeechQueue hoặc overlay chọn vùng.

## Quyết định sản phẩm

### Đóng gói

Dùng **CPython relocatable** (`python-build-standalone`) và cài thẳng dependency
bằng `pip install --target`. Không dùng venv. Venv sinh ra chính lỗi đường dẫn
tuyệt đối ở trên; bỏ hẳn nó thì không còn gì để mà hỏng.

`Scripts/package-kokoro.sh` là script của người bảo trì, không phải người dùng:

1. Tải CPython relocatable cho `aarch64-apple-darwin`.
2. `pip install --target site-packages` đúng những gì cần: `onnxruntime`, `numpy`,
   `soundfile`, `sea_g2p`, `kokoro_vietnamese`. Không cài `torch`, `gradio`,
   `fastapi`, `PIL`.
3. Tải `kokoro_vi.onnx`, `config.json` và voicepacks từ HuggingFace.
4. **Convert 14 voicepack `.pt` sang `.npy`.** Đây là bước loại bỏ `torch`:
   `select_voice_style()` trong `onnx_utils.py` đã gọi `np.asarray()` và chỉ dùng
   `.detach()` khi có, nên nó nhận mảng numpy trực tiếp mà không cần sửa gì.
5. Nén thành `kokoro-runtime-<version>-arm64.tar.zst` và in ra SHA-256.

Người bảo trì attach file kết quả vào một GitHub Release.

Bố cục sau khi cài vào `~/Library/Application Support/SubVoice/Kokoro/`:

```text
Kokoro/
├── python/                 # CPython relocatable
├── site-packages/          # dependency, không có torch
├── models/
│   ├── kokoro_vi.onnx
│   ├── config.json
│   └── voicepacks/*.npy
├── kokoro_service.py
└── manifest.json           # version, sha256, ngày tạo
```

### Phân phối

GitHub Releases trên repo SubVoice. URL cố định theo tag, băng thông không giới hạn
với public repo, và giới hạn 2 GB mỗi file thừa sức cho ~550 MB.

App nhúng ba hằng số: URL tải, phiên bản runtime kỳ vọng, và SHA-256 kỳ vọng. App
không dò tìm bản mới; nâng cấp runtime là việc của bản phát hành sau.

App coi runtime là đã cài khi và chỉ khi `manifest.json` tồn tại và `version` trong
đó khớp hằng số nhúng. Phiên bản lệch được coi như chưa cài và app mời tải lại — đây
cũng là đường mà bản cài kiểu cũ (thư mục `.venv`) đi qua để được thay thế.

### Tải

Máy trạng thái duy nhất, mọi giao diện cùng đọc:

```swift
enum KokoroInstallState {
    case notInstalled
    case downloading(received: Int64, total: Int64)
    case verifying
    case extracting
    case installed(version: String)
    case failed(message: String)
}
```

Trạng thái này nằm trong `AppViewState.kokoroInstall`, nên onboarding, Voice Studio
và Settings hiển thị cùng một tiến trình thay vì mỗi nơi tự đếm.

Trình tự:

1. Kiểm tra còn ít nhất 1,5 GB trống. Không đủ thì dừng ngay với thông báo rõ,
   không tải rồi mới báo lỗi.
2. `URLSession.downloadTask`, tiến trình qua delegate.
3. Đối chiếu SHA-256 với hằng số nhúng trong app.
4. `tar --zstd -xf` vào `Kokoro.incoming/`. macOS 14 có sẵn bsdtar hỗ trợ zstd,
   không cần thư viện ngoài.
5. **Đổi tên nguyên thư mục.** Nếu đã có `Kokoro` cũ thì đổi tên nó thành
   `Kokoro.old`, đổi `Kokoro.incoming` thành `Kokoro`, rồi mới xoá `Kokoro.old`.
   Trình tự này đảm bảo không bao giờ tồn tại bản cài dở, và bản cũ vẫn còn nguyên
   cho tới khi bản mới đã vào đúng chỗ.

Tải là tuỳ chọn và luôn chạy nền. App dùng được bình thường trong suốt quá trình.

**Tải tiếp:** `resumeData` được ghi xuống đĩa khi người dùng huỷ hoặc thoát app.
Lần mở sau, nếu có dữ liệu này thì app hỏi "Tải tiếp?" thay vì bắt tải lại từ đầu.

**Tái tạo backend:** `KokoroSpeechBackend` hiện tính `runtimeResult` đúng một lần
lúc `init`. Nếu không xử lý, cài xong app vẫn nghĩ Kokoro chưa có. Coordinator sẽ
tạo một instance backend mới khi cài xong rồi gọi `publishSnapshot()`. Kokoro sáng
lên trong bộ chọn và 14 giọng xuất hiện mà không cần khởi động lại app.

### Onboarding

Wizard toàn cửa sổ, năm bước, góc trên luôn có **Bỏ qua**, chân hiện chỉ báo bước.
`SubVoiceRootView` chọn giữa `OnboardingView` và `FocusDashboardView` dựa trên
`Settings.hasCompletedOnboarding`.

| Bước | Nội dung |
| --- | --- |
| 1. Chào mừng | SubVoice làm gì, và một câu về việc mọi thứ chạy trên máy người dùng. |
| 2. Screen Recording | Trạng thái quyền tính lại theo thời gian thực, nút mở System Settings, và nói thẳng rằng phải thoát rồi mở lại app thì quyền mới có hiệu lực. |
| 3. Giọng đọc | Giọng hệ thống tìm thấy trên máy; thiếu thì dẫn sang Spoken Content. Thẻ Kokoro ghi rõ dung lượng, hai nút *Tải giọng Kokoro* và *Để sau*. Bấm tải thì chạy nền và wizard vẫn đi tiếp được. |
| 4. Chọn vùng | Nút mở overlay chọn vùng phụ đề; chọn xong quay lại wizard. Bỏ qua được. |
| 5. Xong | Nhắc `⌥⌘V`, `⌥⌘R`, và việc đóng cửa sổ không làm app thoát. |

Điều hướng giữa các bước là trạng thái cục bộ của view. Chỉ những hành động chạm
vào dịch vụ mới đi qua intent: mở System Settings, chọn vùng, tải Kokoro, kết thúc
wizard.

Người dùng đã có vùng đọc được lưu từ trước được coi như đã onboard, để bản nâng
cấp không bắt họ xem lại wizard. Settings có mục **Chạy lại hướng dẫn**.

## Kiến trúc

### File mới

- `Scripts/package-kokoro.sh` — đóng gói runtime, chạy bởi người bảo trì.
- `Sources/SubVoiceCore/KokoroPackage.swift` — mô tả gói (URL, phiên bản, SHA-256)
  và **toàn bộ bước cài thuần**: đối chiếu checksum, giải nén, đổi tên nguyên khối,
  dọn rác. Nhận file đã tải về như một tham số, không tự đi mạng.
- `Sources/SubVoiceApp/KokoroInstaller.swift` — phần chạm hệ thống: `URLSession`,
  tiến trình, `resumeData`, và gọi vào `KokoroPackage` để cài.
- `Sources/SubVoiceUI/KokoroInstallState.swift` — trạng thái cài đặt và phần trăm.
- `Sources/SubVoiceUI/OnboardingStep.swift` — thứ tự bước, thuần giá trị.
- `Sources/SubVoiceUI/OnboardingView.swift` — wizard.
- `Tests/SubVoiceUITests/OnboardingStepTests.swift`
- `Tests/SubVoiceUITests/KokoroInstallStateTests.swift`
- `Tests/SubVoiceCoreTests/KokoroPackageTests.swift`

Ranh giới này có lý do: `SubVoiceApp` là executable target nên rất khó test trực
tiếp. Đẩy phần logic đáng test — checksum, bố cục thư mục, tính nguyên khối của
bước cài — sang `SubVoiceCore` thì test được bằng thư mục tạm và không cần mạng.
`SubVoiceApp` chỉ còn lại phần glue mỏng.

### File sửa

- `Resources/kokoro_service.py` — bỏ `import torch`, nạp voicepack bằng `np.load`.
- `Sources/SubVoiceApp/KokoroRuntime.swift` — tìm `python/bin/python3` và
  `manifest.json` thay cho `.venv/bin/python`; đặt `PYTHONPATH` trỏ vào `site-packages`.
- `Sources/SubVoiceApp/KokoroSpeechBackend.swift` — cho phép tạo lại sau khi cài.
- `Sources/SubVoiceApp/AppCoordinator.swift` — sở hữu installer, xử lý intent mới.
- `Sources/SubVoiceUI/AppViewState.swift` — thêm `kokoroInstall` và các intent mới.
- `Sources/SubVoiceUI/SubVoiceRootView.swift` — rẽ nhánh onboarding.
- `Sources/SubVoiceUI/VoiceStudioView.swift`, `SettingsView.swift` — hiện tiến trình.
- `Sources/SubVoiceCore/Settings.swift` — thêm `hasCompletedOnboarding`.
- `Scripts/bundle.sh` — bỏ phần sao chép `.venv`; `SUBVOICE_INCLUDE_KOKORO` chuyển
  sang cài từ archive cục bộ để người phát triển thử nghiệm.
- `README.md` — hướng dẫn cài cho người dùng cuối.

### Intent mới

`.downloadKokoro`, `.cancelKokoroDownload`, `.finishOnboarding`, `.restartOnboarding`.

Giữ nguyên nguyên tắc đã có: `AppCoordinator` là nơi duy nhất tạo ảnh chụp trạng
thái, giao diện chỉ đọc state và gửi intent.

## Xử lý lỗi

| Tình huống | Hành vi |
| --- | --- |
| Không đủ dung lượng | Dừng trước khi tải, nêu rõ cần bao nhiêu và còn bao nhiêu. |
| Mất mạng giữa chừng | `.failed` kèm nút Thử lại; `resumeData` được giữ để tải tiếp. |
| SHA-256 không khớp | Xoá file tải về, báo gói không toàn vẹn, mời thử lại. Không bao giờ cài gói sai chữ ký. |
| Giải nén lỗi | Xoá `Kokoro.incoming`, giữ nguyên bản cũ nếu có. |
| Cài xong nhưng runtime vẫn không chạy | Hiện đúng lý do thật từ `KokoroRuntime.discover()`, không báo chung chung. |
| Người dùng xoá thư mục Kokoro | Lần dùng kế tiếp `discover()` fail, app lùi về giọng hệ thống và Settings hiện trạng thái chưa cài. |
| Thiếu quyền Screen Recording | Giữ nguyên hành vi hiện có: warning state kèm nút mở System Settings. |

## Lưu trữ

- `Settings` thêm `hasCompletedOnboarding`; thiếu khoá thì mặc định `false`, nhưng
  nếu đã có vùng đọc lưu từ trước thì coi như `true`.
- `resumeData` ghi tại `~/Library/Application Support/SubVoice/kokoro-resume.data`,
  không nhét vào `UserDefaults`.
- `manifest.json` nằm trong thư mục Kokoro, ghi phiên bản đã cài.
- Lịch sử phiên vẫn chỉ nằm trong bộ nhớ, không đổi.

## Kiểm thử

### Tự động

- Thứ tự bước onboarding, hành vi bỏ qua và quay lui.
- Chuyển trạng thái `KokoroInstallState` và phần trăm tiến trình.
- `KokoroPackage` với archive dựng sẵn trong thư mục tạm, **không cần mạng**:
  checksum sai bị từ chối và không để lại dấu vết, thư mục đích chỉ xuất hiện sau
  bước đổi tên, bản cũ vẫn nguyên vẹn nếu bước giữa thất bại, và `Kokoro.incoming`
  được dọn trong mọi nhánh lỗi.
- Migration `hasCompletedOnboarding` cho payload cũ.
- Giữ nguyên toàn bộ unit test, performance test và hai smoke script hiện có.

### Thủ công

- Cài trên một tài khoản macOS sạch: chạy wizard, cấp quyền, khởi động lại app,
  tải Kokoro, nghe thử giọng.
- Ngắt mạng giữa chừng rồi tải tiếp.
- Bỏ qua toàn bộ wizard và xác nhận app vẫn dùng được với giọng hệ thống.
- Kokoro sáng lên trong Voice Studio ngay sau khi cài, không khởi động lại app.
- Thoát app giữa lúc tải, mở lại và tải tiếp.

## Rủi ro đã biết

1. **Chữ ký binary tải về.** Apple Silicon yêu cầu mọi executable phải được ký ít
   nhất ở mức ad-hoc. Nếu bản CPython upstream chưa ký thì installer phải chạy
   `codesign -s -` sau khi giải nén. Phải kiểm chứng ở bước đầu của quá trình
   triển khai, trước khi xây phần còn lại.
2. **`sea_g2p` có thể kéo `torch` ngược vào.** Đã xác nhận đường ONNX chỉ dùng
   numpy, nhưng dependency của `sea_g2p` chưa được kiểm tra. Nếu nó thật sự cần
   `torch`, payload quay lại ~1 GB và phải quyết lại.
3. **Chỉ Apple Silicon.** Mac Intel không có gói runtime và sẽ chỉ dùng được giọng
   hệ thống.
4. **Bước cấp quyền là chỗ rụng người dùng.** macOS bắt buộc khởi động lại app sau
   khi cấp quyền Screen Recording. Thiết kế chọn nói rõ điều đó thay vì để người
   dùng tưởng app hỏng.

## Tiêu chí hoàn thành

- `Scripts/package-kokoro.sh` tạo ra archive chạy được trên một máy chưa từng có
  Kokoro và chưa cài Python.
- App tải, kiểm tra và cài archive đó; Kokoro dùng được ngay không cần khởi động lại.
- Tải chạy nền, không chặn bất kỳ chức năng nào của app.
- Thoát app giữa chừng rồi mở lại vẫn tải tiếp được.
- Wizard năm bước chạy đúng, bỏ qua được ở mọi bước, và chạy lại được từ Settings.
- Người dùng bỏ qua toàn bộ wizard vẫn dùng được app với giọng hệ thống.
- Toàn bộ test tự động và hai smoke script đều đạt.
- README hướng dẫn được người dùng cuối cài đặt mà không cần đọc source.
