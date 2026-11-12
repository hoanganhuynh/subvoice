import Foundation

/// Phiên nội dung độc lập với vòng đời stream. Tạm dừng rồi tiếp tục vẫn giữ
/// stream, nhưng kết quả OCR của nội dung trước lúc dừng không còn hợp lệ.
public struct OCRDeliverySession {
    private var token: UUID?
    public init() {}
    public mutating func begin() -> UUID {
        let next = UUID()
        token = next
        return next
    }
    public mutating func invalidate() { token = nil }
    public func accepts(_ candidate: UUID) -> Bool { token == candidate }
}
