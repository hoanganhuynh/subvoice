import CryptoKit
import Foundation
import Testing
@testable import SubVoiceCore

@Suite("Kokoro package")
struct KokoroPackageTests {

    /// Dựng một archive tar.zst thật trong thư mục tạm, giống hệt cái mà
    /// Scripts/package-kokoro.sh tạo ra: không có thư mục bọc ngoài.
    private func makeArchive(in directory: URL, marker: String) throws -> URL {
        let stage = directory.appendingPathComponent("stage", isDirectory: true)
        let python = stage.appendingPathComponent("python/bin", isDirectory: true)
        let models = stage.appendingPathComponent("models", isDirectory: true)
        try FileManager.default.createDirectory(at: python, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: models, withIntermediateDirectories: true)
        try marker.write(
            to: python.appendingPathComponent("python3"),
            atomically: true,
            encoding: .utf8
        )
        try marker.write(
            to: models.appendingPathComponent("kokoro_vi.onnx"),
            atomically: true,
            encoding: .utf8
        )

        let archive = directory.appendingPathComponent("runtime.tar.zst")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.arguments = ["--zstd", "-cf", archive.path, "-C", stage.path, "."]
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
        return archive
    }

    private func sha256(of url: URL) throws -> String {
        let digest = SHA256.hash(data: try Data(contentsOf: url))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("KokoroPackageTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func installPutsTheRuntimeInPlaceAndWritesAManifest() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let archive = try makeArchive(in: directory, marker: "moi")
        let layout = KokoroInstallLayout(applicationSupport: directory)
        let package = KokoroPackage(
            version: "1.0.0",
            downloadURL: URL(string: "https://example.invalid/runtime.tar.zst")!,
            sha256: try sha256(of: archive),
            downloadBytes: 1
        )

        try package.install(downloadedArchive: archive, into: layout)

        #expect(FileManager.default.fileExists(atPath: layout.python.path))
        #expect(!FileManager.default.fileExists(atPath: layout.incoming.path))
        let manifest = try JSONDecoder().decode(
            KokoroManifest.self,
            from: Data(contentsOf: layout.manifest)
        )
        #expect(manifest.version == "1.0.0")
    }

    @Test func wrongChecksumIsRefusedAndLeavesNothingBehind() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let archive = try makeArchive(in: directory, marker: "moi")
        let layout = KokoroInstallLayout(applicationSupport: directory)
        let package = KokoroPackage(
            version: "1.0.0",
            downloadURL: URL(string: "https://example.invalid/runtime.tar.zst")!,
            sha256: String(repeating: "0", count: 64),
            downloadBytes: 1
        )

        #expect(throws: KokoroInstallError.self) {
            try package.install(downloadedArchive: archive, into: layout)
        }
        #expect(!FileManager.default.fileExists(atPath: layout.root.path))
        #expect(!FileManager.default.fileExists(atPath: layout.incoming.path))
    }

    @Test func aFailedInstallLeavesTheExistingRuntimeUntouched() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let layout = KokoroInstallLayout(applicationSupport: directory)
        let goodArchive = try makeArchive(in: directory, marker: "cu")
        let installed = KokoroPackage(
            version: "1.0.0",
            downloadURL: URL(string: "https://example.invalid/runtime.tar.zst")!,
            sha256: try sha256(of: goodArchive),
            downloadBytes: 1
        )
        try installed.install(downloadedArchive: goodArchive, into: layout)

        let broken = KokoroPackage(
            version: "2.0.0",
            downloadURL: URL(string: "https://example.invalid/runtime.tar.zst")!,
            sha256: String(repeating: "0", count: 64),
            downloadBytes: 1
        )
        #expect(throws: KokoroInstallError.self) {
            try broken.install(downloadedArchive: goodArchive, into: layout)
        }

        let marker = try String(contentsOf: layout.python, encoding: .utf8)
        #expect(marker == "cu")
        let manifest = try JSONDecoder().decode(
            KokoroManifest.self,
            from: Data(contentsOf: layout.manifest)
        )
        #expect(manifest.version == "1.0.0")
    }

    @Test func installedVersionIsReportedOnlyWhenTheManifestMatches() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let layout = KokoroInstallLayout(applicationSupport: directory)
        #expect(layout.installedVersion() == nil)

        let archive = try makeArchive(in: directory, marker: "moi")
        let package = KokoroPackage(
            version: "1.0.0",
            downloadURL: URL(string: "https://example.invalid/runtime.tar.zst")!,
            sha256: try sha256(of: archive),
            downloadBytes: 1
        )
        try package.install(downloadedArchive: archive, into: layout)

        #expect(layout.installedVersion() == "1.0.0")
    }
}
