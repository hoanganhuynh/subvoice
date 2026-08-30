import CoreGraphics
import Foundation

/// Vùng màn hình người dùng đã chọn.
///
/// `rect` đã ở hệ toạ độ CỤC BỘ của display, gốc TRÊN-TRÁI, đơn vị point —
/// đúng dạng `SCStreamConfiguration.sourceRect` yêu cầu.
public struct SelectedRegion: Codable, Equatable, Sendable {
    public var displayID: UInt32
    public var rect: CGRect
    public var scale: CGFloat

    public init(displayID: UInt32, rect: CGRect, scale: CGFloat) {
        self.displayID = displayID
        self.rect = rect
        self.scale = scale
    }

    public var pixelWidth: Int { Int((rect.width * scale).rounded()) }
    public var pixelHeight: Int { Int((rect.height * scale).rounded()) }
}
