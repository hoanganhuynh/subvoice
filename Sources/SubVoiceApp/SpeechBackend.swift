import Foundation

/// Điểm nối để thay engine đọc. Phase 1 chỉ có `SystemSpeechBackend`;
/// phase 2 sẽ gắn thêm VieNeu-TTS ở đây mà không đụng gì tới các module khác.
protocol SpeechBackend: AnyObject {
    /// Gọi trên main thread khi bắt đầu phát ra tiếng. Dùng để đo độ trễ.
    var onStart: (() -> Void)? { get set }
    /// Gọi trên main thread khi đọc xong một câu.
    var onFinish: (() -> Void)? { get set }

    /// Nạp sẵn tài nguyên để câu đầu tiên không bị trễ thêm.
    func warmUp()
    func speak(_ text: String, rate: Float, volume: Float)
    func stop()
}
