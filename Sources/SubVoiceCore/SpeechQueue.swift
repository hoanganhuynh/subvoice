/// Hàng đợi câu chờ đọc.
///
/// Khi có bốn câu chờ, bỏ hai câu cũ nhất để bám lại phụ đề.
/// Câu đang phát luôn được đọc hết; các câu còn lại giữ nguyên thứ tự.
public struct SpeechQueue {
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
        if pending.count >= 4 { pending.removeFirst(2) }
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

    /// Bỏ những câu còn nằm chờ, giữ nguyên câu đang phát dở.
    ///
    /// Dùng khi cửa sổ chủ của vùng đọc vừa khuất: các câu chờ được bắt trong
    /// vài giây trước đó, mà việc phát hiện khuất chậm nhất một vòng poll, nên
    /// không thể chắc câu nào còn là phụ đề thật. Người dùng cũng vừa nhìn đi
    /// chỗ khác, đọc nốt cả hàng đợi chỉ làm app có vẻ hỏng.
    public mutating func dropPending() {
        pending.removeAll()
    }

    public mutating func reset() {
        pending.removeAll()
        speaking = false
    }
}
