import CoreVideo
import Foundation
import Testing
@testable import SubVoiceApp

@Suite("Deferred OCR", .timeLimit(.minutes(1)))
struct CaptureQueueStateTests {
    private func frame() throws -> CVPixelBuffer {
        var result: CVPixelBuffer?
        CVPixelBufferCreate(nil, 32, 32, kCVPixelFormatType_32BGRA, nil, &result)
        return try #require(result)
    }

    @Test func throttledFrameIsSubmittedEvenWithoutAnotherFrame() throws {
        let state = CaptureQueueState()
        let queue = DispatchQueue(label: "test.capture.deferred")
        let session = UUID()
        let first = try frame(), second = try frame(), latest = try frame()
        let done = DispatchSemaphore(value: 0)
        var received: [CVPixelBuffer] = []
        queue.sync {
            state.session = session
            let callback: (CVPixelBuffer, UUID) -> Void = { frame, token in
                #expect(token == session)
                received.append(frame)
                if received.count == 2 { done.signal() }
            }
            state.submit(first, on: queue, perform: callback)
            state.submit(second, on: queue, perform: callback)
            state.submit(latest, on: queue, perform: callback)
        }
        #expect(done.wait(timeout: .now() + 2) == .success)
        queue.sync {
            #expect(received.count == 2)
            #expect(received.first === first)
            #expect(received.last === latest)
        }
    }

    @Test func resettingTheSessionCancelsDeferredFrames() throws {
        let state = CaptureQueueState()
        let queue = DispatchQueue(label: "test.capture.reset")
        let buffer = try frame()
        let drained = DispatchSemaphore(value: 0)
        var count = 0
        queue.sync {
            state.session = UUID()
            let callback: (CVPixelBuffer, UUID) -> Void = { _, _ in count += 1 }
            state.submit(buffer, on: queue, perform: callback)
            state.submit(buffer, on: queue, perform: callback)
            state.reset()
            state.session = UUID()
            queue.asyncAfter(deadline: .now() + 0.2) { drained.signal() }
        }
        #expect(drained.wait(timeout: .now() + 2) == .success)
        queue.sync { #expect(count == 1) }
    }
}
