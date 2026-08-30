import Vision
import CoreVideo
import Foundation
import SubVoiceCore

/// Bọc Vision. Luôn OCR khung MỚI NHẤT, khung cũ bị vứt bỏ chứ không xếp hàng —
/// đang xem phim thì khung cũ không còn giá trị gì.
final class OCREngine {

    /// Gọi trên hàng đợi nội bộ, KHÔNG phải main thread. Chuỗi có thể rỗng.
    var onText: ((String) -> Void)?

    private let queue = DispatchQueue(label: "com.williens.subvoice.ocr", qos: .userInteractive)
    private let lock = NSLock()
    private var busy = false
    private var pendingFrame: CVPixelBuffer?

    /// Lần OCR đầu tiên tốn ~540ms vì phải nạp model, các lần sau ~90ms.
    /// KHÔNG bỏ bước này, nếu không câu phụ đề đầu tiên sẽ trễ hơn nửa giây.
    func warmUp() {
        queue.async {
            var buffer: CVPixelBuffer?
            CVPixelBufferCreate(nil, 32, 32, kCVPixelFormatType_32BGRA, nil, &buffer)
            guard let buffer else { return }
            _ = Self.recognize(buffer)
        }
    }

    func submit(_ frame: CVPixelBuffer) {
        lock.lock()
        if busy {
            pendingFrame = frame      // ghi đè: chỉ giữ đúng một khung mới nhất
            lock.unlock()
            return
        }
        busy = true
        lock.unlock()

        queue.async { [weak self] in self?.process(frame) }
    }

    func reset() {
        lock.lock()
        pendingFrame = nil
        lock.unlock()
    }

    private func process(_ frame: CVPixelBuffer) {
        var current: CVPixelBuffer? = frame
        while let buffer = current {
            onText?(Self.recognize(buffer))

            lock.lock()
            current = pendingFrame
            pendingFrame = nil
            if current == nil { busy = false }
            lock.unlock()
        }
    }

    private static func recognize(_ buffer: CVPixelBuffer) -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate       // .fast KHÔNG có tiếng Việt
        request.recognitionLanguages = ["vi-VT"]   // đúng là "vi-VT", không phải "vi-VN"
        request.usesLanguageCorrection = true
        request.minimumTextHeight = 0.05

        let handler = VNImageRequestHandler(cvPixelBuffer: buffer, options: [:])
        try? handler.perform([request])

        let lines = (request.results ?? []).compactMap { observation -> OCRLine? in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            return OCRLine(
                text: candidate.string,
                confidence: candidate.confidence,
                midY: observation.boundingBox.midY,
                minX: observation.boundingBox.minX
            )
        }
        return OCRAssembler.assemble(lines)
    }
}
