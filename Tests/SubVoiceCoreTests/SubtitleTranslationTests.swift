import Foundation
import Testing
@testable import SubVoiceCore

@Suite("English subtitle preparation")
struct SubtitleTranslationTests {
    @Test(arguments: ["No", "No."])
    func standaloneNoIsReadInsteadOfWaitingForAnotherSentence(_ text: String) {
        var buffer = SubtitleTextBuffer()
        _ = buffer.submit(text)
        #expect(buffer.endSubtitle() == text)
        _ = buffer.submit("Yes.")
        #expect(buffer.flush() == "Yes.")
    }

    @Test func numberedNoIsAnAbbreviationAndNotAStandaloneReply() {
        var buffer = SubtitleTextBuffer()
        _ = buffer.submit("No. 5 is missing.")
        #expect(buffer.flush() == "No. 5 is missing.")
    }

    @Test func punctuationSpacingDoesNotRepeatSpeechButChangedNumbersRemainDistinct() {
        var buffer = SubtitleTextBuffer()
        _ = buffer.submit("Where are you going?")
        #expect(buffer.flush() == "Where are you going?")
        _ = buffer.submit("Where are you going ?")
        #expect(buffer.flush() == nil)
        _ = buffer.submit("Meet at 8:00 .")
        #expect(buffer.flush() == "Meet at 8:00.")
        _ = buffer.submit("Meet at 9:00 .")
        #expect(buffer.flush() == "Meet at 9:00.")
    }

    @Test(arguments: ["I think that you", "I thought that he", "She said that we", "I believe that they"])
    func complementizerWithAnUnfinishedSubjectIsHeld(_ text: String) {
        var buffer = SubtitleTextBuffer()
        _ = buffer.submit(text)
        #expect(buffer.flush(allowUnpunctuated: true) == nil)
        #expect(buffer.endSubtitle() == nil)
        _ = buffer.submit("should leave.")
        #expect(buffer.flush() == text + " should leave.")
    }

    @Test(arguments: ["When are we leaving", "The reason I called is to help", "How are you",
                      "What are you looking for", "Who did you talk to"])
    func completeQuestionsAndMatrixClausesDoNotGetStuck(_ text: String) {
        var buffer = SubtitleTextBuffer()
        _ = buffer.submit(text)
        #expect(buffer.flush(allowUnpunctuated: true) == text)
    }

    @Test(arguments: ["The price is 3.5.", "I'm in the U.S. now.", "Are you sure?",
                      "He said, \"Go.\"", "We're done (for now)."])
    func completePunctuationDoesNotLoseDecimalsQuotesOrBrackets(_ text: String) {
        var buffer = SubtitleTextBuffer()
        _ = buffer.submit(text)
        #expect(buffer.flush() == text)
    }

    @Test func growingSecondCueUpdatesTheContinuationRatherThanRepeatingIt() {
        var buffer = SubtitleTextBuffer()
        _ = buffer.submit("I was going to")
        _ = buffer.endSubtitle()
        _ = buffer.submit("tell you")
        _ = buffer.submit("tell you something.")
        #expect(buffer.flush() == "I was going to tell you something.")
    }

    @Test(arguments: ["I wanted", "I was going to", "I would like to", "I was about to",
                      "If you see him", "Although she left", "The reason I called", "I think you"])
    func obviouslyUnfinishedTextIsNotForcedOutByAnIdleTimeout(_ text: String) {
        var buffer = SubtitleTextBuffer()
        _ = buffer.submit(text)
        #expect(buffer.flush(allowUnpunctuated: true) == nil)
    }

    @Test(arguments: ["I don't know", "Thank you", "I need help", "We should leave now"])
    func aStandaloneUnpunctuatedUtteranceCanEventuallyBeRead(_ text: String) {
        var buffer = SubtitleTextBuffer()
        _ = buffer.submit(text)
        #expect(buffer.flush() == nil)
        #expect(buffer.flush(allowUnpunctuated: true) == text)
    }

    @Test func incompleteClauseSurvivesIdleAndBlankUntilTheNextCueCompletesIt() {
        var buffer = SubtitleTextBuffer()
        _ = buffer.submit("I was going to")
        #expect(buffer.flush() == nil)
        #expect(buffer.endSubtitle() == nil)
        #expect(buffer.submit("tell you something.").isEmpty)
        #expect(buffer.flush() == "I was going to tell you something.")
    }

    @Test func dependentClauseAndEllipsisAreJoinedAcrossCues() {
        var buffer = SubtitleTextBuffer()
        _ = buffer.submit("If you want to go home,")
        #expect(buffer.endSubtitle() == nil)
        _ = buffer.submit("you need to leave now.")
        #expect(buffer.flush() == "If you want to go home, you need to leave now.")
        buffer.reset()
        _ = buffer.submit("I was thinking...")
        #expect(buffer.flush() == nil)
        _ = buffer.submit("...that we could leave tomorrow.")
        #expect(buffer.flush() == "I was thinking that we could leave tomorrow.")
    }

    @Test func aCompletePrefixIsReadWhileTheTrailingFragmentWaits() {
        var buffer = SubtitleTextBuffer()
        _ = buffer.submit("I can't stay. Because I have")
        #expect(buffer.flush() == "I can't stay.")
        #expect(buffer.endSubtitle() == nil)
        _ = buffer.submit("to catch the last train.")
        #expect(buffer.flush() == "Because I have to catch the last train.")
    }

    @Test func aNewShortReplyOrChangedNumberIsNotMistakenForOCRNoise() {
        var buffer = SubtitleTextBuffer()
        _ = buffer.submit("He said Yes.")
        #expect(buffer.flush() == "He said Yes.")
        _ = buffer.submit("Yes.")
        #expect(buffer.flush() == "Yes.")
        _ = buffer.submit("We meet at 8:00.")
        #expect(buffer.flush() == "We meet at 8:00.")
        _ = buffer.submit("We meet at 9:00.")
        #expect(buffer.flush() == "We meet at 9:00.")
    }

    @Test func abbreviationAndDecimalDoNotEndTheSentence() {
        var buffer = SubtitleTextBuffer()
        _ = buffer.submit("Dr.")
        #expect(buffer.flush() == nil)
        _ = buffer.submit("Smith paid 3.5 dollars.")
        #expect(buffer.flush() == "Dr. Smith paid 3.5 dollars.")
    }

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
