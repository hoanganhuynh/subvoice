import Foundation
import Testing
import SubVoiceUI
@testable import SubVoiceApp

@MainActor
@Suite("Subtitle translation pipeline", .timeLimit(.minutes(1)))
struct SubtitleTranslationPipelineTests {
    @Test func waitingIndicatorClearsWhenACompleteSentenceIsQueuedOrReset() {
        let pipeline = SubtitleTranslationPipeline(translate: { _ in "bản dịch" })
        var waiting: [Bool] = []
        pipeline.onWaitingChange = { waiting.append($0) }
        pipeline.submit("I was going to")
        #expect(waiting == [true])
        pipeline.submit("tell you something.")
        pipeline.endSubtitle()
        #expect(waiting == [true, false])
        pipeline.submit("Another incomplete")
        pipeline.reset()
        #expect(waiting == [true, false, true, false])
    }

    @Test func incompleteTextIsHeldPastBothTimersAndJoinedAcrossBlankFrames() async throws {
        var requests: [String] = []
        let (results, emit) = AsyncStream<String>.makeStream()
        let pipeline = SubtitleTranslationPipeline(
            translate: { text in requests.append(text); return "Tôi định nói với bạn một chuyện." },
            stabilizationDelay: .milliseconds(5), unpunctuatedDelay: .milliseconds(15)
        )
        pipeline.onResult = { source, _ in emit.yield(source) }
        pipeline.submit("I was going to")
        try await Task.sleep(for: .milliseconds(45))
        #expect(requests.isEmpty)
        pipeline.endSubtitle()
        try await Task.sleep(for: .milliseconds(25))
        #expect(requests.isEmpty)
        pipeline.submit("tell you something.")
        var output = results.makeAsyncIterator()
        #expect(await output.next() == "I was going to tell you something.")
        #expect(requests == ["I was going to tell you something."])
        pipeline.reset()
    }

    @Test func unpunctuatedCompleteTextDoesNotWaitForeverForAnotherFrame() async {
        let (results, emit) = AsyncStream<String>.makeStream()
        let pipeline = SubtitleTranslationPipeline(
            translate: { _ in "Tôi không biết" },
            stabilizationDelay: .milliseconds(5), unpunctuatedDelay: .milliseconds(15)
        )
        pipeline.onResult = { source, _ in emit.yield(source) }
        pipeline.submit("I don't know")
        var output = results.makeAsyncIterator()
        #expect(await output.next() == "I don't know")
        pipeline.reset()
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["SUBVOICE_CHECK_TRANSLATION"] == "1"))
    func assembledSentenceReachesTheRealAppleTranslatorAsOneRequest() async throws {
        let bridge = TranslationBridge()
        await bridge.refreshAvailability()
        try #require(bridge.status.isReady)
        let (results, emit) = AsyncStream<(String, String)>.makeStream()
        let pipeline = SubtitleTranslationPipeline(translate: bridge.translate)
        pipeline.onResult = { emit.yield(($0, $1)) }
        pipeline.onError = { error in Issue.record(error); emit.finish() }
        pipeline.submit("I was going to")
        pipeline.endSubtitle()
        pipeline.submit("tell you something.")
        pipeline.endSubtitle()
        var iterator = results.makeAsyncIterator()
        let result = try #require(await iterator.next())
        #expect(result.0 == "I was going to tell you something.")
        #expect(!result.1.isEmpty)
        #expect(result.1 != result.0)
        print("Assembled Apple translation: \(result.0) → \(result.1)")
        pipeline.reset()
    }

    private final class Translator {
        let requests: AsyncStream<(String, CheckedContinuation<String, Error>)>
        let continuation: AsyncStream<(String, CheckedContinuation<String, Error>)>.Continuation
        init() {
            (requests, continuation) = AsyncStream.makeStream()
        }
        func translate(_ text: String) async throws -> String {
            try await withCheckedThrowingContinuation { continuation.yield((text, $0)) }
        }
    }

    @Test func resultsReachSpeechInSourceOrderAndKeepFullText() async throws {
        let translator = Translator()
        let (results, emit) = AsyncStream<(String, String)>.makeStream()
        let pipeline = SubtitleTranslationPipeline(translate: translator.translate)
        pipeline.onResult = { emit.yield(($0, $1)) }
        pipeline.submit("Where are")
        pipeline.submit("Where are you going?")
        pipeline.endSubtitle()
        pipeline.submit("Come back!")
        pipeline.endSubtitle()
        var requests = translator.requests.makeAsyncIterator()
        let first = try #require(await requests.next())
        #expect(first.0 == "Where are you going?")
        first.1.resume(returning: "Bạn đang đi đâu?")
        let second = try #require(await requests.next())
        #expect(second.0 == "Come back!")
        second.1.resume(returning: "Quay lại!")
        var output = results.makeAsyncIterator()
        #expect(await output.next()?.1 == "Bạn đang đi đâu?")
        #expect(await output.next()?.1 == "Quay lại!")
        pipeline.reset()
    }

    @Test func resetDiscardsAnInFlightResultAndQueuedSubtitles() async throws {
        let translator = Translator()
        var output: [String] = []
        let (results, emit) = AsyncStream<String>.makeStream()
        let pipeline = SubtitleTranslationPipeline(translate: translator.translate)
        pipeline.onResult = { _, target in output.append(target); emit.yield(target) }
        pipeline.submit("Old scene.")
        pipeline.endSubtitle()
        pipeline.submit("Queued old scene.")
        pipeline.endSubtitle()
        var requests = translator.requests.makeAsyncIterator()
        let old = try #require(await requests.next())
        pipeline.reset()
        pipeline.submit("New scene.")
        pipeline.endSubtitle()
        let current = try #require(await requests.next())
        #expect(current.0 == "New scene.")
        old.1.resume(returning: "Cảnh cũ.")
        current.1.resume(returning: "Cảnh mới.")
        var iterator = results.makeAsyncIterator()
        #expect(await iterator.next() == "Cảnh mới.")
        #expect(output == ["Cảnh mới."])
        pipeline.reset()
    }

    @Test func failedOrEmptyTranslationNeverFallsBackToSpeakingEnglish() async throws {
        let pipeline = SubtitleTranslationPipeline(translate: { _ in "  " })
        let (errors, emit) = AsyncStream<String>.makeStream()
        var output: [String] = []
        pipeline.onResult = { _, text in output.append(text) }
        pipeline.onError = { emit.yield($0.localizedDescription) }
        pipeline.submit("Do not read this in English.")
        pipeline.endSubtitle()
        var iterator = errors.makeAsyncIterator()
        #expect(await iterator.next() != nil)
        #expect(output.isEmpty)
        pipeline.reset()
    }
}
