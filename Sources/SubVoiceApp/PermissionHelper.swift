import AppKit
import CoreGraphics

enum PermissionHelper {
    /// Kiểm tra không hiện hộp thoại.
    static var hasScreenRecordingAccess: Bool {
        CGPreflightScreenCaptureAccess()
    }

    /// Kích hoạt hộp thoại xin quyền của hệ thống. Chỉ hiện được một lần cho
    /// mỗi bản app; sau đó người dùng phải tự bật trong System Settings.
    @discardableResult
    static func requestScreenRecordingAccess() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    static func openScreenRecordingSettings() {
        let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        )!
        NSWorkspace.shared.open(url)
    }
}
