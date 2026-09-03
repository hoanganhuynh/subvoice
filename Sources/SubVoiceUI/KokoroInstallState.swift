import Foundation

/// Tiến trình cài Kokoro. Onboarding, Voice Studio và Settings cùng đọc giá trị
/// này, nên không có nơi nào tự đếm tiến trình riêng.
public enum KokoroInstallState: Equatable, Sendable {
    case notInstalled
    case downloading(received: Int64, total: Int64)
    case verifying
    case extracting
    case finishing
    case installed(version: String)
    case failed(message: String)

    public var isBusy: Bool {
        switch self {
        case .downloading, .verifying, .extracting, .finishing:
            return true
        case .notInstalled, .installed, .failed:
            return false
        }
    }

    /// Phần trăm CHỈ có ý nghĩa khi `isBusy` đúng. Các trạng thái kết thúc cũng
    /// trả `nil` dù chúng xác định rõ 0% hay 100%, nên đừng vẽ thanh tiến trình
    /// mà không kiểm tra `isBusy` trước.
    ///
    /// `nil` lúc đang bận nghĩa là không đo được — thanh phải chạy indeterminate
    /// chứ không đứng im ở 0%.
    public var progress: Double? {
        // URLSession báo tổng chưa biết bằng -1, không phải 0.
        guard case .downloading(let received, let total) = self, total > 0 else {
            return nil
        }
        // Tải tiếp phần dở có thể cộng dồn quá tổng, và Content-Length qua
        // redirect đôi khi báo thiếu.
        return min(max(0, Double(received) / Double(total)), 1)
    }

    public var statusText: String {
        switch self {
        case .notInstalled:
            return "Chưa cài"
        case .downloading(let received, let total):
            return Self.byteProgressText(received: received, total: total)
        case .verifying:
            return "Đang kiểm tra gói tải về…"
        case .extracting:
            return "Đang giải nén…"
        case .finishing:
            return "Đang hoàn tất…"
        case .installed(let version):
            return "Đã cài bản \(version)"
        case .failed(let message):
            // Lỗi mạng đến từ URLError với mô tả tiếng Anh của hệ thống, nên
            // câu dẫn phải do kiểu này bảo đảm chứ không phó mặc chỗ gọi.
            return "Cài Kokoro thất bại: \(message)"
        }
    }

    private static func byteProgressText(received: Int64, total: Int64) -> String {
        let formatter = ByteCountFormatter()
        // Mặc định formatter trả "Zero KB" — tiếng Anh, trong giao diện thuần
        // Việt, và đúng vào giây đầu tiên của mỗi lần tải.
        formatter.allowsNonnumericFormatting = false
        guard total > 0 else {
            return "Đang tải \(formatter.string(fromByteCount: received))…"
        }
        return "Đang tải \(formatter.string(fromByteCount: received))"
            + " / \(formatter.string(fromByteCount: total))"
    }
}
