import Foundation

/// Giữ cả dòng trong lúc phụ đề hiện dần. Dịch phần đuôi riêng lẻ sẽ mất
/// ngữ cảnh, nên buffer này độc lập với TextGate của chế độ đọc trực tiếp.
public struct SubtitleTextBuffer {
    private var candidate: String?
    private var delivered: String?

    public init() {}

    public mutating func submit(_ raw: String) -> [String] {
        guard let text = TextGate.normalize(raw) else { return [] }
        if text == candidate || text == delivered { return [] }
        if let candidate, candidate.contains(text) { return [] }
        if let delivered, delivered.contains(text) { return [] }
        if let delivered, TextGate.similarity(text, delivered) >= TextGate.similarityThreshold {
            return []
        }
        var ready: [String] = []
        if let candidate, let joined = Self.joinOverlapping(candidate, text) {
            self.candidate = joined
            return []
        }
        if let candidate,
           !text.contains(candidate),
           TextGate.similarity(text, candidate) < TextGate.similarityThreshold,
           let previous = flush() {
            ready.append(previous)
        }
        candidate = text
        return ready
    }

    public mutating func flush() -> String? {
        guard let text = candidate else { return nil }
        candidate = nil
        guard text != delivered else { return nil }
        delivered = text
        return text
    }

    public mutating func endSubtitle() -> String? {
        let final = flush()
        delivered = nil
        return final
    }

    public mutating func reset() {
        candidate = nil
        delivered = nil
    }

    private static func joinOverlapping(_ lhs: String, _ rhs: String) -> String? {
        let left = lhs.split(separator: " "), right = rhs.split(separator: " ")
        guard !left.isEmpty, !right.isEmpty else { return nil }
        for length in stride(from: min(left.count, right.count), through: 1, by: -1) {
            if !".!?".contains(lhs.last ?? " "), left.suffix(length).elementsEqual(right.prefix(length)) {
                return (left + right.dropFirst(length)).joined(separator: " ")
            }
            if !".!?".contains(rhs.last ?? " "), right.suffix(length).elementsEqual(left.prefix(length)) {
                return (right + left.dropFirst(length)).joined(separator: " ")
            }
        }
        return nil
    }
}
