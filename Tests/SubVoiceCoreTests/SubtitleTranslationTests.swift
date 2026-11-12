import Foundation
import Testing
@testable import SubVoiceCore

@Suite("English subtitle preparation")
struct SubtitleTranslationTests {
    @Test func readingModeMigratesAndPersistsWithoutChangingVoice() throws {
        let old = Data(#"{"storedRate":0.625,"storedVolume":0.75}"#.utf8)
        var settings = try JSONDecoder().decode(Settings.self, from: old)
        #expect(settings.readingMode == .vietnamese)
        settings.readingMode = .englishToVietnamese
        let restored = try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(settings))
        #expect(restored.readingMode == .englishToVietnamese)
        #expect(restored.speechRate == 0.625)
        #expect(restored.volume == 0.75)
        let invalid = Data(#"{"storedReadingMode":"unknown","storedVolume":0.5}"#.utf8)
        #expect(try JSONDecoder().decode(Settings.self, from: invalid).volume == 0.5)
    }

    @Test func fadeInProducesTheWholeSubtitleRatherThanItsSuffix() {
        var buffer = SubtitleTextBuffer()
        #expect(buffer.submit("Where are").isEmpty)
        #expect(buffer.submit("Where are you going?").isEmpty)
        #expect(buffer.flush() == "Where are you going?")
        #expect(buffer.submit("Where are you going?").isEmpty)
        #expect(buffer.flush() == nil)
    }

    @Test func replacingSubtitleFlushesPreviousAndBlankAllowsRepeatedDialogue() {
        var buffer = SubtitleTextBuffer()
        _ = buffer.submit("Hello there.")
        #expect(buffer.submit("Please come in.") == ["Hello there."])
        #expect(buffer.endSubtitle() == "Please come in.")
        _ = buffer.submit("Please come in.")
        #expect(buffer.flush() == "Please come in.")
    }

    @Test func noiseAndResetDoNotLeakAnOldSubtitle() {
        var buffer = SubtitleTextBuffer()
        #expect(buffer.submit(" | — ").isEmpty)
        _ = buffer.submit("An old sentence")
        buffer.reset()
        #expect(buffer.flush() == nil)
    }

    @Test func shorterOCRFrameDoesNotTruncateTheSentenceBeingAssembled() {
        var buffer = SubtitleTextBuffer()
        _ = buffer.submit("Where are you going?")
        _ = buffer.submit("Where are you")
        #expect(buffer.flush() == "Where are you going?")
    }

    @Test func missingLeadingWordsAreNotTranslatedAsASeparateSuffix() {
        var buffer = SubtitleTextBuffer()
        _ = buffer.submit("Where are you going?")
        #expect(buffer.submit("are you going?").isEmpty)
        #expect(buffer.flush() == "Where are you going?")
        #expect(buffer.submit("you going?").isEmpty)
        #expect(buffer.flush() == nil)
    }

    @Test func suffixFirstAndOverlappingFramesKeepOneCompleteSentence() {
        var buffer = SubtitleTextBuffer()
        _ = buffer.submit("are you going?")
        #expect(buffer.submit("Where are you going?").isEmpty)
        #expect(buffer.flush() == "Where are you going?")
        buffer.reset()
        _ = buffer.submit("Where are you")
        #expect(buffer.submit("are you going?").isEmpty)
        #expect(buffer.flush() == "Where are you going?")
    }

    @Test func ocrFramesFromBeforePauseAreRejectedAfterResume() {
        var session = OCRDeliverySession()
        let beforePause = session.begin()
        #expect(session.accepts(beforePause))
        session.invalidate()
        #expect(!session.accepts(beforePause))
        let afterResume = session.begin()
        #expect(!session.accepts(beforePause))
        #expect(session.accepts(afterResume))
    }

    @Test func bilingualHistorySearchesBothTextsButCopiesVietnamese() {
        var history = SessionTranscript()
        history.append(text: "Bạn đang đi đâu?", sourceText: "Where are you going?")
        #expect(history.matching("where").first?.text == "Bạn đang đi đâu?")
        #expect(history.matching("đi đâu").first?.sourceText == "Where are you going?")
    }
}
