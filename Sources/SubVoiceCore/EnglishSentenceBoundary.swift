import Foundation

/// Quy tắc thận trọng cho phụ đề: dấu kết câu là tín hiệu chính. Không coi
/// một timer hoặc một khung hình trống là bằng chứng câu đã đủ ý.
enum EnglishSentenceBoundary {
    private static let titles: Set<String> = [
        "mr", "mrs", "ms", "dr", "prof", "st", "vs", "jr", "sr", "fig", "approx",
    ]
    private static let dependent = [
        "if ", "unless ", "although ", "though ", "because ", "when ", "while ",
        "until ", "before ", "after ", "since ", "whether ", "even though ",
        "as soon as ", "the reason ", "the fact that ",
    ]
    private static let dangling: Set<String> = [
        "a", "an", "the", "my", "your", "our", "their", "its", "and", "or", "but",
        "because", "if", "although", "when", "while", "unless", "that", "which",
        "to", "of", "for", "from", "with", "without", "at", "in", "on", "into", "by",
        "than", "as", "is", "are", "was", "were", "am", "be", "been", "being",
        "have", "has", "had", "will", "would", "could", "should", "can", "may", "might",
        "must", "not", "very", "too", "want", "wants", "wanted", "need", "needs", "needed",
        "trying", "try", "tries", "tried", "tell", "tells", "telling", "ask", "asks", "asking",
        "explain", "explaining", "like", "about", "through", "between", "towards",
    ]
    private static let shortReplies: Set<String> = [
        "yes", "no", "okay", "ok", "sure", "maybe", "sorry", "thanks", "hello", "hi",
        "bye", "goodbye", "please", "what", "why", "who", "where", "never", "exactly",
        "absolutely", "certainly", "stop", "wait", "go", "come", "look", "listen", "help",
        "leave", "stay", "run", "relax", "quiet", "enough", "welcome",
    ]

    static func normalizeOCR(_ raw: String) -> String? {
        TextGate.normalize(raw)?
            .replacingOccurrences(of: #"\s+([,.!?;:])"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: "’", with: "'")
    }

    static func completePrefixEnd(in text: String) -> String.Index? {
        var boundary: String.Index?
        for index in text.indices where ".!?".contains(text[index]) {
            let character = text[index]
            let next = text.index(after: index)
            if character == "." {
                if next < text.endIndex, text[next] == "." || text[next].isNumber { continue }
                if index > text.startIndex, text[text.index(before: index)] == "." { continue }
                let token = text[..<index].split(whereSeparator: \.isWhitespace).last.map(String.init) ?? ""
                let word = token.trimmingCharacters(in: .punctuationCharacters).lowercased()
                if titles.contains(word) { continue }
                if word == "no", text[next...].drop(while: \.isWhitespace).first?.isNumber == true { continue }
                if word.count == 1, word.first?.isLetter == true { continue }
                // U.S., e.g., i.e. — dấu chấm trong chữ viết tắt.
                if word.contains("."), word.split(separator: ".").allSatisfy({
                    $0.count == 1 && $0.first?.isLetter == true
                }) { continue }
            }
            var end = next
            while end < text.endIndex, "\"”’')]}".contains(text[end]) { end = text.index(after: end) }
            guard end == text.endIndex || text[end].isWhitespace else { continue }
            guard isBalanced(String(text[..<end])) else { continue }
            boundary = end
        }
        return boundary
    }

    /// Chỉ dùng khi một cue đã thay đổi hoặc chờ ổn định lâu hơn. Đây là
    /// fallback cho phụ đề không có dấu câu, không phải bộ phân tích ngữ pháp.
    static func isPlausiblyComplete(_ text: String) -> Bool {
        if completePrefixEnd(in: text) == text.endIndex { return true }
        guard let last = text.last, !",;:—–-…".contains(last), !text.hasSuffix("..."),
              isBalanced(text) else { return false }
        let words = text.lowercased().split(separator: " ").map {
            $0.trimmingCharacters(in: .punctuationCharacters)
        }
        guard let final = words.last, !titles.contains(final) else { return false }
        let question = isQuestion(text)
        if dangling.contains(final) {
            if question, words.count == 3 { return true }
            let strandedPrepositions: Set<String> = ["for", "with", "to", "about", "from", "at", "on"]
            let strandedVerbs: Set<String> = ["waiting", "looking", "talking", "speaking", "talk", "speak",
                                             "working", "work", "listening", "coming", "come"]
            if question, words.count >= 4, ["what", "who", "which", "where"].contains(words[0]),
               strandedPrepositions.contains(final), strandedVerbs.contains(words[words.count - 2]) { return true }
            return false
        }
        let lower = text.lowercased()
        if lower.range(of: #"\b(?:think|thought|hope|wish|believe|said|tell|told|ask|asked)\s+(?:that\s+)?(?:i|you|he|she|it|we|they)$"#,
                       options: .regularExpression) != nil { return false }
        if question { return true }
        if lower.hasPrefix("the reason ") {
            for copula in [" is ", " was ", " means "] {
                if let range = lower.range(of: copula, options: .backwards) {
                    var complement = String(lower[range.upperBound...]).trimmingCharacters(in: .whitespaces)
                    if complement.hasPrefix("because ") { complement = String(complement.dropFirst(8)) }
                    return isPlausiblyComplete(complement)
                }
            }
        }
        if dependent.contains(where: { lower.hasPrefix($0) }) {
            guard let comma = text.lastIndex(of: ",") else { return false }
            return isPlausiblyComplete(String(text[text.index(after: comma)...]).trimmingCharacters(in: .whitespaces))
        }
        if lower.range(of: #"\b(?:am|is|are|was|were|i'm|he's|she's|we're|they're)\s+going$"#,
                       options: .regularExpression) != nil { return false }
        return words.count > 1 || shortReplies.contains(final)
    }

    static func startsIndependentCue(_ text: String) -> Bool {
        let leading = text.trimmingCharacters(in: .whitespaces.union(.punctuationCharacters))
        guard leading.first?.isUppercase == true else { return false }
        if isQuestion(leading) { return true }
        return !dependent.contains { leading.lowercased().hasPrefix($0) }
    }

    private static func isQuestion(_ text: String) -> Bool {
        let words = text.lowercased().split(separator: " ").map(String.init)
        guard words.count >= 3, ["who", "what", "which", "where", "when", "why", "how"].contains(words[0]),
              ["am", "is", "are", "was", "were", "do", "does", "did", "can", "could", "will", "would", "should", "have", "has"].contains(words[1]) else { return false }
        if words.count == 3 {
            return ["who", "what", "where", "how"].contains(words[0])
                && ["am", "is", "are", "was", "were"].contains(words[1])
                && (!dangling.contains(String(words[2])) || ["this", "that"].contains(words[2]))
        }
        return true
    }

    private static func isBalanced(_ text: String) -> Bool {
        guard text.filter({ $0 == "\"" }).count.isMultiple(of: 2) else { return false }
        for (open, close): (Character, Character) in [("(", ")"), ("[", "]"), ("“", "”")] {
            if text.filter({ $0 == open }).count != text.filter({ $0 == close }).count { return false }
        }
        return true
    }
}
