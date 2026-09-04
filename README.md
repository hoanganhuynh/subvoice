<div align="center">

<img src="Resources/AppIcon.png" alt="SubVoice" width="128">

# SubVoice

### Đọc phụ đề tiếng Việt trên màn hình thành giọng nói, chạy offline trên macOS

[![macOS 14+](https://img.shields.io/badge/macOS-14%2B-111111?logo=apple&logoColor=white)](https://support.apple.com/macos)
[![Apple Silicon](https://img.shields.io/badge/Apple_Silicon-arm64-555555?logo=apple&logoColor=white)](#yêu-cầu)
[![Swift 6](https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white)](https://www.swift.org/)
[![Offline](https://img.shields.io/badge/xử_lý-100%25_offline-2ea44f)](#quyền-riêng-tư)
[![Tests](https://img.shields.io/badge/tests-119_passing-6f42c1)](#kiểm-thử)

[Tải về](#tải-về) · [Tính năng](#tính-năng) · [Cách hoạt động](#cách-hoạt-động) · [Quyền riêng tư](#quyền-riêng-tư)

<br>

<img src="Resources/Screenshots/main-window.png" alt="Cửa sổ chính của SubVoice" width="820">

</div>

---

Xem phim có phụ đề tiếng Việt thì mắt phải chạy theo chữ, thành ra bỏ lỡ diễn xuất. SubVoice khoanh một vùng trên màn hình, nhận diện chữ trong đó rồi đọc thành tiếng, để bạn nghe thoại và nhìn hình.

Nó đọc được phụ đề nào hiện lên màn hình: YouTube, IINA, VLC, hay phụ đề dạng lớp HTML nằm ngoài khung video.

Nội dung có DRM thì không. Netflix, Apple TV+ và tương tự bị macOS chặn khỏi Screen Recording ở tầng hệ điều hành, SubVoice chỉ nhận được khung đen.

## Tải về

<div align="center">

### [⬇️ Tải SubVoice 0.1.0](https://github.com/hoanganhuynh/subvoice/releases/download/v0.1.0/SubVoice-0.1.0.zip)

`SubVoice-0.1.0.zip` · 2,7 MB · macOS 14+ · Apple Silicon

<sub>[Xem tất cả phiên bản](https://github.com/hoanganhuynh/subvoice/releases)</sub>

</div>

Giải nén rồi kéo `SubVoice.app` vào thư mục Applications. Mở app, một hướng dẫn 5 bước sẽ đưa bạn qua phần cấp quyền và chọn vùng phụ đề.

> [!WARNING]
> SubVoice chưa được Apple notarize. Lần đầu mở, macOS sẽ báo *"không thể mở vì không xác minh được nhà phát triển"* và chặn lại.

<details>
<summary><b>Cách mở app lần đầu</b></summary>

<br>

Ba cách, xếp từ ít ảnh hưởng tới nhiều.

**Control-click.** Nhấn giữ <kbd>Control</kbd>, bấm vào `SubVoice.app`, chọn Open, rồi bấm Open lần nữa trong hộp thoại. Làm một lần duy nhất và chỉ áp dụng cho app này.

**Gỡ cờ quarantine.** Dùng khi cách trên không hiện tuỳ chọn Open.

```bash
xattr -dr com.apple.quarantine /Applications/SubVoice.app
```

Cũng chỉ tác động lên một app.

**Tắt Gatekeeper toàn hệ thống.**

```bash
sudo spctl --master-disable
```

Lệnh này tắt kiểm tra cho mọi app bạn tải về sau này, không riêng SubVoice. Chỉ nên dùng nếu bạn thật sự cần cài nhiều app ngoài App Store, và nhớ bật lại:

```bash
sudo spctl --master-enable
```

Hướng dẫn chi tiết kèm ảnh: [maclife.io.vn](https://maclife.io.vn/huong-dan-tat-gatekeeper-tren-macbook/)

</details>

> [!IMPORTANT]
> Ở bước cấp quyền Screen Recording, sau khi bật trong System Settings bạn phải thoát SubVoice rồi mở lại. macOS chỉ áp dụng quyền này ở lần khởi động kế tiếp.

<div align="center">
<img src="Resources/Screenshots/onboarding.png" alt="Hướng dẫn lần đầu chạy" width="720">
</div>

## Tính năng

Cửa sổ chính đặt trạng thái và nút bật/tắt ở giữa. Ba thẻ dưới đáy cho biết đang đọc vùng nào, bằng giọng gì, và câu gần nhất vừa đọc là gì. Bấm vào thẻ nào thì mở phần đó ra.

Có hai bộ đọc. Giọng hệ thống của macOS phản hồi trong khoảng 50 ms nên bám kịp phụ đề đang chạy. Kokoro nghe tự nhiên hơn nhiều nhưng chậm hơn, và phải tải thêm 680 MB. Đổi qua lại lúc nào cũng được trong Voice Studio, cùng chỗ để chỉnh tốc độ, âm lượng và nghe thử.

Phụ đề đứng yên thì app im lặng chứ không đọc đi đọc lại. Phụ đề hiện dần kiểu fade-in hay cảnh đổi nhanh vẫn xử lý được.

Lịch sử phiên giữ tối đa 200 câu để bạn tìm lại hoặc sao chép. Nó nằm trong bộ nhớ và mất khi bạn thoát app.

Phím tắt toàn cục chạy cả khi video đang toàn màn hình ở app khác. Mục chẩn đoán trong Cài đặt kiểm tra quyền Screen Recording, giọng hệ thống và tình trạng Kokoro, mỗi mục kèm nút xử lý nếu thiếu.

Giao diện theo sáng, tối, hoặc theo hệ thống. Dùng được hoàn toàn bằng bàn phím và VoiceOver, có tôn trọng Increase Contrast và Reduce Motion.

## Cách hoạt động

```text
   Vùng màn hình bạn chọn
            │
            ▼
   ScreenCaptureKit          bắt hình liên tục
            │
            ▼
   ChangeDetector            chỉ chạy tiếp khi chữ đổi
            │
            ▼
   Vision OCR                nhận diện tiếng Việt có dấu
            │
            ▼
   TextGate                  chuẩn hoá, lọc trùng
            │
            ▼
   SpeechQueue               FIFO, không bỏ câu
            │
            ▼
   Giọng hệ thống / Kokoro ──▶ loa
```

`ChangeDetector` chỉ cho OCR chạy khi chữ ký độ sáng của vùng phụ đề thay đổi. Nhờ vậy app không đốt CPU nhận diện đi nhận diện lại cùng một câu, và cũng không đọc lặp.

## Giọng đọc

### Hệ thống

`AVSpeechSynthesizer` với giọng Linh (`vi-VN`). Độ trễ khoảng 50 ms nên bám sát được phụ đề realtime. Có sẵn trên macOS, không phải tải gì.

Máy chưa có giọng Việt thì vào `System Settings → Accessibility → Spoken Content → System Voice`.

### Kokoro

Model neural [Kokoro-Vietnamese](https://github.com/iamdinhthuan/Kokoro-Vietnamese) chạy qua ONNX Runtime với 14 voice pack. Tổng hợp khoảng 1 tới 1,6 giây mỗi câu.

Cài ngay trong app: Voice Studio, hoặc `Cài đặt → Chẩn đoán → Kokoro → Tải giọng Kokoro`.

Gói nặng 680 MB vì đã gồm sẵn một bản Python relocatable, nên máy bạn không cần cài Python. App đối chiếu SHA-256 trước khi cài. Cài xong thì 14 giọng xuất hiện ngay, không phải khởi động lại. Trong lúc tải app vẫn dùng bình thường, và thoát giữa chừng thì lần sau tải tiếp.

Năm mức tốc độ ánh xạ sang dải 0,65× tới 1,55×. Thay đổi có hiệu lực từ câu kế tiếp.

## Phím tắt

| Phím | Hành động |
| --- | --- |
| <kbd>⌥</kbd> <kbd>⌘</kbd> <kbd>V</kbd> | Bật hoặc tắt đọc |
| <kbd>⌥</kbd> <kbd>⌘</kbd> <kbd>R</kbd> | Chọn lại vùng phụ đề |
| <kbd>⌘</kbd> <kbd>Q</kbd> | Thoát hẳn |

Đóng cửa sổ không làm SubVoice dừng. App tiếp tục chạy trên menu bar và câu đang đọc không bị ngắt. Bấm Dock icon hoặc mục Mở SubVoice trên menu bar để hiện lại cửa sổ.

## Quyền riêng tư

Toàn bộ pipeline chạy trên máy bạn. Không có API phân tích, không quảng cáo, không đồng bộ đám mây.

- ScreenCaptureKit chỉ lấy đúng vùng bạn khoanh, không lấy cả màn hình.
- Vision nhận diện chữ cục bộ.
- Linh và Kokoro đều tổng hợp giọng offline.
- Lịch sử phiên chỉ nằm trong bộ nhớ tiến trình, tối đa 200 câu, biến mất khi thoát app. Nó không được ghi vào `UserDefaults` hay bất kỳ file log nào.

SubVoice không cần quyền Microphone, Accessibility hay Input Monitoring.

## Yêu cầu

- macOS 14 trở lên
- Apple Silicon. Giọng Kokoro chỉ có bản arm64; máy Intel vẫn dùng được giọng hệ thống.
- Quyền Screen Recording
- Giọng tiếng Việt của macOS nếu dùng bộ đọc hệ thống

## Build từ nguồn

```bash
git clone https://github.com/hoanganhuynh/subvoice.git
cd subvoice
./Scripts/bundle.sh release
open ~/Applications/SubVoice.app
```

> [!NOTE]
> Script cài vào `~/Applications/SubVoice.app`. Giữ đường dẫn và chữ ký ổn định giúp macOS không hỏi lại quyền Screen Recording sau mỗi lần build. Đặt `SUBVOICE_SIGN_IDENTITY` để dùng chứng chỉ của bạn.

### Đóng gói lại Kokoro

Dành cho người bảo trì.

```bash
./Scripts/package-kokoro.sh 1.0.0
```

Script dựng CPython relocatable, cài dependency bằng `pip install --target` chứ không dùng venv, tải model, convert voicepack sang `.npy`, rồi cắt bỏ stack PyTorch. Trước khi nén nó chạy self-test dưới `env -i`; self-test hỏng thì archive không được tạo ra.

Nó in ra `SHA256` và `SIZE`. Dán hai giá trị đó vào `KokoroPackage.current` rồi attach archive vào GitHub Release trùng tag.

## Kiến trúc

```text
Sources/
├── SubVoiceApp/      # Vòng đời AppKit: cửa sổ, menu bar, capture, OCR, TTS, installer
├── SubVoiceUI/       # State trình bày và toàn bộ view SwiftUI
├── SubVoiceCore/     # Detector, lọc văn bản, hàng đợi, lịch sử, cài đặt, gói Kokoro
└── SubVoiceProbe/    # Công cụ đo OCR/capture

Scripts/
├── bundle.sh         # Build, ký và cài SubVoice.app
├── package-kokoro.sh # Đóng gói runtime Kokoro
├── smoke-overlay.sh  # Vòng đời overlay chọn vùng, chạy dưới NSZombie
├── smoke-window.sh   # Vòng đời cửa sổ chính
└── trace.sh          # Đọc trace chẩn đoán
```

`AppCoordinator` sở hữu mọi dịch vụ đang chạy và là nơi duy nhất tạo ra ảnh chụp trạng thái. Cửa sổ SwiftUI và menu bar cùng đọc một `AppViewState` và chỉ gửi `AppIntent` ngược lại, nên hai nơi không thể hiển thị lệch nhau.

Logic đáng test nằm ở `SubVoiceCore` và `SubVoiceUI`, đều là value type thuần. `SubVoiceApp` chỉ giữ phần chạm hệ thống.

## Kiểm thử

```bash
swift test                  # 119 test, 11 suite
./Scripts/smoke-overlay.sh  # overlay dưới NSZombie
./Scripts/smoke-window.sh   # vòng đời cửa sổ
```

Bật trace khi cần tìm câu bị bỏ qua:

```bash
open ~/Applications/SubVoice.app --args --trace
./Scripts/trace.sh 100
```

## Giới hạn đã biết

- Chỉ đọc chữ đang hiển thị trong vùng bạn đã chọn.
- Nội dung DRM như Netflix hay Apple TV+ bị macOS chặn khỏi Screen Recording nên không đọc được. Phụ đề dạng lớp HTML bên ngoài khung video thì vẫn đọc bình thường.
- Kokoro nghe tự nhiên hơn nhưng chậm hơn đáng kể so với giọng hệ thống.
- Gói Kokoro chỉ có bản Apple Silicon.
- Hiện tập trung vào tiếng Việt và macOS.

## Ghi nhận

- [Kokoro-Vietnamese](https://github.com/iamdinhthuan/Kokoro-Vietnamese), model và frontend tiếng Việt, giấy phép Apache-2.0
- [contextboxai/Kokoro-Vietnamese](https://huggingface.co/contextboxai/Kokoro-Vietnamese), ONNX model và voice packs
- [python-build-standalone](https://github.com/astral-sh/python-build-standalone), bản CPython relocatable trong gói runtime
- Apple Vision, ScreenCaptureKit và AVFoundation

---

<div align="center">

Made by Anthony with ⌨️

</div>
