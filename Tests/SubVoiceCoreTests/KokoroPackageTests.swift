import CryptoKit
import Foundation
import Testing
@testable import SubVoiceCore

@Suite("Kokoro package")
struct KokoroPackageTests {

    /// Đúng những tệp mà một bản cài dùng được phải có, theo bố cục gói mới.
    private static let payloadFiles = [
        "python/bin/python3",
        "kokoro_service.py",
        "models/kokoro_vi.onnx",
        "models/config.json",
        "models/voicepacks/diem_trinh.npy",
    ]

    /// FileManager cho phép bắt một thao tác cụ thể hỏng, để thử đúng những
    /// nhánh mà đĩa lỗi mới chạm tới.
    private final class FailingFileManager: FileManager, @unchecked Sendable {
        var moveFailureSources: [URL] = []
        var removeFailures: [URL] = []

        private func matches(_ url: URL, _ list: [URL]) -> Bool {
            list.contains { $0.standardizedFileURL.path == url.standardizedFileURL.path }
        }

        override func moveItem(at srcURL: URL, to dstURL: URL) throws {
            if matches(srcURL, moveFailureSources) {
                throw CocoaError(.fileWriteNoPermission)
            }
            try super.moveItem(at: srcURL, to: dstURL)
        }

        override func removeItem(at url: URL) throws {
            if matches(url, removeFailures) {
                throw CocoaError(.fileWriteNoPermission)
            }
            try super.removeItem(at: url)
        }
    }

    /// Dựng một archive tar.gz thật trong thư mục tạm, giống hệt cái mà
    /// Scripts/package-kokoro.sh tạo ra: không có thư mục bọc ngoài.
    private func makeArchive(
        in directory: URL,
        marker: String,
        omitting omitted: [String] = []
    ) throws -> URL {
        let stage = directory.appendingPathComponent(
            "stage-\(UUID().uuidString)",
            isDirectory: true
        )
        for relative in Self.payloadFiles where !omitted.contains(relative) {
            let file = stage.appendingPathComponent(relative)
            try FileManager.default.createDirectory(
                at: file.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try marker.write(to: file, atomically: true, encoding: .utf8)
        }

        let archive = directory.appendingPathComponent("runtime-\(UUID().uuidString).tar.gz")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.arguments = ["-czf", archive.path, "-C", stage.path, "."]
        // Tạo fixture dưới đúng PATH mà app mở từ Finder có. Nếu ai đó đổi định
        // dạng gói sang thứ bsdtar phải gọi chương trình ngoài, như zstd, bước
        // này hỏng ngay tại đây thay vì hỏng trên máy người dùng.
        process.environment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin"]
        try process.run()
        process.waitUntilExit()
        try #require(process.terminationStatus == 0)
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

    private func package(
        version: String = "1.0.0",
        sha256: String,
        downloadBytes: Int64 = 1
    ) -> KokoroPackage {
        KokoroPackage(
            version: version,
            downloadURL: URL(string: "https://example.invalid/runtime.tar.gz")!,
            sha256: sha256,
            downloadBytes: downloadBytes
        )
    }

    /// Cài sẵn một bản chạy được, để các phép thử hỏng hóc có cái để phá.
    @discardableResult
    private func installExisting(
        in directory: URL,
        into layout: KokoroInstallLayout,
        marker: String = "cu",
        version: String = "1.0.0"
    ) throws -> URL {
        let archive = try makeArchive(in: directory, marker: marker)
        let installed = package(version: version, sha256: try sha256(of: archive))
        try installed.install(downloadedArchive: archive, into: layout)
        return archive
    }

    private func expectExistingInstallSurvived(
        _ layout: KokoroInstallLayout,
        marker: String = "cu",
        version: String = "1.0.0"
    ) throws {
        let found = try String(contentsOf: layout.python, encoding: .utf8)
        #expect(found == marker)
        let manifest = try JSONDecoder().decode(
            KokoroManifest.self,
            from: Data(contentsOf: layout.manifest)
        )
        #expect(manifest.version == version)
        #expect(!FileManager.default.fileExists(atPath: layout.incoming.path))
    }

    // MARK: - Đường đi thuận

    @Test func installPutsTheRuntimeInPlaceAndWritesAManifest() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let archive = try makeArchive(in: directory, marker: "moi")
        let layout = KokoroInstallLayout(applicationSupport: directory)
        let package = package(sha256: try sha256(of: archive))

        try package.install(downloadedArchive: archive, into: layout)

        #expect(FileManager.default.fileExists(atPath: layout.python.path))
        #expect(!FileManager.default.fileExists(atPath: layout.incoming.path))
        let manifest = try JSONDecoder().decode(
            KokoroManifest.self,
            from: Data(contentsOf: layout.manifest)
        )
        #expect(manifest.version == "1.0.0")
    }

    @Test func installKeepsTheArchiveForTheCallerToDeleteOnSuccess() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let archive = try makeArchive(in: directory, marker: "moi")
        let layout = KokoroInstallLayout(applicationSupport: directory)
        try package(sha256: try sha256(of: archive))
            .install(downloadedArchive: archive, into: layout)

        #expect(FileManager.default.fileExists(atPath: archive.path))
    }

    @Test func installedVersionIsReportedOnlyWhenTheManifestMatches() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let layout = KokoroInstallLayout(applicationSupport: directory)
        #expect(layout.installedVersion() == nil)

        let archive = try makeArchive(in: directory, marker: "moi")
        try package(sha256: try sha256(of: archive))
            .install(downloadedArchive: archive, into: layout)

        #expect(layout.installedVersion() == "1.0.0")
    }

    @Test func onPhaseReportsEveryStageInOrder() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let archive = try makeArchive(in: directory, marker: "moi")
        let layout = KokoroInstallLayout(applicationSupport: directory)

        var phases: [KokoroInstallPhase] = []
        try package(sha256: try sha256(of: archive)).install(
            downloadedArchive: archive,
            into: layout,
            onPhase: { phases.append($0) }
        )

        #expect(phases == [.verifying, .extracting, .finishing])
    }

    // MARK: - Checksum

    @Test func wrongChecksumIsRefusedAndLeavesNothingBehind() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let archive = try makeArchive(in: directory, marker: "moi")
        let layout = KokoroInstallLayout(applicationSupport: directory)
        let expected = String(repeating: "0", count: 64)
        let package = package(sha256: expected)

        #expect(
            throws: KokoroInstallError.checksumMismatch(
                expected: expected,
                actual: try sha256(of: archive)
            )
        ) {
            try package.install(downloadedArchive: archive, into: layout)
        }
        #expect(!FileManager.default.fileExists(atPath: layout.root.path))
        #expect(!FileManager.default.fileExists(atPath: layout.incoming.path))
    }

    @Test func aRefusedArchiveIsLeftForTheCallerToDelete() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let archive = try makeArchive(in: directory, marker: "moi")
        let layout = KokoroInstallLayout(applicationSupport: directory)

        #expect(throws: KokoroInstallError.self) {
            try package(sha256: String(repeating: "0", count: 64))
                .install(downloadedArchive: archive, into: layout)
        }
        #expect(FileManager.default.fileExists(atPath: archive.path))
    }

    @Test func checksumComparisonIgnoresCase() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let archive = try makeArchive(in: directory, marker: "moi")
        let layout = KokoroInstallLayout(applicationSupport: directory)

        try package(sha256: try sha256(of: archive).uppercased())
            .install(downloadedArchive: archive, into: layout)

        #expect(layout.installedVersion() == "1.0.0")
    }

    @Test func onPhaseStopsAtVerifyingWhenTheChecksumIsWrong() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let archive = try makeArchive(in: directory, marker: "moi")
        let layout = KokoroInstallLayout(applicationSupport: directory)

        var phases: [KokoroInstallPhase] = []
        #expect(throws: KokoroInstallError.self) {
            try package(sha256: String(repeating: "0", count: 64)).install(
                downloadedArchive: archive,
                into: layout,
                onPhase: { phases.append($0) }
            )
        }

        #expect(phases == [.verifying])
    }

    @Test func aFailedInstallLeavesTheExistingRuntimeUntouched() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let layout = KokoroInstallLayout(applicationSupport: directory)
        let goodArchive = try installExisting(in: directory, into: layout)

        let broken = package(version: "2.0.0", sha256: String(repeating: "0", count: 64))
        #expect(throws: KokoroInstallError.self) {
            try broken.install(downloadedArchive: goodArchive, into: layout)
        }

        try expectExistingInstallSurvived(layout)
    }

    // MARK: - Giải nén hỏng

    @Test func extractionFailureCleansUpAndSparesTheExistingRuntime() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let layout = KokoroInstallLayout(applicationSupport: directory)
        try installExisting(in: directory, into: layout)

        let newArchive = try makeArchive(in: directory, marker: "moi")
        let update = package(version: "2.0.0", sha256: try sha256(of: newArchive))

        #expect(throws: KokoroInstallError.self) {
            try update.install(
                downloadedArchive: newArchive,
                into: layout,
                extract: { _, _ in throw KokoroInstallError.extractionFailed("hỏng") }
            )
        }

        try expectExistingInstallSurvived(layout)
    }

    @Test func tarFailureIsReportedAsExtractionFailed() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let notAnArchive = directory.appendingPathComponent("runtime.tar.gz")
        try "rác".write(to: notAnArchive, atomically: true, encoding: .utf8)
        let layout = KokoroInstallLayout(applicationSupport: directory)

        #expect(throws: KokoroInstallError.self) {
            try package(sha256: try sha256(of: notAnArchive))
                .install(downloadedArchive: notAnArchive, into: layout)
        }
        #expect(!FileManager.default.fileExists(atPath: layout.incoming.path))
    }

    /// Thiếu bất kỳ tệp bắt buộc nào cũng phải bị chặn TRƯỚC khi đổi tên đè lên
    /// bản đang dùng được.
    @Test(arguments: KokoroPackageTests.payloadFiles)
    func anArchiveMissingARequiredFileIsRefused(missing: String) throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let layout = KokoroInstallLayout(applicationSupport: directory)
        try installExisting(in: directory, into: layout)

        let partial = try makeArchive(in: directory, marker: "moi", omitting: [missing])
        let update = package(version: "2.0.0", sha256: try sha256(of: partial))

        #expect(throws: KokoroInstallError.incompleteArchive) {
            try update.install(downloadedArchive: partial, into: layout)
        }

        try expectExistingInstallSurvived(layout)
    }

    // MARK: - Đổi tên và khôi phục

    @Test func aFailedSwapRollsTheOldRuntimeBack() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let layout = KokoroInstallLayout(applicationSupport: directory)
        try installExisting(in: directory, into: layout)

        let fileManager = FailingFileManager()
        fileManager.moveFailureSources = [layout.incoming]

        let newArchive = try makeArchive(in: directory, marker: "moi")
        let update = package(version: "2.0.0", sha256: try sha256(of: newArchive))

        #expect(throws: (any Error).self) {
            try update.install(
                downloadedArchive: newArchive,
                into: layout,
                fileManager: fileManager
            )
        }

        try expectExistingInstallSurvived(layout)
        #expect(!FileManager.default.fileExists(atPath: layout.previous.path))
    }

    /// Bị giết giữa hai lần đổi tên: `root` biến mất, bản cũ nằm ở `Kokoro.old`.
    @Test func anInterruptedSwapIsHealedOnTheNextInstall() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let layout = KokoroInstallLayout(applicationSupport: directory)
        try installExisting(in: directory, into: layout)

        // Dựng lại đúng hiện trường của một lần bị giết.
        try FileManager.default.moveItem(at: layout.root, to: layout.previous)
        #expect(layout.installedVersion() == nil)

        let newArchive = try makeArchive(in: directory, marker: "moi")
        let update = package(version: "2.0.0", sha256: try sha256(of: newArchive))
        #expect(throws: KokoroInstallError.self) {
            try update.install(
                downloadedArchive: newArchive,
                into: layout,
                extract: { _, _ in throw KokoroInstallError.extractionFailed("hỏng") }
            )
        }

        try expectExistingInstallSurvived(layout)
    }

    @Test func aLeftoverIncomingThatCannotBeRemovedStopsTheInstall() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let layout = KokoroInstallLayout(applicationSupport: directory)
        try installExisting(in: directory, into: layout)

        // Rác còn lại từ một lần cài trước đó.
        try FileManager.default.createDirectory(
            at: layout.incoming.appendingPathComponent("rác", isDirectory: true),
            withIntermediateDirectories: true
        )

        let fileManager = FailingFileManager()
        fileManager.removeFailures = [layout.incoming]

        let newArchive = try makeArchive(in: directory, marker: "moi")
        let update = package(version: "2.0.0", sha256: try sha256(of: newArchive))

        #expect(throws: (any Error).self) {
            try update.install(
                downloadedArchive: newArchive,
                into: layout,
                fileManager: fileManager
            )
        }

        let marker = try String(contentsOf: layout.python, encoding: .utf8)
        #expect(marker == "cu")
    }

    // MARK: - Chỗ trống trên đĩa

    @Test func requiredFreeBytesLeavesHeadroomAboveTheDownload() {
        #expect(package(sha256: "", downloadBytes: 1_000).requiredFreeBytes == 3_000)
    }

    @Test func checkDiskSpaceAcceptsASmallPackage() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        try package(sha256: "", downloadBytes: 1).checkDiskSpace(at: directory)
    }

    @Test func checkDiskSpaceRefusesAPackageNoDiskCouldHold() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let huge: Int64 = 1 << 60
        do {
            try package(sha256: "", downloadBytes: huge).checkDiskSpace(at: directory)
            Issue.record("Đáng lẽ phải từ chối vì không đủ chỗ")
        } catch let error as KokoroInstallError {
            guard case .notEnoughDiskSpace(let required, let available) = error else {
                Issue.record("Sai loại lỗi: \(error)")
                return
            }
            #expect(required == huge * 3)
            #expect(available < required)
        }
    }
}

@Suite("Kokoro package constants")
struct KokoroPackageConstantsTests {

    /// Ba giá trị này do người bảo trì dán tay sau khi chạy script đóng gói.
    /// Dán thiếu hoặc dán nhầm chỗ là app không bao giờ cài được Kokoro.
    @Test func currentPackageIsFullyFilledIn() {
        let package = KokoroPackage.current
        #expect(package.version == "1.0.1")
        #expect(package.sha256.count == 64)
        let isHex = package.sha256.allSatisfy { $0.isHexDigit }
        #expect(isHex)
        #expect(package.downloadBytes > 100_000_000)
        // Định dạng phải là thứ bsdtar xử lý nội bộ. zstd cần chương trình
        // ngoài mà macOS không có, và bản 1.0.0 đã hỏng vì chuyện đó.
        #expect(package.downloadURL.absoluteString.hasSuffix(".tar.gz"))
        #expect(package.downloadURL.absoluteString.contains(package.version))
    }
}
