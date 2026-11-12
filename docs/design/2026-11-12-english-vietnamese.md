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

## Ghép đủ câu trước khi dịch

Không coi timeout hoặc khung trống là dấu kết câu. Giữ mệnh đề còn thiếu (như `I was going to`, `I think that you`) qua nhiều cue; ghép với phần tiếp theo, cập nhật khung chữ hiện dần và chỉ đẩy phần đủ ý. Nếu một cue có câu hoàn chỉnh rồi tới đoạn dở, đọc câu trước và giữ đoạn dở.

Câu có dấu kết thúc chờ ổn định 350 ms. Câu không có dấu câu chờ 1,8 giây rồi xét các quy tắc thận trọng; mệnh đề phụ, từ nối, giới từ hoặc bổ ngữ còn thiếu vẫn được giữ. Có ngoại lệ cho phản hồi ngắn, câu hỏi và mệnh đề chính đã đủ. Quy tắc này là suy đoán theo văn bản, không cam kết phân tích hoàn hảo mọi câu tiếng Anh.

Chuẩn hoá khoảng trắng trước dấu câu để không đọc lặp khi OCR đổi cách viết; không dùng ngưỡng giống nhau 90% để bỏ câu đã đọc vì có thể làm mất câu đổi số hoặc đổi nghĩa. Giữ đủ hàng đợi phát tiếng Việt từ bản dịch; chế độ đọc tiếng Việt trực tiếp giữ chính sách bắt kịp cũ. Đổi vùng/dừng/tạm dừng vì cửa sổ nguồn bị che vẫn huỷ nội dung đang chờ như trước.

Đã kiểm tra 213 tests với cả hai bài dịch Apple thật được bật. Chuỗi ghép `I was going to` + `tell you something.` đến Apple dưới đúng một yêu cầu và trả về `Tôi đã định nói với bạn điều gì đó.`. Có regression cho dấu ba chấm, câu rút ngắn/hiện dần, No/No. 5, số thập phân, khoảng trắng trước dấu câu, mệnh đề that, câu hỏi và hàng đợi phát chậm.
