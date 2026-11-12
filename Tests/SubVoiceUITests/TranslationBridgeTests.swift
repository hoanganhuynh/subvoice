import Foundation
import Testing
@testable import SubVoiceUI

@MainActor
@Suite("Translation preparation")
struct TranslationBridgeTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["SUBVOICE_CHECK_TRANSLATION"] == "1"))
    func installedAppleLanguagesTranslateEnglishOnThisMac() async throws {
        let bridge = TranslationBridge()
        await bridge.refreshAvailability()
        print("Apple en→vi availability: \(bridge.status.message)")
        try #require(bridge.status.isReady, "Gói ngôn ngữ chưa được tải; cần chuẩn bị trong app trước.")
        let result = try await bridge.translate("Hello, how are you?")
        #expect(!result.isEmpty)
        #expect(result != "Hello, how are you?")
        print("Apple en→vi result: \(result)")
    }

    @Test func unsupportedTranslationCannotBePreparedOrMarkedReady() async {
        let bridge = TranslationBridge(supported: false)
        #expect(!bridge.status.isReady)
        do {
            try await bridge.prepare()
            Issue.record("Unsupported translation was accepted")
        } catch {}
        #expect(!bridge.status.isReady)
        #expect(bridge.request == nil)
    }

    @Test func cancelledPreparationCanBeRetriedAndStaleCompletionIsIgnored() async throws {
        let bridge = TranslationBridge(supported: true)
        bridge.hostConnected = true
        let first = Task { try await bridge.prepare() }
        for _ in 0..<100 where bridge.request == nil { await Task.yield() }
        let old = try #require(bridge.request?.id)
        bridge.cancel()
        do { try await first.value; Issue.record("Cancelled request succeeded") } catch {}
        #expect(bridge.status != .preparing)
        let second = Task { try await bridge.prepare() }
        for _ in 0..<100 where bridge.request == nil { await Task.yield() }
        let current = try #require(bridge.request?.id)
        bridge.complete(id: old, result: .success(""))
        #expect(bridge.request?.id == current)
        bridge.complete(id: current, result: .success(""))
        try await second.value
        #expect(bridge.status.isReady)
    }

    @Test func immediateRetryDoesNotInheritTheCancelledPreparationsStatus() async throws {
        let bridge = TranslationBridge(supported: true)
        bridge.hostConnected = true
        let first = Task { try await bridge.prepare() }
        for _ in 0..<100 where bridge.request == nil { await Task.yield() }
        _ = try #require(bridge.request)
        bridge.cancel()
        let second = Task { try await bridge.prepare() }
        for _ in 0..<100 where bridge.request == nil { await Task.yield() }
        let current = try #require(bridge.request?.id)
        do { try await first.value } catch {}
        #expect(bridge.status == .preparing)
        bridge.complete(id: current, result: .success(""))
        try await second.value
        #expect(bridge.status.isReady)
    }
}
