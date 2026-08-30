import Testing
import Foundation
@testable import SubVoiceCore

/// Dựng buffer BGRA tổng hợp. `fill` trả về (b, g, r) cho từng toạ độ pixel.
private func makeBGRA(
    width: Int,
    height: Int,
    fill: (Int, Int) -> (UInt8, UInt8, UInt8)
) -> [UInt8] {
    var bytes = [UInt8](repeating: 0, count: width * height * 4)
    for y in 0..<height {
        for x in 0..<width {
            let (b, g, r) = fill(x, y)
            let i = (y * width + x) * 4
            bytes[i] = b
            bytes[i + 1] = g
            bytes[i + 2] = r
            bytes[i + 3] = 255
        }
    }
    return bytes
}

/// Nền video tối trung bình, có nhiễu để mô phỏng chuyển động giữa các khung.
private func darkVideoFrame(seed: Int, width: Int, height: Int) -> [UInt8] {
    makeBGRA(width: width, height: height) { x, y in
        let v = UInt8((x &* 7 &+ y &* 13 &+ seed &* 29) % 90)
        return (v, v, v)
    }
}

/// Nền video tối, cộng thêm một dải chữ trắng ở giữa.
private func frameWithText(
    seed: Int,
    width: Int,
    height: Int,
    textColumns: Range<Int>
) -> [UInt8] {
    makeBGRA(width: width, height: height) { x, y in
        let inTextBand = y > height / 3 && y < height * 2 / 3
        let onGlyphStroke = textColumns.contains(x) && x % 3 != 0
        if inTextBand && onGlyphStroke {
            return (250, 250, 250)
        }
        let v = UInt8((x &* 7 &+ y &* 13 &+ seed &* 29) % 90)
        return (v, v, v)
    }
}

private func signature(_ bytes: [UInt8], width: Int, height: Int) -> BrightnessSignature {
    bytes.withUnsafeBufferPointer { buffer in
        ChangeDetector.signature(
            bgra: buffer.baseAddress!,
            width: width,
            height: height,
            bytesPerRow: width * 4
        )
    }
}

@Test func movingVideoWithoutTextReportsBlank() {
    let w = 240, h = 60
    var detector = ChangeDetector()

    // Nền video đổi liên tục nhưng không có chữ -> phải luôn là .blank,
    // KHÔNG được kích hoạt OCR. Đây chính là lỗi mà thiết kế này tồn tại để tránh.
    let verdicts = (0..<5).map { seed in
        detector.evaluate(signature(darkVideoFrame(seed: seed, width: w, height: h), width: w, height: h))
    }

    #expect(verdicts.allSatisfy { $0 == .blank })
}

@Test func textAppearingReportsChanged() {
    let w = 240, h = 60
    var detector = ChangeDetector()

    _ = detector.evaluate(signature(darkVideoFrame(seed: 0, width: w, height: h), width: w, height: h))
    let verdict = detector.evaluate(
        signature(frameWithText(seed: 1, width: w, height: h, textColumns: 40..<200), width: w, height: h)
    )

    #expect(verdict == .changed)
}

@Test func sameTextOverMovingVideoReportsUnchanged() {
    let w = 240, h = 60
    var detector = ChangeDetector()

    // Cùng một câu phụ đề, nhưng nền video phía sau đã đổi (seed khác nhau).
    _ = detector.evaluate(
        signature(frameWithText(seed: 1, width: w, height: h, textColumns: 40..<200), width: w, height: h)
    )
    let verdict = detector.evaluate(
        signature(frameWithText(seed: 2, width: w, height: h, textColumns: 40..<200), width: w, height: h)
    )

    #expect(verdict == .unchanged)
}

@Test func differentTextReportsChanged() {
    let w = 240, h = 60
    var detector = ChangeDetector()

    _ = detector.evaluate(
        signature(frameWithText(seed: 1, width: w, height: h, textColumns: 40..<200), width: w, height: h)
    )
    let verdict = detector.evaluate(
        signature(frameWithText(seed: 1, width: w, height: h, textColumns: 10..<80), width: w, height: h)
    )

    #expect(verdict == .changed)
}

@Test func textDisappearingReportsBlank() {
    let w = 240, h = 60
    var detector = ChangeDetector()

    _ = detector.evaluate(
        signature(frameWithText(seed: 1, width: w, height: h, textColumns: 40..<200), width: w, height: h)
    )
    let verdict = detector.evaluate(
        signature(darkVideoFrame(seed: 2, width: w, height: h), width: w, height: h)
    )

    #expect(verdict == .blank)
}

@Test func resetForcesNextFrameToBeChanged() {
    let w = 240, h = 60
    var detector = ChangeDetector()
    let frame = frameWithText(seed: 1, width: w, height: h, textColumns: 40..<200)

    _ = detector.evaluate(signature(frame, width: w, height: h))
    #expect(detector.evaluate(signature(frame, width: w, height: h)) == .unchanged)

    detector.reset()
    #expect(detector.evaluate(signature(frame, width: w, height: h)) == .changed)
}

@Test func signatureHasConfiguredColumnCount() {
    let w = 240, h = 60
    let sig = signature(darkVideoFrame(seed: 0, width: w, height: h), width: w, height: h)

    #expect(sig.columns.count == DetectorTuning.columnCount)
}
