import AppKit
import CoreText
import CoreVideo
import Foundation
import Testing
@testable import SubVoiceApp

@Suite("English OCR", .timeLimit(.minutes(1)))
struct EnglishOCRTests {
    @Test func englishSubtitlePassesThroughTheConfiguredVisionEngine() throws {
        var optional: CVPixelBuffer?
        CVPixelBufferCreate(nil, 1600, 180, kCVPixelFormatType_32BGRA, nil, &optional)
        let buffer = try #require(optional)
        CVPixelBufferLockBaseAddress(buffer, [])
        let context = try #require(CGContext(
            data: CVPixelBufferGetBaseAddress(buffer), width: 1600, height: 180,
            bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
        ))
        context.setFillColor(CGColor(gray: 0.02, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 1600, height: 180))
        let phrase = "Where are you going?"
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: phrase, attributes: [
            .font: CTFontCreateWithName("Helvetica-Bold" as CFString, 54, nil),
            .foregroundColor: NSColor.white.cgColor,
        ]))
        context.textPosition = CGPoint(x: 100, y: 70)
        CTLineDraw(line, context)
        CVPixelBufferUnlockBaseAddress(buffer, [])
        let finished = DispatchSemaphore(value: 0)
        var observed = ""
        let engine = OCREngine()
        engine.setReadingMode(.englishToVietnamese)
        engine.onText = { text, _ in observed = text; finished.signal() }
        engine.submit(buffer, session: UUID())
        #expect(finished.wait(timeout: .now() + 5) == .success)
        #expect(observed == phrase)
    }
}
