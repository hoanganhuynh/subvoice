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
    /// Cửa sổ đã sinh ra vùng này. `nil` với vùng lưu từ bản cũ, hoặc khi
    /// khoanh lên desktop — lúc đó app đọc liên tục như trước.
    ///
    /// `Codable` tự sinh dùng `decodeIfPresent` cho thuộc tính Optional, nên
    /// JSON cũ thiếu khoá này vẫn giải mã được.
    public var owner: RegionOwner?

    public init(
        displayID: UInt32,
        rect: CGRect,
        scale: CGFloat,
        owner: RegionOwner? = nil
    ) {
        self.displayID = displayID
        self.rect = rect
        self.scale = scale
        self.owner = owner
    }

    public var pixelWidth: Int { Int((rect.width * scale).rounded()) }
    public var pixelHeight: Int { Int((rect.height * scale).rounded()) }
}
