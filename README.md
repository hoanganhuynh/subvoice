<div align="center">

# SubVoice

### Đọc phụ đề tiếng Việt trên màn hình thành giọng nói — riêng tư, offline, dành cho macOS

[![macOS 14+](https://img.shields.io/badge/macOS-14%2B-111111?logo=apple&logoColor=white)](https://support.apple.com/macos)
[![Swift 6](https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white)](https://www.swift.org/)
[![Offline](https://img.shields.io/badge/xử_lý-100%25_offline-2ea44f)](#quyền-riêng-tư)
[![Swift Testing](https://img.shields.io/badge/tests-Swift_Testing-6f42c1)](#kiểm-thử)

Chọn một vùng phụ đề trên màn hình. SubVoice nhận diện chữ tiếng Việt, lọc câu trùng và đọc thành tiếng ngay từ menu bar.

</div>

---

## Điểm nổi bật

- **Chạy gọn trên menu bar** — không chiếm Dock, không cần cửa sổ chính.
- **OCR tiếng Việt có dấu** bằng Vision, được hâm nóng để giảm độ trễ câu đầu.
- **Hai bộ đọc offline:** giọng hệ thống nhanh và Kokoro tự nhiên với 14 giọng Việt.
- **Không đọc lặp** khi phụ đề đứng yên; xử lý được phụ đề xuất hiện kiểu fade-in.
- **Không bỏ câu đã nhận diện** — hàng đợi FIFO giữ đúng thứ tự hội thoại.
- **Điều chỉnh được** giọng, tốc độ và âm lượng ngay trong menu.
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

1. Mở biểu tượng SubVoice trên menu bar.
2. Chọn **Chọn lại vùng…**, rồi kéo quanh khu vực hiển thị phụ đề.
3. Chọn **Bật đọc**.
4. Chọn bộ đọc, giọng, tốc độ và âm lượng phù hợp.

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

Kokoro cần khoảng **1,3 GB** cho runtime và model. Các tệp này không được commit vào repo.

#### Chuẩn bị Kokoro

```bash
git clone https://github.com/iamdinhthuan/Kokoro-Vietnamese.git \
  ThirdParty/Kokoro-Vietnamese

python3 -m venv ThirdParty/Kokoro-Vietnamese/.venv
ThirdParty/Kokoro-Vietnamese/.venv/bin/pip install \
  -e "ThirdParty/Kokoro-Vietnamese[onnx]"

ThirdParty/Kokoro-Vietnamese/.venv/bin/hf download \
  contextboxai/Kokoro-Vietnamese \
  --local-dir ThirdParty/Kokoro-Vietnamese/models
```

Sau đó đóng gói app kèm runtime Kokoro:

```bash
SUBVOICE_INCLUDE_KOKORO=1 ./Scripts/bundle.sh release
```

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
- SubVoice không có API phân tích, quảng cáo hoặc đồng bộ đám mây.

## Kiến trúc dự án

```text
Sources/
├── SubVoiceApp/      # Menu bar, capture, OCR, TTS và điều phối
├── SubVoiceCore/     # Detector, lọc văn bản, hàng đợi và cài đặt
└── SubVoiceProbe/    # Công cụ đo OCR/capture

Resources/
└── kokoro_service.py # Sidecar JSON-lines thường trú

Scripts/
├── bundle.sh         # Build, ký và cài SubVoice.app
├── smoke-overlay.sh  # Kiểm tra vòng đời overlay
└── trace.sh          # Đọc trace chẩn đoán

Tests/
└── SubVoiceCoreTests/
```


## Kiểm thử

Chạy toàn bộ unit test và performance test:

```bash
swift test
```

Kiểm tra overlay chọn vùng dưới NSZombie:

```bash
./Scripts/smoke-overlay.sh
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
