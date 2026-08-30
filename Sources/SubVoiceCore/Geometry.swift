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

    /// Cắt vùng cho nằm gọn trong display. Trả về nil nếu phần còn lại quá nhỏ để dùng.
    public static func clamped(_ rect: CGRect, toDisplaySize size: CGSize) -> CGRect? {
        let bounds = CGRect(origin: .zero, size: size)
        let result = rect.intersection(bounds)
        guard !result.isNull, result.width >= 8, result.height >= 8 else { return nil }
        return result
    }
}
