import Foundation

/// Điểm nối để thay engine đọc. Phase 1 chỉ có `SystemSpeechBackend`;
/// phase 2 sẽ gắn thêm VieNeu-TTS ở đây mà không đụng gì tới các module khác.
protocol SpeechBackend: AnyObject {
    /// Gọi trên main thread khi bắt đầu phát ra tiếng. Dùng để đo độ trễ.
    var onStart: ((UUID) -> Void)? { get set }
    /// Gọi trên main thread khi đọc xong một câu.
    var onFinish: ((UUID) -> Void)? { get set }
    /// Gọi khi backend không thể tạo hoặc phát âm thanh.
    var onError: ((UUID, String) -> Void)? { get set }

    /// Nạp sẵn tài nguyên để câu đầu tiên không bị trễ thêm.
    func warmUp()
    /// `token` gắn callback với đúng lượt đọc đã tạo nó. Backend có thể gửi
    /// callback trễ sau `stop()`; coordinator sẽ bỏ callback đó thay vì để nó
    /// làm thay đổi trạng thái của lượt đọc mới.
    func speak(_ text: String, rate: Float, volume: Float, token: UUID)
    func stop()
}
