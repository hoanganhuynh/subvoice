import Foundation
import Testing
@testable import SubVoiceApp
import SubVoiceCore
import SubVoiceUI

@MainActor
@Suite("Kokoro installer")
struct KokoroInstallerTests {

    @Test func cancellationLeavesTheInstallerReadyToRetry() {
        let applicationSupport = FileManager.default.temporaryDirectory
            .appendingPathComponent("SubVoiceInstallerTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: applicationSupport) }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [HangingURLProtocol.self]

        let installer = KokoroInstaller(package: KokoroPackage(
            version: "test",
            downloadURL: URL(string: "https://subvoice.test/kokoro.tar.zst")!,
            sha256: "unused",
            downloadBytes: 0
        ), applicationSupportDirectory: applicationSupport, sessionConfiguration: configuration)

        installer.start()
        #expect(installer.state.isBusy)

        installer.cancel()
        #expect(!installer.state.isBusy)

        installer.start()
        #expect(installer.state.isBusy)
        installer.cancel()
    }
}

private final class HangingURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {}
    override func stopLoading() {}
}
