import CoreGraphics

/// Ảnh chụp một cửa sổ đang hiện trên màn hình.
///
/// Tách khỏi CoreGraphics window API để luật xét vùng đọc test được bằng dữ
/// liệu dựng tay. Danh sách truyền vào `RegionFocusPolicy` LUÔN xếp từ trước ra
/// sau, đúng thứ tự `CGWindowListCopyWindowInfo` trả về.
public struct WindowSnapshot: Equatable, Sendable {
    public var windowNumber: UInt32
    public var bundleIdentifier: String?
    public var applicationName: String?
    public var title: String?
    /// Hệ toạ độ toàn cục gốc TRÊN-TRÁI, đúng như `kCGWindowBounds` trả về.
    public var frame: CGRect
    /// 0 là cửa sổ thường. Thanh menu, Dock và các lớp hệ thống khác có layer
    /// lớn hơn, và không bao giờ được tính là che vùng đọc.
    public var layer: Int
    public var alpha: CGFloat

    public init(
        windowNumber: UInt32,
        bundleIdentifier: String?,
        applicationName: String?,
        title: String?,
        frame: CGRect,
        layer: Int,
        alpha: CGFloat
    ) {
        self.windowNumber = windowNumber
        self.bundleIdentifier = bundleIdentifier
        self.applicationName = applicationName
        self.title = title
        self.frame = frame
        self.layer = layer
        self.alpha = alpha
    }
}
