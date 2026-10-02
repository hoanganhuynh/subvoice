import CoreVideo
import Foundation
import Testing
@testable import SubVoiceApp

@Suite("OCR sessions", .timeLimit(.minutes(1)))
struct OCRSessionTests {
    @Test func inFlightOCRKeepsItsOriginalSessionAfterReset() throws {
        var buffer: CVPixelBuffer?
        CVPixelBufferCreate(nil, 32, 32, kCVPixelFormatType_32BGRA, nil, &buffer)
        let frame = try #require(buffer)
        let started = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        let finished = DispatchSemaphore(value: 0)
        let old = UUID(), current = UUID()
        var calls = 0
        let engine = OCREngine { _ in
            calls += 1
            if calls == 1 {
                started.signal()
                _ = release.wait(timeout: .now() + 2)
            }
            return "sentence"
        }
        let lock = NSLock()
        var sessions: [UUID] = []
        engine.onText = { _, session in
            lock.lock()
            sessions.append(session)
            let done = sessions.count == 2
            lock.unlock()
            if done { finished.signal() }
        }
        engine.submit(frame, session: old)
        #expect(started.wait(timeout: .now() + 2) == .success)
        engine.reset()
        engine.submit(frame, session: current)
        release.signal()
        #expect(finished.wait(timeout: .now() + 2) == .success)
        lock.lock()
        let observed = sessions
        lock.unlock()
        #expect(observed == [old, current])
        // Coordinator chỉ nhận token phiên hiện tại, nên kết quả đang chạy cũ bị loại.
        #expect(observed.filter { $0 == current } == [current])
    }
}
