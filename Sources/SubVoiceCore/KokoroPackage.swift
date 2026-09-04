import CryptoKit
import Foundation

/// Nội dung `manifest.json` nằm trong thư mục runtime đã cài.
public struct KokoroManifest: Codable, Equatable, Sendable {
    public let version: String

    public init(version: String) {
        self.version = version
    }
}

/// Các đường dẫn liên quan tới một lần cài. Gom vào một chỗ để không có
/// chuỗi đường dẫn nào bị viết tay hai lần.
public struct KokoroInstallLayout: Equatable, Sendable {
    public let root: URL
    public let incoming: URL
    public let previous: URL

    public init(applicationSupport: URL) {
        let base = applicationSupport.appendingPathComponent("SubVoice", isDirectory: true)
        root = base.appendingPathComponent("Kokoro", isDirectory: true)
        incoming = base.appendingPathComponent("Kokoro.incoming", isDirectory: true)
        previous = base.appendingPathComponent("Kokoro.old", isDirectory: true)
    }

    /// Đúng những tệp mà `KokoroRuntime.discover()` đòi hỏi. Một danh sách duy
    /// nhất, vì hai danh sách lệch nhau nghĩa là gói thiếu tệp vẫn được cài đè
    /// lên bản đang chạy được rồi mới phát hiện ra là hỏng.
    public static let requiredRelativePaths = [
        "python/bin/python3",
        "kokoro_service.py",
        "models/kokoro_vi.onnx",
        "models/config.json",
        "models/voicepacks/diem_trinh.npy",
    ]

    public static func requiredFiles(in root: URL) -> [URL] {
        requiredRelativePaths.map(root.appendingPathComponent)
    }

    public var manifest: URL { root.appendingPathComponent("manifest.json") }
    public var python: URL { root.appendingPathComponent("python/bin/python3") }
    public var sitePackages: URL {
        root.appendingPathComponent("site-packages", isDirectory: true)
    }
    public var models: URL { root.appendingPathComponent("models", isDirectory: true) }
    public var service: URL { root.appendingPathComponent("kokoro_service.py") }

    /// Phiên bản đang cài, hoặc `nil` nếu chưa cài hoặc bản cài hỏng.
    public func installedVersion(fileManager: FileManager = .default) -> String? {
        guard let data = fileManager.contents(atPath: manifest.path),
              let decoded = try? JSONDecoder().decode(KokoroManifest.self, from: data),
              fileManager.fileExists(atPath: python.path)
        else { return nil }
        return decoded.version
    }
}

/// Giai đoạn của một lần cài, để giao diện nói đúng việc đang diễn ra thay vì
/// gộp tất cả vào một chữ "đang cài".
public enum KokoroInstallPhase: Equatable, Sendable {
    case verifying
    case extracting
    case finishing
}

public enum KokoroInstallError: LocalizedError, Equatable, Sendable {
    case checksumMismatch(expected: String, actual: String)
    case extractionFailed(String)
    case incompleteArchive
    case notEnoughDiskSpace(requiredBytes: Int64, availableBytes: Int64)
    case rollbackFailed(previousInstallPath: String)

    public var errorDescription: String? {
        switch self {
        case .checksumMismatch:
            return "Gói tải về không toàn vẹn. Hãy thử tải lại."
        case .extractionFailed(let detail):
            return "Không giải nén được gói Kokoro: \(detail)"
        case .incompleteArchive:
            return "Gói Kokoro thiếu tệp bắt buộc."
        case .notEnoughDiskSpace(let required, let available):
            let formatter = ByteCountFormatter()
            formatter.allowsNonnumericFormatting = false
            return "Cần \(formatter.string(fromByteCount: required)) trống, "
                + "máy chỉ còn \(formatter.string(fromByteCount: available))."
        case .rollbackFailed(let path):
            return "Cài Kokoro hỏng và không khôi phục được bản cũ. "
                + "Bản cũ đang nằm ở \(path)."
        }
    }
}

/// Gói runtime Kokoro mà bản app này biết cách cài.
public struct KokoroPackage: Equatable, Sendable {
    public let version: String
    public let downloadURL: URL
    public let sha256: String
    public let downloadBytes: Int64

    public init(version: String, downloadURL: URL, sha256: String, downloadBytes: Int64) {
        self.version = version
        self.downloadURL = downloadURL
        self.sha256 = sha256
        self.downloadBytes = downloadBytes
    }
}

extension KokoroPackage {

    /// Gấp ba: archive tải về, cây đã giải nén (lớn hơn archive), và chút dư.
    public var requiredFreeBytes: Int64 { downloadBytes * 3 }

    public static func availableBytes(at url: URL) -> Int64 {
        let values = try? url.resourceValues(
            forKeys: [.volumeAvailableCapacityForImportantUsageKey]
        )
        return values?.volumeAvailableCapacityForImportantUsage ?? 0
    }

    /// Gọi TRƯỚC khi bắt đầu tải. `install` cố tình không gọi hàm này: kiểm tra
    /// chỗ trống sau khi đã tốn hàng trăm MB băng thông thì quá muộn.
    public func checkDiskSpace(at url: URL) throws {
        let available = Self.availableBytes(at: url)
        guard available >= requiredFreeBytes else {
            throw KokoroInstallError.notEnoughDiskSpace(
                requiredBytes: requiredFreeBytes,
                availableBytes: available
            )
        }
    }

    /// Cài gói đã tải về. Không đụng tới mạng, và không xoá archive — vòng đời
    /// của tệp đó thuộc về nơi gọi.
    ///
    /// Một lần cài THẤT BẠI không bao giờ để lại bản dở: bản cũ chỉ bị xoá sau
    /// khi bản mới đã nằm đúng chỗ. Một lần cài BỊ GIẾT giữa hai lần đổi tên thì
    /// có, và `healInterruptedSwap` ở đầu hàm dọn đúng hiện trường đó.
    public func install(
        downloadedArchive archive: URL,
        into layout: KokoroInstallLayout,
        fileManager: FileManager = .default,
        extract: (URL, URL) throws -> Void = KokoroPackage.extractTar(archive:destination:),
        onPhase: (KokoroInstallPhase) -> Void = { _ in }
    ) throws {
        try Self.healInterruptedSwap(layout, fileManager: fileManager)

        onPhase(.verifying)
        let actual = try Self.sha256Hex(of: archive)
        // Hằng số này do người bảo trì dán tay; một lần dán chữ hoa không đáng
        // biến thành "gói không toàn vẹn" vĩnh viễn.
        guard actual.caseInsensitiveCompare(sha256) == .orderedSame else {
            throw KokoroInstallError.checksumMismatch(expected: sha256, actual: actual)
        }

        onPhase(.extracting)
        // `try?` ở đây sẽ nuốt mất trường hợp XOÁ KHÔNG ĐƯỢC, và khi đó tar sẽ
        // trộn gói mới vào rác của lần trước — đúng cái bản cài dở mà hàm này
        // hứa là không bao giờ tạo ra.
        if fileManager.fileExists(atPath: layout.incoming.path) {
            try fileManager.removeItem(at: layout.incoming)
        }
        try fileManager.createDirectory(at: layout.incoming, withIntermediateDirectories: true)

        var installed = false
        defer { if !installed { try? fileManager.removeItem(at: layout.incoming) } }

        try extract(archive, layout.incoming)

        let required = KokoroInstallLayout.requiredFiles(in: layout.incoming)
        guard required.allSatisfy({ fileManager.fileExists(atPath: $0.path) }) else {
            throw KokoroInstallError.incompleteArchive
        }

        let manifest = try JSONEncoder().encode(KokoroManifest(version: version))
        try manifest.write(to: layout.incoming.appendingPathComponent("manifest.json"))

        onPhase(.finishing)
        try? fileManager.removeItem(at: layout.previous)
        let hadExistingInstall = fileManager.fileExists(atPath: layout.root.path)
        if hadExistingInstall {
            try fileManager.moveItem(at: layout.root, to: layout.previous)
        }
        do {
            try fileManager.moveItem(at: layout.incoming, to: layout.root)
        } catch {
            guard hadExistingInstall else { throw error }
            do {
                try fileManager.moveItem(at: layout.previous, to: layout.root)
            } catch {
                // Bản cũ bị kẹt ở Kokoro.old. Giữ lại cây vừa giải nén để còn
                // thử lại được, và báo đúng chỗ bản cũ đang nằm — lỗi gốc
                // "không đổi tên được" giấu mất sự thật tệ hơn này.
                installed = true
                throw KokoroInstallError.rollbackFailed(
                    previousInstallPath: layout.previous.path
                )
            }
            throw error
        }
        installed = true
        try? fileManager.removeItem(at: layout.previous)
    }

    /// Bị giết giữa hai lần đổi tên thì `root` biến mất còn bản cũ nằm nguyên
    /// vẹn ở `Kokoro.old`. Không có bước này, app báo "chưa cài" và bắt người
    /// dùng tải lại hàng trăm MB trong khi bản chạy được vẫn nằm trên đĩa.
    static func healInterruptedSwap(
        _ layout: KokoroInstallLayout,
        fileManager: FileManager = .default
    ) throws {
        guard !fileManager.fileExists(atPath: layout.root.path),
              fileManager.fileExists(atPath: layout.previous.path)
        else { return }
        try fileManager.moveItem(at: layout.previous, to: layout.root)
    }

    static func sha256Hex(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Giải nén bằng bsdtar sẵn có của macOS.
    ///
    /// KHÔNG truyền cờ định dạng: `-xf` để libarchive tự nhận dạng, và nó chỉ
    /// xử lý nội bộ được gzip, xz, bzip2. Với zstd bsdtar phải gọi chương trình
    /// `zstd` bên ngoài — thứ macOS không có sẵn, và app mở từ Finder cũng
    /// không thấy bản Homebrew vì PATH chỉ có /usr/bin:/bin:/usr/sbin:/sbin.
    /// Bản 1.0.0 nén bằng zstd nên hỏng đúng chỗ này trên máy người dùng.
    public static func extractTar(archive: URL, destination: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.arguments = ["-xf", archive.path, "-C", destination.path]
        // PATH tối thiểu và cố định: quá trình giải nén không được phép phụ
        // thuộc vào thứ gì người dùng cài thêm.
        process.environment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin"]
        let errors = Pipe()
        process.standardError = errors
        try process.run()
        // `readToEnd()` ném lỗi tử tế, khác `readDataToEndOfFile()` vốn ném
        // ngoại lệ ObjC. Phải đọc hết TRƯỚC `waitUntilExit()`, nếu không tar
        // ghi quá bộ đệm pipe là kẹt cứng.
        let raw = (try? errors.fileHandleForReading.readToEnd()) ?? Data()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let detail = String(decoding: raw.prefix(4096), as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw KokoroInstallError.extractionFailed(
                detail.isEmpty ? "tar thoát với mã \(process.terminationStatus)" : detail
            )
        }
    }
}

extension KokoroPackage {
    /// Gói mà bản app này biết cách cài.
    ///
    /// Ba giá trị dưới đây đi liền nhau: đổi gói thì phải chạy lại
    /// `Scripts/package-kokoro.sh`, dán `SHA256` và `SIZE` nó in ra vào đây, rồi
    /// đẩy archive lên GitHub Release trùng tag. Sai SHA thì `install` từ chối
    /// gói — hỏng theo hướng an toàn, nhưng người dùng sẽ không tài nào cài được.
    public static let current = KokoroPackage(
        version: "1.0.1",
        downloadURL: URL(
            string: "https://github.com/hoanganhuynh/subvoice/releases/download"
                + "/kokoro-runtime-1.0.1/kokoro-runtime-1.0.1-arm64.tar.gz"
        )!,
        sha256: "1bd8ac3dd21186b07f638bdaf5c4668397e8bc40786bb7abdf3508054505aa97",
        downloadBytes: 393_540_951
    )
}
