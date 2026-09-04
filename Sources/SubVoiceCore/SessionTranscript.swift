import Foundation

/// Chế độ giao diện người dùng chọn trong cài đặt.
public enum ThemeMode: String, Codable, CaseIterable, Equatable, Sendable {
    case system
    case light
    case dark
}

/// Một câu đã được đọc trong phiên hiện tại.
public struct TranscriptEntry: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let timestamp: Date
    public let text: String

    public init(id: UUID = UUID(), timestamp: Date, text: String) {
        self.id = id
        self.timestamp = timestamp
        self.text = text
    }
}

/// Lịch sử câu đã đọc, chỉ nằm trong bộ nhớ tiến trình.
///
/// Không bao giờ được ghi xuống đĩa: phụ đề là nội dung riêng tư của người
/// dùng, nên nó biến mất cùng lúc với app.
public struct SessionTranscript: Equatable, Sendable {
    public static let maximumEntries = 200

    public private(set) var entries: [TranscriptEntry] = []

    public init() {}

    public mutating func append(text: String, at timestamp: Date = .now) {
        entries.insert(TranscriptEntry(timestamp: timestamp, text: text), at: 0)
        if entries.count > Self.maximumEntries {
            entries.removeLast(entries.count - Self.maximumEntries)
        }
    }

    public mutating func clear() {
        entries.removeAll(keepingCapacity: true)
    }

    /// Lọc theo từ khoá, không phân biệt hoa thường. Chuỗi chỉ có khoảng trắng
    /// được coi như không lọc gì cả.
    public func matching(_ query: String) -> [TranscriptEntry] {
        let value = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return entries }
        return entries.filter { $0.text.localizedCaseInsensitiveContains(value) }
    }
}
