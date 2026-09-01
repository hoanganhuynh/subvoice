import Foundation

/// Một giọng đọc có thể chọn, dùng chung cho cả hai backend.
public struct SpeechVoiceOption: Identifiable, Equatable, Sendable {
    public let identifier: String
    public let name: String

    public var id: String { identifier }

    public init(identifier: String, name: String) {
        self.identifier = identifier
        self.name = name
    }
}
