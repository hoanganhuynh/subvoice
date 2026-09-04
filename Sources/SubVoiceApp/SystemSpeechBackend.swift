import AVFoundation
import Foundation
import SubVoiceCore

/// Đọc bằng `AVSpeechSynthesizer` với giọng tiếng Việt offline của macOS.
/// Khoảng 50ms là có tiếng — đây là lý do nó được chọn thay vì engine neural.
final class SystemSpeechBackend: NSObject, SpeechBackend, AVSpeechSynthesizerDelegate {

    var onStart: ((UUID) -> Void)?
    var onFinish: ((UUID) -> Void)?
    var onError: ((UUID, String) -> Void)?

    private let synthesizer = AVSpeechSynthesizer()
    private var voice: AVSpeechSynthesisVoice?
    private var tokensByUtterance: [ObjectIdentifier: UUID] = [:]

    override init() {
        voice = Self.defaultVietnameseVoice()
        super.init()
        synthesizer.delegate = self
    }

    var hasVietnameseVoice: Bool { voice != nil }

    var availableVietnameseVoices: [SpeechVoiceOption] {
        Self.vietnameseVoices().map {
            SpeechVoiceOption(identifier: $0.identifier, name: $0.name)
        }
    }

    /// Chọn một giọng đang cài. Nếu lựa chọn cũ không còn trên máy, quay về
    /// Linh (nếu có) hoặc giọng tiếng Việt đầu tiên.
    @discardableResult
    func selectVoice(identifier: String?) -> String? {
        let voices = Self.vietnameseVoices()
        voice = identifier.flatMap { requested in
            voices.first { $0.identifier == requested }
        } ?? Self.defaultVietnameseVoice(from: voices)
        return voice?.identifier
    }

    func warmUp() {
        guard let voice else { return }
        let utterance = AVSpeechUtterance(string: "a")
        utterance.voice = voice
        utterance.volume = 0
        synthesizer.speak(utterance)
    }

    func speak(_ text: String, rate: Float, volume: Float, token: UUID) {
        guard let voice else { return }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        utterance.rate = rate
        utterance.volume = volume
        utterance.preUtteranceDelay = 0
        utterance.postUtteranceDelay = 0
        tokensByUtterance[ObjectIdentifier(utterance)] = token
        synthesizer.speak(utterance)
    }

    func stop() {
        // Bỏ token trước khi synthesizer phát delegate `didCancel`, để callback
        // của lượt cũ không thể chạm vào activity mới của coordinator.
        tokensByUtterance.removeAll(keepingCapacity: false)
        synthesizer.stopSpeaking(at: .immediate)
    }

    private static func vietnameseVoices() -> [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.lowercased().hasPrefix("vi") }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private static func defaultVietnameseVoice(
        from voices: [AVSpeechSynthesisVoice] = vietnameseVoices()
    ) -> AVSpeechSynthesisVoice? {
        voices.first { $0.identifier == "com.apple.voice.compact.vi-VN.Linh" }
            ?? voices.first
    }

    // MARK: - AVSpeechSynthesizerDelegate

    func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didStart utterance: AVSpeechUtterance
    ) {
        guard utterance.volume > 0,
              let token = tokensByUtterance[ObjectIdentifier(utterance)]
        else { return }   // bỏ qua câu hâm nóng
        onStart?(token)
    }

    func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        let token = tokensByUtterance.removeValue(forKey: ObjectIdentifier(utterance))
        guard utterance.volume > 0, let token else { return }
        onFinish?(token)
    }

    func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didCancel utterance: AVSpeechUtterance
    ) {
        let token = tokensByUtterance.removeValue(forKey: ObjectIdentifier(utterance))
        guard utterance.volume > 0, let token else { return }
        onFinish?(token)
    }
}
