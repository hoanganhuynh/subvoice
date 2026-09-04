import Foundation
import Testing
@testable import SubVoiceCore

@Suite("Session transcript")
struct SessionTranscriptTests {
    @Test func newestEntryIsFirst() {
        var history = SessionTranscript()
        history.append(text: "Câu một", at: Date(timeIntervalSince1970: 1))
        history.append(text: "Câu hai", at: Date(timeIntervalSince1970: 2))
        #expect(history.entries.map(\.text) == ["Câu hai", "Câu một"])
    }

    @Test func historyKeepsOnlyTwoHundredEntries() {
        var history = SessionTranscript()
        for index in 0..<205 {
            history.append(text: "Câu \(index)", at: Date(timeIntervalSince1970: Double(index)))
        }
        #expect(history.entries.count == 200)
        #expect(history.entries.first?.text == "Câu 204")
        #expect(history.entries.last?.text == "Câu 5")
    }

    @Test func matchingIsCaseInsensitiveAndWhitespaceSafe() {
        var history = SessionTranscript()
        history.append(text: "Xin Chào", at: .now)
        history.append(text: "Tạm biệt", at: .now)
        #expect(history.matching(" chào ").map(\.text) == ["Xin Chào"])
        #expect(history.matching("   ") == history.entries)
    }

    @Test func clearRemovesFilteredAndUnfilteredEntries() {
        var history = SessionTranscript()
        history.append(text: "Một", at: .now)
        history.append(text: "Hai", at: .now)
        #expect(history.matching("hai").count == 1)
        history.clear()
        #expect(history.entries.isEmpty)
        #expect(history.matching("hai").isEmpty)
    }
}
