import Foundation

/// Giữ cả dòng trong lúc phụ đề hiện dần. Dịch phần đuôi riêng lẻ sẽ mất
/// ngữ cảnh, nên buffer này độc lập với TextGate của chế độ đọc trực tiếp.
public struct SubtitleTextBuffer {
    private var candidate: String?
    private var delivered: String?
    private var lastFrame: String?

    public init() {}

    public var hasPendingText: Bool { candidate != nil }

    public mutating func submit(_ raw: String) -> [String] {
        guard let normalized = EnglishSentenceBoundary.normalizeOCR(raw), normalized != lastFrame else { return [] }
        let previousFrame = lastFrame
        lastFrame = normalized
        var text = normalized
        if let delivered {
            if text == delivered { return [] }
            if text.hasPrefix(delivered) {
                text = String(text.dropFirst(delivered.count)).trimmingCharacters(in: .whitespaces)
                guard !text.isEmpty else { return [] }
            } else if text.split(separator: " ").count > 1, delivered.contains(text) {
                return []
            } else {
                self.delivered = nil
            }
        }
        guard let candidate else { self.candidate = text; return [] }
        if text == candidate || (text.split(separator: " ").count > 1 && candidate.contains(text)) { return [] }
        if text.contains(candidate) { self.candidate = text; return [] }
        // Một cue tiếp nối đã được ghép vào câu trước; các khung sau của cue
        // này chỉ cập nhật phần cuối, không nối lại toàn bộ phần đó lần nữa.
        if let previousFrame, candidate.hasSuffix(previousFrame), text.hasPrefix(previousFrame) {
            self.candidate = String(candidate.dropLast(previousFrame.count)) + text
            return []
        }
        if let joined = Self.joinOverlapping(candidate, text) {
            self.candidate = joined
            return []
        }
        var ready: [String] = []
        if let complete = flush() { ready.append(complete) }
        if self.candidate == nil {
            self.candidate = text
            delivered = nil
        } else if EnglishSentenceBoundary.isPlausiblyComplete(self.candidate!),
                  EnglishSentenceBoundary.startsIndependentCue(text),
                  let complete = flush(allowUnpunctuated: true) {
            ready.append(complete)
            self.candidate = text
            delivered = nil
        } else {
            self.candidate = Self.appendContinuation(self.candidate!, text)
        }
        return ready
    }

    public mutating func flush(allowUnpunctuated: Bool = false) -> String? {
        guard let text = candidate else { return nil }
        let end: String.Index
        if allowUnpunctuated, EnglishSentenceBoundary.isPlausiblyComplete(text) { end = text.endIndex }
        else if let boundary = EnglishSentenceBoundary.completePrefixEnd(in: text) { end = boundary }
        else { return nil }
        let ready = String(text[..<end]).trimmingCharacters(in: .whitespaces)
        let remaining = String(text[end...]).trimmingCharacters(in: .whitespaces)
        candidate = remaining.isEmpty ? nil : remaining
        delivered = [delivered, ready].compactMap { $0 }.joined(separator: " ")
        return ready
    }

    public mutating func endSubtitle() -> String? {
        let final = flush(allowUnpunctuated: true)
        delivered = nil
        lastFrame = nil
        return final
    }

    public mutating func reset() {
        candidate = nil
        delivered = nil
        lastFrame = nil
    }

    private static func appendContinuation(_ lhs: String, _ rhs: String) -> String {
        var left = lhs, right = rhs
        while left.hasSuffix("...") { left = String(left.dropLast(3)).trimmingCharacters(in: .whitespaces) }
        while left.hasSuffix("…") { left = String(left.dropLast()).trimmingCharacters(in: .whitespaces) }
        while right.hasPrefix("...") { right = String(right.dropFirst(3)).trimmingCharacters(in: .whitespaces) }
        while right.hasPrefix("…") { right = String(right.dropFirst()).trimmingCharacters(in: .whitespaces) }
        return left + " " + right
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
