/// Quyết định có tiếp tục bắt màn hình sau khi người dùng chọn vùng hay không.
///
/// Việc chọn vùng thủ công chỉ là cấu hình; nó không được phép tự bật đọc.
/// Chỉ lời gọi từ nút Bắt đầu khi chưa có vùng, hoặc capture đang chạy trước
/// đó, mới cần quay lại capture sau khi overlay đóng.
public enum RegionSelectionPolicy {
    public static func shouldResumeCapture(
        captureWasRunning: Bool,
        initiatedByStart: Bool
    ) -> Bool {
        captureWasRunning || initiatedByStart
    }
}
