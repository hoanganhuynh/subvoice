<div align="center">

# SubVoice

### Đọc phụ đề tiếng Việt trên màn hình thành giọng nói — riêng tư, offline, dành cho macOS

[![macOS 14+](https://img.shields.io/badge/macOS-14%2B-111111?logo=apple&logoColor=white)](https://support.apple.com/macos)
[![Swift 6](https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white)](https://www.swift.org/)
[![Offline](https://img.shields.io/badge/xử_lý-100%25_offline-2ea44f)](#quyền-riêng-tư)
[![Swift Testing](https://img.shields.io/badge/tests-Swift_Testing-6f42c1)](#kiểm-thử)

Chọn một vùng phụ đề trên màn hình. SubVoice nhận diện chữ tiếng Việt, lọc câu trùng và đọc thành tiếng — điều khiển từ cửa sổ chính hoặc từ menu bar.

<img src="Resources/Screenshots/main-window.png" alt="Cửa sổ chính của SubVoice ở chế độ tối" width="820">

</div>

---

## Điểm nổi bật

- **Cửa sổ chính Focus First** — trạng thái, nút bật/tắt và ba thẻ điều khiển trong một màn hình.
- **Menu bar vẫn còn nguyên** cho thao tác nhanh khi cửa sổ đã đóng.
- **OCR tiếng Việt có dấu** bằng Vision, được hâm nóng để giảm độ trễ câu đầu.
- **Hai bộ đọc offline:** giọng hệ thống nhanh và Kokoro tự nhiên với 14 giọng Việt.
- **Voice Studio** — đổi bộ đọc, giọng, tốc độ, âm lượng và thử giọng ngay tại chỗ.
- **Lịch sử chỉ trong phiên** — tìm kiếm, sao chép, tự xoá khi thoát app.
- **Cài Kokoro từ trong app** — một gói tự chứa, tải nền, không cần Python trên máy.
- **Hướng dẫn lần đầu** năm bước, bỏ qua được ở bất kỳ đâu.
- **Chẩn đoán tại chỗ** cho quyền Screen Recording, giọng hệ thống và Kokoro.
- **Không đọc lặp** khi phụ đề đứng yên; xử lý được phụ đề xuất hiện kiểu fade-in.
- **Không bỏ câu đã nhận diện** — hàng đợi FIFO giữ đúng thứ tự hội thoại.
- **Giao diện System, Light hoặc Dark**, theo phím tắt và VoiceOver.
- **Phím tắt toàn cục** hoạt động cả khi trình duyệt hoặc video đang toàn màn hình.
- **Không gửi ảnh hay nội dung phụ đề ra mạng.**

## Cách SubVoice hoạt động

```text
Vùng màn hình
     │
     ▼
ScreenCaptureKit ──▶ ChangeDetector ──▶ Vision OCR ──▶ TextGate
                                                              │
                                                              ▼
                                     SpeechQueue ──▶ Linh / Kokoro ──▶ Loa
```

SubVoice chỉ chạy OCR khi chữ ký độ sáng của vùng phụ đề thay đổi. Văn bản sau đó được chuẩn hoá, lọc trùng và đưa vào hàng đợi trước khi đọc.

## Yêu cầu

- macOS 14 trở lên
- Máy Mac dùng Apple Silicon được khuyến nghị
- Xcode 16 hoặc Swift 6 toolchain
- Quyền **Screen Recording**
- Giọng tiếng Việt của macOS nếu dùng bộ đọc hệ thống

SubVoice không cần quyền Microphone, Accessibility hoặc Input Monitoring.

## Cài đặt nhanh

```bash
git clone https://github.com/hoanganhuynh/subvoice.git
cd subvoice
./Scripts/bundle.sh release
open ~/Applications/SubVoice.app
```

Lần chạy đầu, macOS sẽ yêu cầu quyền **Screen Recording**. Cấp quyền tại:

`System Settings → Privacy & Security → Screen & System Audio Recording`

Sau khi cấp quyền, hãy thoát rồi mở lại SubVoice.

> [!NOTE]
> Script cài app vào `~/Applications/SubVoice.app`. Giữ đường dẫn và chữ ký ổn định giúp macOS không hỏi lại quyền Screen Recording sau mỗi lần build.

## Sử dụng

1. Lần đầu mở, SubVoice dẫn bạn qua năm bước: cấp quyền, chọn giọng, chọn vùng.
   Bỏ qua bước nào cũng được, và chạy lại được từ **Cài đặt → Chạy lại hướng dẫn**.
2. Cửa sổ chính mở ra ở trạng thái dừng — app không bao giờ tự đọc khi vừa khởi động.
3. Bấm thẻ **Vùng đọc**, rồi kéo quanh khu vực hiển thị phụ đề.
4. Bấm **Bắt đầu đọc**.
5. Bấm thẻ **Giọng đọc** để mở Voice Studio và chỉnh bộ đọc, giọng, tốc độ, âm lượng.
6. Bấm thẻ **Vừa đọc** để tìm và sao chép những câu đã đọc trong phiên.

Đóng cửa sổ không làm SubVoice dừng lại: app tiếp tục chạy trên menu bar và pipeline
đang đọc không bị ngắt. Bấm Dock icon hoặc **Mở SubVoice** trên menu bar để hiện lại
cửa sổ; chỉ <kbd>⌘</kbd> + <kbd>Q</kbd> mới thoát hẳn.

Menu bar giữ đủ các điều khiển nhanh — bật/tắt đọc, chọn lại vùng, đổi bộ đọc, giọng,
tốc độ, âm lượng và khởi động cùng máy — để bạn không phải rời khỏi video đang xem.

### Phím tắt

| Phím | Hành động |
| --- | --- |
| <kbd>⌥</kbd> + <kbd>⌘</kbd> + <kbd>V</kbd> | Bật hoặc tắt đọc |
| <kbd>⌥</kbd> + <kbd>⌘</kbd> + <kbd>R</kbd> | Chọn lại vùng phụ đề |

## Bộ đọc

### Hệ thống — nhanh

Dùng `AVSpeechSynthesizer` và ưu tiên giọng **Linh** (`vi-VN`). Bộ đọc này có độ trễ thấp, phù hợp khi cần theo sát phụ đề realtime.

Nếu máy chưa có giọng Việt, mở:

`System Settings → Accessibility → Spoken Content → System Voice`

### Kokoro — tự nhiên, offline

Dùng [Kokoro-Vietnamese](https://github.com/iamdinhthuan/Kokoro-Vietnamese) qua ONNX Runtime. Model được nạp trong một tiến trình Python thường trú; SubVoice hỗ trợ 14 voice pack và tự chuyển về giọng hệ thống nếu Kokoro gặp lỗi.

Gói Kokoro nặng khoảng **680 MB** khi tải và khoảng 1,1 GB sau khi giải nén. Nó gồm sẵn một bản CPython relocatable, nên máy bạn không cần cài Python. Các tệp này không được commit vào repo.

#### Cài Kokoro

Không cần chuẩn bị gì. Mở SubVoice, vào **Cài đặt → Chẩn đoán → Kokoro** rồi bấm
**Tải giọng Kokoro**. App tải một gói tự chứa gồm cả Python runtime lẫn model,
đối chiếu SHA-256 rồi cài vào máy.

Tải xong là 14 giọng Kokoro xuất hiện ngay, **không cần khởi động lại app**. Gói
này chỉ có bản Apple Silicon.

Trong lúc tải, SubVoice vẫn dùng được bình thường với giọng hệ thống. Thoát app
giữa chừng cũng không mất phần đã tải — lần mở sau tải tiếp.

#### Đóng gói lại Kokoro (dành cho người bảo trì)

```bash
./Scripts/package-kokoro.sh 1.0.0
```

Script dựng một CPython relocatable, cài dependency bằng `pip install --target`,
tải model, convert voicepack sang `.npy`, cắt bỏ toàn bộ stack PyTorch, rồi
**chạy self-test dưới `env -i`** trước khi nén. Self-test hỏng thì archive không
được tạo ra.

Script in ra `SHA256` và `SIZE`. Dán hai giá trị đó vào `KokoroPackage.current`
trong `Sources/SubVoiceCore/KokoroPackage.swift`, rồi attach archive vào GitHub
Release trùng tag với `downloadURL`.

Runtime được cài tại:

```text
~/Library/Application Support/SubVoice/Kokoro
```

Lần đầu chọn Kokoro có thể mất khoảng 3 giây để nạp model. Thời gian tổng hợp thông thường khoảng 1–1,6 giây mỗi câu, tuỳ độ dài và máy.

### Tốc độ Kokoro

Năm mức tốc độ được ánh xạ sang dải `0,65×–1,55×`. Thay đổi có hiệu lực từ câu kế tiếp; câu đang được tạo hoặc đang phát vẫn giữ tốc độ cũ.

## Quyền riêng tư

Toàn bộ pipeline chạy trên máy:

- ScreenCaptureKit chỉ lấy vùng bạn đã chọn.
- Vision thực hiện OCR cục bộ.
- Linh và Kokoro đều tạo giọng offline.
- Lịch sử phiên chỉ nằm trong bộ nhớ tiến trình, tối đa 200 câu, và biến mất khi bạn thoát app. Nó không được ghi vào `UserDefaults` hay bất kỳ file log nào.
- SubVoice không có API phân tích, quảng cáo hoặc đồng bộ đám mây.

## Kiến trúc dự án

```text
Sources/
├── SubVoiceApp/      # Vòng đời AppKit: cửa sổ, menu bar, capture, OCR, TTS
├── SubVoiceUI/       # State trình bày và toàn bộ view SwiftUI
├── SubVoiceCore/     # Detector, lọc văn bản, hàng đợi, lịch sử và cài đặt
└── SubVoiceProbe/    # Công cụ đo OCR/capture

Resources/
├── kokoro_service.py # Sidecar JSON-lines thường trú
└── Screenshots/      # Ảnh dùng trong tài liệu

Scripts/
├── bundle.sh         # Build, ký và cài SubVoice.app
├── smoke-overlay.sh  # Kiểm tra vòng đời overlay
├── smoke-window.sh   # Kiểm tra vòng đời cửa sổ chính
├── package-kokoro.sh # Đóng gói runtime Kokoro (người bảo trì)
└── trace.sh          # Đọc trace chẩn đoán

Tests/
├── SubVoiceCoreTests/
└── SubVoiceUITests/
```

`AppCoordinator` sở hữu mọi dịch vụ đang chạy và là nơi duy nhất tạo ra ảnh chụp
trạng thái. Cửa sổ SwiftUI và menu bar cùng đọc một ảnh chụp đó và chỉ gửi lệnh
ngược lại, nên hai nơi không thể hiển thị lệch nhau.

## Kiểm thử

Chạy toàn bộ unit test và performance test:

```bash
swift test
```

Kiểm tra overlay chọn vùng dưới NSZombie:

```bash
./Scripts/smoke-overlay.sh
```

Kiểm tra vòng đời cửa sổ chính:

```bash
./Scripts/smoke-window.sh
```

Bật trace khi cần tìm câu bị bỏ qua:

```bash
open ~/Applications/SubVoice.app --args --trace
./Scripts/trace.sh 100
```

## Giới hạn đã biết

- SubVoice chỉ đọc chữ đang hiển thị trong vùng màn hình đã chọn.
- Nội dung DRM có thể chặn Screen Recording; phụ đề dạng lớp HTML bên ngoài video thường vẫn đọc được.
- Kokoro tự nhiên hơn nhưng chậm hơn đáng kể so với giọng hệ thống.
- Phiên bản hiện tại tập trung vào tiếng Việt và macOS.

## Ghi nhận

- [Kokoro-Vietnamese](https://github.com/iamdinhthuan/Kokoro-Vietnamese) — model và frontend tiếng Việt, giấy phép Apache-2.0.
- [contextboxai/Kokoro-Vietnamese](https://huggingface.co/contextboxai/Kokoro-Vietnamese) — ONNX model và voice packs.
- Apple Vision, ScreenCaptureKit và AVFoundation — OCR, capture và phát âm thanh native trên macOS.

---

<div align="center">

**SubVoice — nghe phụ đề, không rời mắt khỏi bộ phim.**

</div>
