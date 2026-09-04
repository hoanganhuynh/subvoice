import Foundation

/// Ghi trace chẩn đoán ra file phẳng.
///
/// KHÔNG dùng `NSLog` cho việc này: unified logging của macOS che mọi nội dung
/// động thành `<private>` khi đọc từ tiến trình khác, nên `log show` chỉ hiện
/// `(Foundation) <private>` — trace vẫn chạy nhưng vô dụng.
final class TraceLog {
    static let path = "/tmp/subvoice-trace.log"
    static let shared = TraceLog()

    private let handle: FileHandle?
    private let queue = DispatchQueue(label: "com.williens.subvoice.trace")
    private let formatter: DateFormatter

    private init() {
        FileManager.default.createFile(atPath: Self.path, contents: nil)
        handle = FileHandle(forWritingAtPath: Self.path)
        formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
    }

    func write(_ line: String) {
        let stamped = formatter.string(from: Date()) + "  " + line + "\n"
        queue.async { [weak self] in
            guard let data = stamped.data(using: .utf8) else { return }
            try? self?.handle?.write(contentsOf: data)
        }
    }
}
