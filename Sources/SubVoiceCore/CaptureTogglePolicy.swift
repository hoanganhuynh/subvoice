import Foundation

/// Phân biệt một lần đọc thử với việc bắt phụ đề thật. Cả hai đều hiển thị
/// trạng thái "đang đọc", nhưng chỉ capture mới được phép khởi động OCR.
public enum CaptureToggleAction: Equatable, Sendable {
    case startCapture
    case stopCapture
    case stopPreview
}

public enum CaptureTogglePolicy {
    public static func action(
        isCaptureRunning: Bool,
        isPreviewing: Bool
    ) -> CaptureToggleAction {
        if isPreviewing { return .stopPreview }
        return isCaptureRunning ? .stopCapture : .startCapture
    }
}
