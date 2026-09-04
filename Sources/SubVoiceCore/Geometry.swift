import CoreGraphics

/// Chuyển đổi giữa hệ toạ độ toàn cục của AppKit và hệ toạ độ cục bộ của display.
///
/// AppKit: gốc DƯỚI-TRÁI của màn hình chính, trục y hướng LÊN.
/// ScreenCaptureKit `sourceRect`: gốc TRÊN-TRÁI của chính display đó, trục y hướng XUỐNG.
public enum Geometry {

    /// - Parameters:
    ///   - globalRect: vùng trong hệ toạ độ toàn cục AppKit.
    ///   - displayFrame: `NSScreen.frame` của display chứa vùng đó, cùng hệ toạ độ.
    /// - Returns: vùng trong hệ toạ độ cục bộ của display, gốc trên-trái.
    public static func toDisplayLocalTopLeft(
        globalRect: CGRect,
        displayFrame: CGRect
    ) -> CGRect {
        CGRect(
            x: globalRect.minX - displayFrame.minX,
            y: displayFrame.maxY - globalRect.maxY,
            width: globalRect.width,
            height: globalRect.height
        )
    }

    /// Đường ngược cho việc đối chiếu với danh sách cửa sổ.
    ///
    /// - Parameters:
    ///   - displayLocalRect: vùng ở hệ cục bộ của display, gốc trên-trái —
    ///     đúng dạng `SelectedRegion.rect` đang lưu.
    ///   - displayBounds: `CGDisplayBounds` của chính display đó. Giá trị này
    ///     ĐÃ ở hệ toàn cục gốc trên-trái, cùng hệ mà `kCGWindowBounds` dùng,
    ///     nên phép chuyển chỉ là cộng gốc của display. Không đụng `NSScreen`,
    ///     không phải lật trục y.
    public static func toGlobalTopLeft(
        displayLocalRect: CGRect,
        displayBounds: CGRect
    ) -> CGRect {
        displayLocalRect.offsetBy(dx: displayBounds.minX, dy: displayBounds.minY)
    }

    /// Cắt vùng cho nằm gọn trong display. Trả về nil nếu phần còn lại quá nhỏ để dùng.
    public static func clamped(_ rect: CGRect, toDisplaySize size: CGSize) -> CGRect? {
        let bounds = CGRect(origin: .zero, size: size)
        let result = rect.intersection(bounds)
        guard !result.isNull, result.width >= 8, result.height >= 8 else { return nil }
        return result
    }
}
