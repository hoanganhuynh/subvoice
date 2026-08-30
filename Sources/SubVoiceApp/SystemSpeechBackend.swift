import AVFoundation
import Foundation

/// Đọc bằng `AVSpeechSynthesizer` với giọng tiếng Việt offline của macOS.
/// Khoảng 50ms là có tiếng — đây là lý do nó được chọn thay vì engine neural.
final class SystemSpeechBackend: NSObject, SpeechBackend, AVSpeechSynthesizerDelegate {

    var onStart: (() -> Void)?
    var onFinish: (() -> Void)?

    private let synthesizer = AVSpeechSynthesizer()
    private let voice: AVSpeechSynthesisVoice?

    override init() {
        voice = AVSpeechSynthesisVoice(identifier: "com.apple.voice.compact.vi-VN.Linh")
            ?? AVSpeechSynthesisVoice(language: "vi-VN")
        super.init()
        synthesizer.delegate = self
    }

    var hasVietnameseVoice: Bool { voice != nil }

    func warmUp() {
        guard let voice else { return }
        let utterance = AVSpeechUtterance(string: "a")
        utterance.voice = voice
        utterance.volume = 0
        synthesizer.speak(utterance)
    }

    func speak(_ text: String, rate: Float, volume: Float) {
        guard let voice else { return }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        utterance.rate = rate
        utterance.volume = volume
        utterance.preUtteranceDelay = 0
        utterance.postUtteranceDelay = 0
        synthesizer.speak(utterance)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }

    // MARK: - AVSpeechSynthesizerDelegate

    func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didStart utterance: AVSpeechUtterance
    ) {
        guard utterance.volume > 0 else { return }   // bỏ qua câu hâm nóng
        onStart?()
    }

    func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        guard utterance.volume > 0 else { return }
        onFinish?()
    }

    func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didCancel utterance: AVSpeechUtterance
    ) {
        guard utterance.volume > 0 else { return }
        onFinish?()
    }
}
