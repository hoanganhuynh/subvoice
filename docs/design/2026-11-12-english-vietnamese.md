# Đọc phụ đề Anh bằng tiếng Việt

SubVoice nhận chữ tiếng Anh trong vùng màn hình đã chọn, dịch sang tiếng Việt rồi phát bằng giọng System/Kokoro đang chọn. Không thêm lớp phụ đề nổi hay nhận dạng âm thanh.

- Giữ chế độ đọc tiếng Việt làm mặc định, tương thích cài đặt cũ và macOS 14.
- Chế độ Anh → Việt dùng Apple Translation trên macOS 15+, kiểm tra cặp ngôn ngữ trên thiết bị. Tải gói ngôn ngữ qua giao diện hệ thống khi người dùng yêu cầu, sau đó dịch trên máy, không API key.
- OCR tiếng Anh khi dịch. Ghép chữ đang hiện dần trước khi dịch cả câu, không dịch riêng phần đuôi của TextGate.
- Dịch tuần tự, giữ thứ tự câu. Dừng/đổi vùng/đổi chế độ/hide cửa sổ nguồn phải loại kết quả cũ. Khi dịch lỗi, báo lỗi và dừng phiên; không đọc tiếng Anh như tiếng Việt.
- Lịch sử chỉ ở RAM, có câu gốc cùng bản dịch, tìm kiếm cả hai; copy lấy bản tiếng Việt.
- Chọn chế độ và chuẩn bị ngôn ngữ trong Voice Studio; menu bar phản ánh chế độ. Giữ nguyên giọng, tốc độ và âm lượng.
- Giữ session Apple trong vòng đời view trên macOS 15; dùng session độc lập khi ngôn ngữ đã cài trên macOS 26 để tiếp tục khi cửa sổ chính ẩn.
- Kiểm thử buffer, settings migration, thứ tự dịch, cancellation và lỗi bằng adapter bất đồng bộ có kiểm soát. Xác minh build Universal và native translation khi gói ngôn ngữ có sẵn.
