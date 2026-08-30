/// Hàng đợi câu chờ đọc, có trần.
///
/// Vượt trần thì bỏ câu CŨ NHẤT chứ không bỏ câu mới: câu mới bám sát cảnh
/// người dùng đang xem hơn, còn câu cũ đã trôi qua trên màn hình rồi.
public struct SpeechQueue {
    public static let maxPending = 2

    private var pending: [String] = []
    private var speaking = false

    public init() {}

    public var pendingCount: Int { pending.count }
    public var isSpeaking: Bool { speaking }

    /// - Returns: câu cần đưa xuống backend NGAY, hoặc nil nếu phải xếp hàng chờ.
    public mutating func enqueue(_ text: String) -> String? {
        guard speaking else {
            speaking = true
            return text
        }
        pending.append(text)
        while pending.count > SpeechQueue.maxPending {
            pending.removeFirst()
        }
        return nil
    }

    /// Gọi khi backend báo đã đọc xong một câu.
    /// - Returns: câu kế tiếp cần đọc, hoặc nil nếu đã hết.
    public mutating func finished() -> String? {
        guard !pending.isEmpty else {
            speaking = false
            return nil
        }
        return pending.removeFirst()
    }

    public mutating func reset() {
        pending.removeAll()
        speaking = false
    }
}
