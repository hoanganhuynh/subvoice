import Foundation

/// App và cửa sổ đã sinh ra vùng đọc.
///
/// `windowNumber` CHỈ có nghĩa trong phiên hiện tại: macOS cấp lại số hiệu cửa
/// sổ sau khi app đích khởi động lại, nên đầu mỗi phiên đọc đều phải neo lại
/// bằng `RegionFocusPolicy.reanchor`.
public struct RegionOwner: Codable, Equatable, Sendable {
    public var bundleIdentifier: String
    public var applicationName: String
    public var windowNumber: UInt32?
    /// Tiêu đề cửa sổ lúc khoanh vùng, đã chuẩn hoá. `nil` khi không đọc được.
    public var windowTitle: String?

    public init(
        bundleIdentifier: String,
        applicationName: String,
        windowNumber: UInt32?,
        windowTitle: String?
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.applicationName = applicationName
        self.windowNumber = windowNumber
        self.windowTitle = windowTitle
    }

    /// Cắt phần đếm thông báo `(3) ` mà web hay chèn vào đầu tiêu đề tab, rồi
    /// cắt khoảng trắng hai đầu. Không có gì còn lại thì trả `nil`.
    ///
    /// Chỉ cắt khi trong ngoặc toàn chữ số — `(Trailer)` là một phần của tên
    /// thật, cắt đi là so sánh sai.
    public static func normalizedTitle(_ raw: String?) -> String? {
        guard var text = raw?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return nil
        }
        while text.hasPrefix("("), let close = text.firstIndex(of: ")") {
            let digits = text[text.index(after: text.startIndex)..<close]
            guard !digits.isEmpty, digits.allSatisfy(\.isNumber) else { break }
            text = String(text[text.index(after: close)...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return text.isEmpty ? nil : text
    }
}
