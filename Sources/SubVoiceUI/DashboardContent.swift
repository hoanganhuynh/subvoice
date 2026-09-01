import Foundation

/// Chữ hiển thị ở khu vực trung tâm, suy ra hoàn toàn từ trạng thái chạy.
///
/// Tách khỏi view để test được: sai một nhãn ở đây là người dùng đọc nhầm
/// trạng thái, mà loại lỗi đó không lộ ra trong ảnh chụp giao diện.
public struct DashboardContent: Equatable, Sendable {
    public let title: String
    public let detail: String
    public let primaryActionTitle: String
    public let symbolName: String
    /// Nhãn nút khắc phục; chỉ có khi đang ở trạng thái cảnh báo.
    public let recoveryTitle: String?
    public let recoveryAction: RecoveryAction?

    public init(runState: AppRunState) {
        switch runState {
        case .stopped:
            title = "Nghe phụ đề. Không rời mắt."
            detail = "Sẵn sàng khi bạn sẵn sàng."
            primaryActionTitle = "Bắt đầu đọc"
            symbolName = "speaker.wave.2"
            recoveryTitle = nil
            recoveryAction = nil
        case .listening:
            title = "SubVoice đang nghe"
            detail = "Đang theo dõi vùng phụ đề đã chọn."
            primaryActionTitle = "Dừng đọc"
            symbolName = "waveform"
            recoveryTitle = nil
            recoveryAction = nil
        case .speaking:
            title = "Đang đọc phụ đề"
            detail = "Câu mới đã được đưa tới loa."
            primaryActionTitle = "Dừng đọc"
            symbolName = "waveform.circle.fill"
            recoveryTitle = nil
            recoveryAction = nil
        case .warning(let warning):
            title = "SubVoice cần bạn hỗ trợ"
            detail = warning.message
            primaryActionTitle = "Bắt đầu đọc"
            symbolName = "exclamationmark.triangle.fill"
            recoveryTitle = Self.label(for: warning.recovery)
            recoveryAction = warning.recovery ?? .retry
        }
    }

    private static func label(for recovery: RecoveryAction?) -> String {
        switch recovery {
        case .openScreenRecordingSettings: "Mở System Settings"
        case .openSpokenContentSettings: "Mở Spoken Content"
        case .retry, .none: "Thử lại"
        }
    }
}
