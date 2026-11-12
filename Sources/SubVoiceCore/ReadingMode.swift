import Foundation

public enum ReadingMode: String, Codable, CaseIterable, Equatable, Sendable {
    case vietnamese
    case englishToVietnamese

    public var title: String {
        switch self {
        case .vietnamese: "Đọc tiếng Việt"
        case .englishToVietnamese: "Dịch Anh → Việt"
        }
    }

    public var recognitionLanguages: [String] {
        self == .englishToVietnamese ? ["en-US"] : ["vi-VT"]
    }
}
