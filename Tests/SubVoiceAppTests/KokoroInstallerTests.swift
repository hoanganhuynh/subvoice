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
        let archive = directory.appendingPathComponent("runtime.tar.gz")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.arguments = ["-czf", archive.path, "-C", stage.path, "."]
        process.environment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin"]
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
        let observer = installer.onStateChange
        return await withCheckedContinuation { continuation in
            var resumed = false
            installer.onStateChange = { state in
                observer?(state)
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
            supportsKokoro: true,
            applicationSupportDirectory: applicationSupport,
            sessionConfiguration: .ephemeral
        )
    }

    @Test func unsupportedPlatformCannotDownloadTheArmRuntime() {
        let installer = KokoroInstaller(supportsKokoro: false)
        installer.start()
        #expect(installer.state == .failed(message: KokoroPlatform.unsupportedMessage))
        #expect(!installer.state.isBusy)
        installer.refreshInstalledState()
        #expect(installer.state == .notInstalled)
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
            for: directory.appendingPathComponent("khong-ton-tai.tar.gz"),
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

    @Test func extractionRunsOffMainActorAndPublishesProgress() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let archive = try makeArchive(in: directory)
        let gate = ExtractionGate()
        defer { gate.release.signal() }
        let installer = KokoroInstaller(
            package: KokoroPackage(version: "test", downloadURL: archive,
                                   sha256: try sha256Hex(of: archive), downloadBytes: 1),
            supportsKokoro: true,
            applicationSupportDirectory: directory,
            sessionConfiguration: .ephemeral,
            extract: { try gate.extract($0, into: $1) }
        )
        var phases: [KokoroInstallState] = []
        installer.onStateChange = { phases.append($0) }
        installer.start()
        let started = await Task.detached { gate.waitUntilStarted() }.value
        #expect(started == .success)
        // Actor đang chạy trong lúc worker bị giữ ở bước giải nén.
        for _ in 0..<100 where installer.state != .extracting {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(installer.state == .extracting)
        #expect(phases.contains(.verifying))
        #expect(phases.contains(.extracting))
        gate.release.signal()
        let final = await waitForTerminalState(installer)
        #expect(final == .installed(version: "test"))
        #expect(phases.filter { [.verifying, .extracting, .finishing].contains($0) }
                == [.verifying, .extracting, .finishing])
    }

    @Test func cancellingExtractionAndRetryingDoesNotRaceTheNewInstall() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let archive = try makeArchive(in: directory)
        let gate = ExtractionGate()
        defer { gate.release.signal() }
        let installer = KokoroInstaller(
            package: KokoroPackage(version: "test", downloadURL: archive,
                                   sha256: try sha256Hex(of: archive), downloadBytes: 1),
            supportsKokoro: true,
            applicationSupportDirectory: directory,
            sessionConfiguration: .ephemeral,
            extract: { try gate.extract($0, into: $1) }
        )
        installer.start()
        let started = await Task.detached { gate.waitUntilStarted() }.value
        #expect(started == .success)
        installer.cancel()
        #expect(installer.state == .notInstalled)
        installer.start()
        #expect(installer.state.isBusy)
        gate.release.signal()
        let final = await waitForTerminalState(installer)
        #expect(final == .installed(version: "test"))
        let layout = KokoroInstallLayout(applicationSupport: directory)
        #expect(layout.installedVersion() == "test")
        #expect(!FileManager.default.fileExists(atPath: layout.incoming.path))
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
                downloadURL: URL(string: "https://subvoice.invalid/kokoro.tar.gz")!,
                sha256: String(repeating: "0", count: 64),
                downloadBytes: 1
            ),
            supportsKokoro: true,
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

/// Chặn đúng lượt giải nén đầu tiên để thử MainActor và cancel/retry khi worker còn chạy.
private final class ExtractionGate: @unchecked Sendable {
    let started = DispatchSemaphore(value: 0)
    let release = DispatchSemaphore(value: 0)
    // Chỉ hàng đợi cài đặt nối tiếp truy cập biến này.
    private var first = true

    func waitUntilStarted() -> DispatchTimeoutResult {
        started.wait(timeout: .now() + 5)
    }

    func extract(_ archive: URL, into destination: URL) throws {
        #expect(!Thread.isMainThread)
        if first {
            first = false
            started.signal()
            guard release.wait(timeout: .now() + 5) == .success else {
                throw CocoaError(.userCancelled)
            }
        }
        try KokoroPackage.extractTar(archive: archive, destination: destination)
    }
}
