import CoreGraphics

/// Một dòng chữ Vision nhận được, đã tách khỏi kiểu dữ liệu của Vision
/// để phần ghép nối test được mà không cần chạy OCR thật.
public struct OCRLine: Equatable, Sendable {
    public var text: String
    public var confidence: Float
    /// Tâm theo trục dọc trong hộp bao đã chuẩn hoá của Vision (gốc DƯỚI-trái).
    public var midY: CGFloat
    /// Cạnh trái trong hộp bao đã chuẩn hoá của Vision.
    public var minX: CGFloat

    public init(text: String, confidence: Float, midY: CGFloat, minX: CGFloat) {
        self.text = text
        self.confidence = confidence
        self.midY = midY
        self.minX = minX
    }
}

public enum OCRAssembler {
    public static let minimumConfidence: Float = 0.30
    /// Chênh lệch midY nhỏ hơn mức này thì coi là cùng một dòng.
    public static let sameLineTolerance: CGFloat = 0.02

    public static func assemble(_ lines: [OCRLine]) -> String {
        lines
            .filter { $0.confidence >= minimumConfidence }
            .sorted { lhs, rhs in
                if abs(lhs.midY - rhs.midY) > sameLineTolerance {
                    return lhs.midY > rhs.midY   // midY lớn hơn = cao hơn = đọc trước
                }
                return lhs.minX < rhs.minX
            }
            .map(\.text)
            .joined(separator: " ")
    }
}
