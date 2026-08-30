import Foundation

public enum GateResult: Equatable, Sendable {
    case drop
    case speak(String)
}

/// Quyết định chuỗi OCR nào đáng đọc thành tiếng.
///
/// Bốn quy tắc, áp dụng đúng thứ tự này:
///  1. Giống hệt câu trước            -> bỏ
///  2. Là phần mở rộng của câu trước  -> chỉ đọc phần đuôi (xử lý fade-in)
///  3. Giống >= 90% câu trước         -> bỏ, coi là nhiễu OCR của cùng câu
///  4. Còn lại                        -> đọc toàn bộ
public struct TextGate {
    /// Ngưỡng coi hai chuỗi là cùng một câu phụ đề.
    public static let similarityThreshold = 0.90

    private static let noiseTokens: Set<String> = ["|", "—", "–", "-", "_", "·", "•"]

    private var lastSpoken: String?

    public init() {}

    /// Xoá trạng thái. Gọi khi `ChangeDetector` báo `.blank`, để một câu thoại
    /// lặp lại y hệt ở cảnh sau vẫn được đọc chứ không bị quy tắc 1 nuốt mất.
    public mutating func clear() {
        lastSpoken = nil
    }

    public mutating func admit(_ raw: String) -> GateResult {
        guard let text = TextGate.normalize(raw) else { return .drop }

        guard let last = lastSpoken else {
            lastSpoken = text
            return .speak(text)
        }

        if text == last { return .drop }

        if text.hasPrefix(last) {
            let suffix = String(text.dropFirst(last.count))
                .trimmingCharacters(in: .whitespaces)
            lastSpoken = text
            return suffix.isEmpty ? .drop : .speak(suffix)
        }

        if TextGate.similarity(text, last) >= TextGate.similarityThreshold {
            return .drop
        }

        lastSpoken = text
        return .speak(text)
    }

    /// Chuẩn hoá chuỗi OCR. Trả về nil nếu không đáng đọc.
    public static func normalize(_ raw: String) -> String? {
        let collapsed = raw
            .precomposedStringWithCanonicalMapping
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty && !noiseTokens.contains($0) }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)

        guard collapsed.count >= 2 else { return nil }
        guard collapsed.contains(where: { $0.isLetter }) else { return nil }
        return collapsed
    }

    /// Khoảng cách Levenshtein chuẩn hoá về dải 0...1, 1 là giống hệt.
    public static func similarity(_ a: String, _ b: String) -> Double {
        let lhs = Array(a)
        let rhs = Array(b)
        let longest = max(lhs.count, rhs.count)
        guard longest > 0 else { return 1 }
        return 1 - Double(levenshtein(lhs, rhs)) / Double(longest)
    }

    static func levenshtein(_ a: [Character], _ b: [Character]) -> Int {
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }

        var previous = Array(0...b.count)
        var current = [Int](repeating: 0, count: b.count + 1)

        for i in 1...a.count {
            current[0] = i
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
            }
            swap(&previous, &current)
        }
        return previous[b.count]
    }
}
