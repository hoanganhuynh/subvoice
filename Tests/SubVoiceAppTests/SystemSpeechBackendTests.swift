import AVFoundation
import Foundation
import Testing
@testable import SubVoiceApp

@MainActor
@Suite("System speech callbacks")
struct SystemSpeechBackendTests {
    @Test func mutedSpeechStillStartsAndFinishesItsToken() {
        let backend = SystemSpeechBackend()
        let synthesizer = AVSpeechSynthesizer()
        let token = UUID()
        var started: [UUID] = [], finished: [UUID] = []
        backend.onStart = { started.append($0) }
        backend.onFinish = { finished.append($0) }
        let utterance = backend.makeUtterance("muted", voice: nil, rate: 0.55, volume: 0, token: token)
        backend.speechSynthesizer(synthesizer, didStart: utterance)
        backend.speechSynthesizer(synthesizer, didFinish: utterance)
        backend.speechSynthesizer(synthesizer, didFinish: utterance)
        #expect(started == [token])
        #expect(finished == [token])
    }

    @Test func mutedSpeechCancellationFinishesButWarmUpIsIgnored() {
        let backend = SystemSpeechBackend()
        let synthesizer = AVSpeechSynthesizer()
        let token = UUID()
        var finished: [UUID] = []
        backend.onFinish = { finished.append($0) }
        let warmUp = AVSpeechUtterance(string: "a")
        warmUp.volume = 0
        backend.speechSynthesizer(synthesizer, didFinish: warmUp)
        #expect(finished.isEmpty)
        let utterance = backend.makeUtterance("muted", voice: nil, rate: 0.55, volume: 0, token: token)
        backend.speechSynthesizer(synthesizer, didCancel: utterance)
        #expect(finished == [token])
    }
}
