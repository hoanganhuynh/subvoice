import Foundation
import Testing
@testable import SubVoiceApp
import SubVoiceCore
import SubVoiceUI

/// Chạy trọn chuỗi tải–kiểm–cài của `KokoroInstaller` mà KHÔNG cần mạng.
///
/// `URLSession` xử lý được `file://`, nên một archive thật nằm trong thư mục tạm
/// đi qua đúng những bước mà một gói tải từ GitHub Release phải đi: download
/// task, tệp tạm, đối chiếu SHA-256, giải nén, đổi tên nguyên khối. Đây là lớp
/// glue duy nhất trong dự án mà test của SubVoiceCore không chạm tới.
@MainActor
@Suite("Kokoro installer", .timeLimit(.minutes(1)))
struct KokoroInstallerTests {

    private static let payloadFiles = [
        "python/bin/python3",
        "kokoro_service.py",
        "models/kokoro_vi.onnx",
        "models/config.json",
        "models/voicepacks/diem_trinh.npy",
    ]

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("SubVoiceInstallerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Dựng archive giống hệt cái mà Scripts/package-kokoro.sh tạo ra.
    private func makeArchive(in directory: URL, marker: String = "moi") throws -> URL {
        let stage = directory.appendingPathComponent("stage", isDirectory: true)
        for relative in Self.payloadFiles {
            let file = stage.appendingPathComponent(relative)
            try FileManager.default.createDirectory(
                at: file.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try marker.write(to: file, atomically: true, encoding: .utf8)
        }
        let archive = directory.appendingPathComponent("runtime.tar.zst")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.arguments = ["--zstd", "-cf", archive.path, "-C", stage.path, "."]
        try process.run()
        process.waitUntilExit()
        try #require(process.terminationStatus == 0)
        return archive
    }

    private func sha256Hex(of url: URL) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/shasum")
        process.arguments = ["-a", "256", url.path]
        let output = Pipe()
        process.standardOutput = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let text = String(decoding: data, as: UTF8.self)
        return try #require(text.split(separator: " ").first.map(String.init))
    }

    /// Chờ tới khi installer rời trạng thái bận.
    private func waitForTerminalState(_ installer: KokoroInstaller) async -> KokoroInstallState {
        if !installer.state.isBusy { return installer.state }
        return await withCheckedContinuation { continuation in
            var resumed = false
            installer.onStateChange = { state in
                guard !state.isBusy, !resumed else { return }
                resumed = true
                continuation.resume(returning: state)
            }
        }
    }

    private func installer(
        for archive: URL,
        sha256: String,
        applicationSupport: URL,
        version: String = "test-1.0.0"
    ) -> KokoroInstaller {
        KokoroInstaller(
            package: KokoroPackage(
                version: version,
                downloadURL: archive,
                sha256: sha256,
                downloadBytes: 1
            ),
            applicationSupportDirectory: applicationSupport,
            sessionConfiguration: .ephemeral
        )
    }

    @Test func installsALocalArchiveEndToEnd() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let archive = try makeArchive(in: directory)
        let installer = installer(
            for: archive,
            sha256: try sha256Hex(of: archive),
            applicationSupport: directory
        )

        installer.start()
        let final = await waitForTerminalState(installer)

        #expect(final == .installed(version: "test-1.0.0"))

        let layout = KokoroInstallLayout(applicationSupport: directory)
        #expect(layout.installedVersion() == "test-1.0.0")
        #expect(FileManager.default.fileExists(atPath: layout.python.path))
        #expect(!FileManager.default.fileExists(atPath: layout.incoming.path))
    }

    @Test func aTamperedArchiveIsRefusedAndNothingIsInstalled() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let archive = try makeArchive(in: directory)
        let installer = installer(
            for: archive,
            sha256: String(repeating: "0", count: 64),
            applicationSupport: directory
        )

        installer.start()
        let final = await waitForTerminalState(installer)

        guard case .failed = final else {
            Issue.record("Đáng lẽ phải hỏng vì sai checksum, nhận: \(final)")
            return
        }
        let layout = KokoroInstallLayout(applicationSupport: directory)
        #expect(layout.installedVersion() == nil)
        #expect(!FileManager.default.fileExists(atPath: layout.root.path))
        #expect(!FileManager.default.fileExists(atPath: layout.incoming.path))
    }

    @Test func aMissingArchiveSurfacesAsFailureNotACrash() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let installer = installer(
            for: directory.appendingPathComponent("khong-ton-tai.tar.zst"),
            sha256: String(repeating: "0", count: 64),
            applicationSupport: directory
        )

        installer.start()
        let final = await waitForTerminalState(installer)

        guard case .failed = final else {
            Issue.record("Đáng lẽ phải hỏng vì không có tệp, nhận: \(final)")
            return
        }
    }

    /// Huỷ giữa chừng phải trả installer về trạng thái bấm lại được ngay.
    @Test func cancellationLeavesTheInstallerReadyToRetry() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [HangingURLProtocol.self]

        let installer = KokoroInstaller(
            package: KokoroPackage(
                version: "test",
                downloadURL: URL(string: "https://subvoice.invalid/kokoro.tar.zst")!,
                sha256: String(repeating: "0", count: 64),
                downloadBytes: 1
            ),
            applicationSupportDirectory: directory,
            sessionConfiguration: configuration
        )

        installer.start()
        #expect(installer.state.isBusy)

        installer.cancel()
        #expect(!installer.state.isBusy)

        installer.start()
        #expect(installer.state.isBusy)
        installer.cancel()
    }
}

/// Giữ request treo mãi mà không chạm mạng, để thử đúng nhánh huỷ.
private final class HangingURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {}
    override func stopLoading() {}
}
