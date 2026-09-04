# SubVoice Desktop App UI

Ngày chốt thiết kế: 2026-09-01

Trạng thái: Đã duyệt

## Mục tiêu

Chuyển SubVoice từ ứng dụng chỉ điều khiển qua menu bar thành ứng dụng macOS có Dock icon và cửa sổ chính, đồng thời giữ menu bar cho các thao tác nhanh. Cửa sổ mới phải thể hiện rõ trạng thái đọc, gom các thiết lập hiện có vào một trải nghiệm dễ dùng và bổ sung những tiện ích có giá trị cao mà không làm thay đổi pipeline capture, OCR và speech đang ổn định.

Giao diện dùng hướng mỹ thuật **Cinematic Aurora** với bố cục **Focus First**. Trạng thái và thao tác bật/tắt là trọng tâm; những thiết lập chi tiết được mở khi người dùng cần.

## Phạm vi bản đầu

Bản đầu bao gồm:

- Cửa sổ chính SwiftUI chạy trong vòng đời AppKit hiện tại.
- Dock icon, menu ứng dụng chuẩn và menu bar điều khiển nhanh.
- Trạng thái dừng, đang nghe, đang đọc và cảnh báo.
- Chọn lại vùng phụ đề.
- Chọn System hoặc Kokoro, chọn voice, tốc độ và âm lượng.
- Thử giọng khi SubVoice đang dừng.
- Hiển thị câu vừa được đưa vào hàng đợi đọc.
- Lịch sử chỉ trong phiên, có tìm kiếm và sao chép.
- Kiểm tra quyền Screen Recording và tình trạng Kokoro.
- Tuỳ chọn theme System, Light và Dark.
- Tuỳ chọn khởi động cùng máy.
- Credit `Made by Anthony with ⌨️` ở footer và màn hình About.

Không nằm trong phạm vi bản đầu:

- Lưu transcript xuống ổ đĩa hoặc đồng bộ đám mây.
- Dịch phụ đề.
- Nhiều vùng đọc hoặc preset theo từng ứng dụng.
- Thay đổi thuật toán detector, OCR, TextGate hoặc SpeechQueue.
- Viết lại overlay chọn vùng, global hotkey hoặc speech backend.

## Quyết định sản phẩm

### Vòng đời ứng dụng

- SubVoice dùng activation policy `.regular` và xuất hiện trong Dock.
- Cửa sổ chính mở khi khởi động.
- Mỗi lần khởi động, SubVoice luôn ở trạng thái dừng. App không tự đọc dù đã có vùng được lưu.
- Đóng cửa sổ chỉ ẩn cửa sổ. Nếu SubVoice đang đọc, pipeline tiếp tục hoạt động.
- Bấm Dock hoặc mục **Mở SubVoice** trên menu bar sẽ hiện lại cửa sổ.
- `⌘Q` mới thoát hoàn toàn.
- `⌥⌘V` tiếp tục bật hoặc tắt đọc; `⌥⌘R` tiếp tục chọn lại vùng.

### Quyền riêng tư

- Lịch sử transcript chỉ nằm trong bộ nhớ của tiến trình.
- Lịch sử bị xoá khi thoát app và không được mã hoá vào `UserDefaults`.
- Danh sách giữ tối đa 200 câu để bộ nhớ không tăng vô hạn.
- Chỉ câu đã qua `TextGate` và được đưa vào `SpeechQueue` mới xuất hiện trong lịch sử.
- Ảnh màn hình, OCR và speech tiếp tục được xử lý cục bộ.

## Kiến trúc

### Nguồn trạng thái duy nhất

`AppCoordinator` tiếp tục sở hữu toàn bộ dịch vụ đang chạy:

- `ScreenCapturer`
- `OCREngine`
- `TextGate`
- `SpeechQueue`
- `SystemSpeechBackend`
- `KokoroSpeechBackend`
- `RegionSelector`
- `HotKeyManager`

Một `AppViewModel` mới chạy trên main actor và phát `AppViewState` cho giao diện. `MainWindowController` và `MenuBarController` không tự giữ trạng thái sản phẩm riêng; cả hai đọc state và gửi lệnh về coordinator.

Các nhóm dữ liệu chính của `AppViewState`:

- Trạng thái chạy: stopped, listening, speaking hoặc warning.
- Nội dung cảnh báo và hành động khắc phục nếu có.
- Vùng đọc hiện tại và mô tả ngắn cho UI.
- Engine, danh sách voice, voice đã chọn, tốc độ và âm lượng.
- Câu mới nhất và danh sách lịch sử phiên.
- Quyền Screen Recording, System voice và tình trạng Kokoro.
- Theme và trạng thái khởi động cùng máy.

### Cửa sổ chính

`MainWindowController` tạo `NSWindow` và đặt một `NSHostingController` chứa SwiftUI root view. Cách này giữ lifecycle AppKit phù hợp với status item, overlay và global hotkey, đồng thời dùng SwiftUI cho layout, animation, binding và accessibility.

Cửa sổ mặc định 820 × 620 điểm và có kích thước tối thiểu 720 × 540 điểm để control dock không bị vỡ. Vị trí và kích thước cửa sổ được macOS khôi phục an toàn, nhưng app không khôi phục trạng thái đang đọc.

### Luồng lệnh

SwiftUI gửi intent về view model; view model chuyển intent sang coordinator. Các intent gồm:

- Bật hoặc tắt đọc.
- Chọn lại vùng.
- Đổi engine, voice, tốc độ hoặc âm lượng.
- Thử giọng.
- Mở phần cài đặt hoặc hướng dẫn cấp quyền.
- Xoá, tìm kiếm hoặc sao chép lịch sử phiên.
- Đổi theme và khởi động cùng máy.

Coordinator cập nhật state sau khi lệnh thành công hoặc thất bại. Menu bar và cửa sổ nhận cùng một state nên luôn hiển thị thống nhất.

### Luồng transcript

Luồng capture hiện tại không thay đổi:

`ScreenCaptureKit → ChangeDetector → Vision OCR → TextGate → SpeechQueue → Speech backend`

Khi `TextGate` chấp nhận một câu, coordinator thêm câu đó vào hàng đợi đọc và lịch sử phiên trên main actor. Câu được gắn thời gian và định danh ổn định để SwiftUI cập nhật danh sách mà không tạo lại toàn bộ view.

## Trải nghiệm giao diện

### Dashboard Focus First

Thanh trên cùng chứa:

- Icon và tên SubVoice.
- Nhãn trạng thái có cả biểu tượng và chữ.
- Nút mở Cài đặt.

Khu vực trung tâm chứa:

- Status orb tím–cyan.
- Tiêu đề và mô tả thay đổi theo trạng thái.
- Nút chính **Bắt đầu đọc** hoặc **Dừng đọc**, kèm phím tắt `⌥⌘V`.

Control dock phía dưới có ba thẻ:

1. **Vùng đọc** — mô tả màn hình và kích thước vùng; kích hoạt overlay chọn lại vùng.
2. **Giọng đọc** — engine và voice hiện tại; mở Voice Studio.
3. **Vừa đọc** — câu mới nhất; mở drawer lịch sử phiên.

Footer hiển thị `Made by Anthony with ⌨️` với độ tương phản đủ đọc nhưng không cạnh tranh với thao tác chính.

### Voice Studio

Voice Studio cung cấp:

- Bộ chọn System hoặc Kokoro.
- Danh sách voice tương ứng với engine.
- Điều khiển tốc độ có nhãn dễ hiểu và giá trị phản ánh đúng mapping của backend.
- Điều khiển âm lượng.
- Nút **Thử giọng** với câu mẫu `Xin chào, đây là giọng đọc của SubVoice.`

Thử giọng chỉ khả dụng khi app đang dừng để không cắt ngang câu đang đọc. Thay đổi cấu hình có hiệu lực từ câu kế tiếp; câu đang tổng hợp hoặc phát giữ cấu hình cũ.

### Lịch sử phiên

Drawer lịch sử gồm:

- Tối đa 200 câu, mới nhất ở trên.
- Thời gian của từng câu.
- Tìm kiếm không phân biệt hoa thường.
- Sao chép một câu hoặc toàn bộ kết quả đang lọc.
- Nút xoá lịch sử phiên với xác nhận rõ ràng.

Trạng thái trống giải thích rằng lịch sử chỉ xuất hiện sau khi SubVoice đọc được câu đầu tiên và sẽ tự xoá khi thoát app.

### Cài đặt và chẩn đoán

Cài đặt gồm:

- Theme System, Light và Dark; mặc định là System.
- Khởi động cùng máy.
- Screen Recording với trạng thái và nút mở System Settings.
- System Vietnamese voice với hướng dẫn khi thiếu.
- Kokoro với trạng thái sẵn sàng hoặc lý do không khả dụng.
- About với phiên bản app, các ghi nhận hiện có và credit.

## Hệ thống hình ảnh

- Nền dùng near-black hoặc near-white có sắc lạnh; không dùng đen và trắng tuyệt đối.
- Tím là accent chính; cyan dành cho trạng thái đang nghe/đọc. Semantic warning và error dùng màu riêng nhưng luôn đi kèm icon và chữ.
- Gradient và glow chỉ dùng cho status orb, nút chính và một số brand moment.
- Typography dùng SF Pro và phân cấp tối đa ba cỡ chữ chính trên mỗi view.
- Spacing theo lưới 8 điểm; corner radius dùng hệ 8, 16 và 24 điểm.
- Theme System theo thay đổi appearance của macOS. Light và Dark là override có chủ ý.
- Theme chỉ đổi khi người dùng kích hoạt lựa chọn, không đổi khi hover hoặc focus.
- Animation ngắn, có mục đích và bị giảm hoặc tắt khi hệ thống bật Reduce Motion.

## Accessibility

- Mọi control dùng thành phần SwiftUI/AppKit native khi có thể.
- Toàn bộ chức năng dùng được bằng bàn phím, với focus order theo thứ tự đọc.
- Focus indicator phải rõ trong cả light và dark theme.
- Status không truyền đạt bằng màu đơn lẻ; luôn có icon, chữ và accessibility label.
- Icon trang trí bị ẩn khỏi accessibility tree; control chỉ có icon phải có label rõ nghĩa.
- Slider hỗ trợ phím mũi tên và đọc được giá trị hiện tại bằng VoiceOver.
- Drawer và sheet quản lý focus khi mở/đóng, hỗ trợ Escape và trả focus về control đã mở chúng.
- Nội dung đáp ứng WCAG 2.2 AA về tương phản chữ và thành phần giao diện.

## Xử lý lỗi

### Thiếu quyền Screen Recording

Hero chuyển sang warning state, giải thích ngắn gọn và cung cấp nút **Mở System Settings**. App không lặp lại system prompt hoặc giả vờ rằng quyền đã có hiệu lực trước khi khởi động lại.

### Chưa có vùng đọc

Bấm **Bắt đầu đọc** mở overlay chọn vùng. Nếu người dùng huỷ, app trở về stopped và không hiển thị lỗi.

### Kokoro không khả dụng

Kokoro bị vô hiệu hoá trong bộ chọn và UI hiển thị lý do. Nếu Kokoro lỗi trong lúc chạy, coordinator dừng backend đó, chuyển sang System, lưu engine mới và hiển thị banner không chặn thao tác.

### Capture hoặc OCR lỗi nghiêm trọng

Pipeline dừng an toàn, hàng đợi được làm sạch và hero chuyển sang warning state. Cửa sổ vẫn hoạt động để người dùng chọn lại vùng, cấp quyền hoặc thử bắt đầu lại.

## Lưu trữ

`Settings` tiếp tục được mã hoá vào `UserDefaults`. Bổ sung `ThemeMode` với ba giá trị hợp lệ: system, light và dark. Giá trị không hợp lệ hoặc thiếu được chuyển về system.

Vùng đọc tiếp tục dùng cơ chế lưu hiện tại. Transcript không được thêm vào `Settings`, `Store` hoặc bất kỳ file log mặc định nào.

## Kiểm thử

### Tự động

- Giữ toàn bộ unit test và performance test hiện tại.
- Kiểm thử chuyển trạng thái stopped, listening, speaking và warning.
- Kiểm thử giới hạn, thứ tự, tìm kiếm và xoá lịch sử phiên.
- Kiểm thử migration/default của ThemeMode.
- Kiểm thử intent thay đổi engine, voice, rate và volume cập nhật state đúng.
- Kiểm thử trạng thái Kokoro không khả dụng và fallback về System.
- Chạy `swift test` và overlay smoke test.

### Thủ công

- Cửa sổ mở khi launch và app luôn bắt đầu ở stopped.
- Dock, menu bar và cửa sổ hiển thị cùng trạng thái.
- Đóng cửa sổ không thoát app; Dock và menu bar mở lại được cửa sổ.
- Global hotkey hoạt động khi cửa sổ ẩn và khi app khác đang focus.
- Chọn vùng, huỷ chọn và chọn lại vùng hoạt động ổn định.
- System và Kokoro đọc được; đổi tốc độ Kokoro tạo khác biệt nghe thấy ở câu kế tiếp.
- Thử giọng không khả dụng khi đang chạy.
- Permission flow, fallback và banner lỗi có hành động đúng.
- Keyboard, VoiceOver, light/dark, Increase Contrast và Reduce Motion hoạt động đúng.
- Bundle release được build, ký, cài và mở thành công.

## Tài liệu và đóng gói

- `Info.plist` bỏ chế độ menu-bar-only.
- Script bundle tiếp tục đóng gói icon và Kokoro runtime như hiện tại.
- README được cập nhật cho desktop UI, luồng sử dụng mới và ảnh giao diện.
- Mô tả kiến trúc được cập nhật để phản ánh AppKit coordinator kết hợp SwiftUI window.

## Tiêu chí hoàn thành

- SubVoice có Dock icon, cửa sổ Focus First và menu bar hoạt động đồng thời.
- Mọi control hiện có trong menu bar đều có đường truy cập rõ trong cửa sổ.
- Dashboard, Voice Studio, lịch sử phiên, settings và diagnostics hoạt động theo đặc tả.
- Không có transcript nào được lưu sau khi thoát app.
- Pipeline capture/OCR/speech và hotkey hiện tại không bị regression.
- UI đạt yêu cầu keyboard, VoiceOver, contrast và Reduce Motion đã nêu.
- Test tự động, smoke test và bundle verification đều đạt.
- README và credit được cập nhật.

## Hướng phát triển sau bản đầu

- Lưu nhiều vùng đọc theo màn hình hoặc ứng dụng.
- Preset Phim, Anime và Bài giảng.
- Xuất transcript thủ công với lựa chọn định dạng.
- Tự chọn preset dựa trên ứng dụng đang phát video.
