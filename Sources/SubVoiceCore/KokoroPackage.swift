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

public enum KokoroInstallError: LocalizedError, Equatable {
    case checksumMismatch(expected: String, actual: String)
    case extractionFailed(String)
    case incompleteArchive
    case notEnoughDiskSpace(requiredBytes: Int64, availableBytes: Int64)

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
            return "Cần \(formatter.string(fromByteCount: required)) trống, "
                + "máy chỉ còn \(formatter.string(fromByteCount: available))."
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

    /// Cần chỗ cho cả archive lẫn bản giải nén cùng lúc.
    public var requiredFreeBytes: Int64 { downloadBytes * 3 }

    public static func availableBytes(at url: URL) -> Int64 {
        let values = try? url.resourceValues(
            forKeys: [.volumeAvailableCapacityForImportantUsageKey]
        )
        return values?.volumeAvailableCapacityForImportantUsage ?? 0
    }

    public func checkDiskSpace(at url: URL) throws {
        let available = Self.availableBytes(at: url)
        guard available >= requiredFreeBytes else {
            throw KokoroInstallError.notEnoughDiskSpace(
                requiredBytes: requiredFreeBytes,
                availableBytes: available
            )
        }
    }

    /// Cài gói đã tải về. Không đụng tới mạng.
    ///
    /// Thứ tự đổi tên ở cuối là chỗ quan trọng nhất: bản cũ chỉ bị xoá SAU khi
    /// bản mới đã nằm đúng chỗ, nên không có thời điểm nào người dùng còn lại
    /// một bản cài dở.
    public func install(
        downloadedArchive archive: URL,
        into layout: KokoroInstallLayout,
        fileManager: FileManager = .default,
        extract: (URL, URL) throws -> Void = KokoroPackage.extractTarZstd(archive:destination:),
        onPhase: (KokoroInstallPhase) -> Void = { _ in }
    ) throws {
        onPhase(.verifying)
        let actual = try Self.sha256Hex(of: archive)
        guard actual == sha256 else {
            try? fileManager.removeItem(at: archive)
            throw KokoroInstallError.checksumMismatch(expected: sha256, actual: actual)
        }

        onPhase(.extracting)
        try? fileManager.removeItem(at: layout.incoming)
        try fileManager.createDirectory(
            at: layout.incoming,
            withIntermediateDirectories: true
        )

        var installed = false
        defer { if !installed { try? fileManager.removeItem(at: layout.incoming) } }

        try extract(archive, layout.incoming)

        let required = [
            layout.incoming.appendingPathComponent("python/bin/python3").path,
            layout.incoming.appendingPathComponent("models/kokoro_vi.onnx").path,
        ]
        guard required.allSatisfy(fileManager.fileExists(atPath:)) else {
            throw KokoroInstallError.incompleteArchive
        }

        let manifest = try JSONEncoder().encode(KokoroManifest(version: version))
        try manifest.write(to: layout.incoming.appendingPathComponent("manifest.json"))

        onPhase(.finishing)
        try? fileManager.removeItem(at: layout.previous)
        let hadPrevious = fileManager.fileExists(atPath: layout.root.path)
        if hadPrevious {
            try fileManager.moveItem(at: layout.root, to: layout.previous)
        }
        do {
            try fileManager.moveItem(at: layout.incoming, to: layout.root)
        } catch {
            if hadPrevious {
                try? fileManager.moveItem(at: layout.previous, to: layout.root)
            }
            throw error
        }
        installed = true
        try? fileManager.removeItem(at: layout.previous)
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

    /// macOS 14 có sẵn bsdtar hỗ trợ zstd, nên không cần thư viện giải nén nào.
    public static func extractTarZstd(archive: URL, destination: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.arguments = ["--zstd", "-xf", archive.path, "-C", destination.path]
        let errors = Pipe()
        process.standardError = errors
        try process.run()
        let detail = String(
            data: errors.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw KokoroInstallError.extractionFailed(
                detail.isEmpty ? "tar thoát với mã \(process.terminationStatus)" : detail
            )
        }
    }
}
