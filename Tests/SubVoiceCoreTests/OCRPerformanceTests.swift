import Testing
import Vision
import CoreGraphics
import CoreText
import AppKit
@testable import SubVoiceCore

/// Render một dải phụ đề tổng hợp: chữ trắng đậm trên nền tối.
private func renderSubtitle(_ text: String, width: Int, height: Int, fontSize: CGFloat) -> CGImage {
    let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.setFillColor(CGColor(red: 0.05, green: 0.05, blue: 0.06, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))

    let font = CTFontCreateWithName("Helvetica-Bold" as CFString, fontSize, nil)
    let attributed = NSAttributedString(string: text, attributes: [
        .font: font,
        .foregroundColor: NSColor(calibratedWhite: 0.97, alpha: 1).cgColor,
    ])
    let line = CTLineCreateWithAttributedString(attributed)
    let bounds = CTLineGetBoundsWithOptions(line, [])
    context.textPosition = CGPoint(
        x: (CGFloat(width) - bounds.width) / 2,
        y: CGFloat(height) / 2 - fontSize * 0.35
    )
    CTLineDraw(line, context)
    return context.makeImage()!
}

private func recognize(_ image: CGImage) -> (text: String, milliseconds: Double) {
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.recognitionLanguages = ["vi-VT"]
    request.usesLanguageCorrection = true

    let start = CFAbsoluteTimeGetCurrent()
    try? VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
    let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000

    let lines = (request.results ?? []).compactMap { observation -> OCRLine? in
        guard let candidate = observation.topCandidates(1).first else { return nil }
        return OCRLine(
            text: candidate.string,
            confidence: candidate.confidence,
            midY: observation.boundingBox.midY,
            minX: observation.boundingBox.minX
        )
    }
    return (OCRAssembler.assemble(lines), elapsed)
}

private let samples = [
    "Tôi không nghĩ chúng ta còn nhiều thời gian đâu.",
    "Anh ấy đã rời khỏi thành phố từ sáng sớm hôm qua.",
    "Đừng nói với ai về chuyện này, được chứ?",
]

@Test func visionSupportsVietnameseAtAccurateLevel() throws {
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    let languages = try request.supportedRecognitionLanguages()

    // Apple dùng mã "vi-VT", không phải "vi-VN". Sai mã thì OCR âm thầm
    // rơi về tiếng Anh và mọi dấu thanh sẽ hỏng.
    #expect(languages.contains("vi-VT"))
}

@Test func recognizesVietnameseDiacriticsExactly() {
    for sample in samples {
        let image = renderSubtitle(sample, width: 2400, height: 220, fontSize: 68)
        #expect(recognize(image).text == sample)
    }
}

@Test func warmOCRStaysUnder150Milliseconds() {
    let images = samples.map { renderSubtitle($0, width: 2400, height: 220, fontSize: 68) }

    // Hâm nóng: lần OCR đầu tiên tốn ~540ms vì phải nạp model.
    _ = recognize(images[0])

    var timings: [Double] = []
    for _ in 0..<5 {
        for image in images {
            timings.append(recognize(image).milliseconds)
        }
    }

    let average = timings.reduce(0, +) / Double(timings.count)
    #expect(average < 150, "OCR trung binh \(average)ms, ngan sach do tre la 150ms")
}
