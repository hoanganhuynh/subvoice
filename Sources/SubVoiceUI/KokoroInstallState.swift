import Foundation

/// Tiến trình cài Kokoro. Onboarding, Voice Studio và Settings cùng đọc giá trị
/// này, nên không có nơi nào tự đếm tiến trình riêng.
public enum KokoroInstallState: Equatable, Sendable {
    case notInstalled
    case downloading(received: Int64, total: Int64)
    case verifying
    case extracting
    case installed(version: String)
    case failed(message: String)

    public var isBusy: Bool {
        switch self {
        case .downloading, .verifying, .extracting: true
        case .notInstalled, .installed, .failed: false
        }
    }

    /// `nil` khi không xác định được phần trăm — thanh tiến trình phải chạy ở
    /// chế độ indeterminate chứ không đứng im ở 0%.
    public var progress: Double? {
        guard case .downloading(let received, let total) = self, total > 0 else {
            return nil
        }
        return Double(received) / Double(total)
    }

    public var statusText: String {
        switch self {
        case .notInstalled:
            "Chưa cài"
        case .downloading(let received, let total):
            Self.byteProgressText(received: received, total: total)
        case .verifying:
            "Đang kiểm tra gói tải về…"
        case .extracting:
            "Đang cài…"
        case .installed(let version):
            "Đã cài bản \(version)"
        case .failed(let message):
            message
        }
    }

    private static func byteProgressText(received: Int64, total: Int64) -> String {
        let formatter = ByteCountFormatter()
        guard total > 0 else {
            return "Đang tải \(formatter.string(fromByteCount: received))…"
        }
        return "Đang tải \(formatter.string(fromByteCount: received))"
            + " / \(formatter.string(fromByteCount: total))"
    }
}
