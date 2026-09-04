import AppKit
import ScreenCaptureKit
import CoreMedia
import CoreVideo
import CoreImage
import Vision
import Foundation
import SubVoiceCore

// Công cụ chẩn đoán, không phải sản phẩm cuối. Bắt dải 30% dưới cùng của màn
// hình chính trong vài giây, in ra mọi chuỗi OCR đọc được và lưu một khung PNG
// để mắt người tự kiểm tra xem vùng video có bị DRM làm đen không.

let durationSeconds = CommandLine.arguments.count > 1
    ? Double(CommandLine.arguments[1]) ?? 6.0
    : 6.0
let outputPath = "/tmp/subvoice-probe.png"

final class Probe: NSObject, SCStreamOutput, SCStreamDelegate {
    private var stream: SCStream?
    private var detector = ChangeDetector()
    private var gate = TextGate()
    private var savedFrame = false
    private var frameCount = 0
    private var ocrCount = 0
    private var lastOCR = Date.distantPast
    private let started = Date()
    private let queue = DispatchQueue(label: "probe.capture")

    func run() async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(
            false, onScreenWindowsOnly: false
        )
        guard let display = content.displays.first(where: { $0.displayID == CGMainDisplayID() })
            ?? content.displays.first
        else {
            print("LỖI: không tìm thấy màn hình nào.")
            exit(1)
        }

        let screen = NSScreen.screens.first {
            ($0.deviceDescription[.init("NSScreenNumber")] as? NSNumber)?.uint32Value
                == display.displayID
        }
        let scale = screen?.backingScaleFactor ?? 2

        // Dải 30% dưới cùng, nơi phụ đề gần như luôn nằm.
        let band = CGRect(
            x: 0,
            y: CGFloat(display.height) * 0.70,
            width: CGFloat(display.width),
            height: CGFloat(display.height) * 0.30
        )

        print("Màn hình \(display.displayID): \(display.width)x\(display.height) point, scale \(scale)")
        print("Vùng bắt: \(band)")
        print("Đang bắt trong \(durationSeconds)s — hãy để phim chạy có phụ đề tiếng Việt.\n")

        let config = SCStreamConfiguration()
        config.sourceRect = band
        config.width = Int(band.width * scale)
        config.height = Int(band.height * scale)
        config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.queueDepth = 3
        config.showsCursor = false

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        try await stream.startCapture()
        self.stream = stream
    }

    func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of type: SCStreamOutputType
    ) {
        guard type == .screen, sampleBuffer.isValid,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(
                  sampleBuffer, createIfNecessary: false
              ) as? [[SCStreamFrameInfo: Any]],
              let rawStatus = attachments.first?[.status] as? Int,
              SCFrameStatus(rawValue: rawStatus) == .complete,
              let pixelBuffer = sampleBuffer.imageBuffer
        else { return }

        frameCount += 1
        if !savedFrame {
            savedFrame = true
            savePNG(pixelBuffer, to: outputPath)
            print("Đã lưu khung đầu tiên: \(outputPath)")
        }

        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return }

        let signature = ChangeDetector.signature(
            bgra: base.assumingMemoryBound(to: UInt8.self),
            width: CVPixelBufferGetWidth(pixelBuffer),
            height: CVPixelBufferGetHeight(pixelBuffer),
            bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer)
        )
        let verdict = detector.evaluate(signature)

        if verdict == .blank { gate.clear() }
        guard verdict == .changed else { return }
        guard Date().timeIntervalSince(lastOCR) >= DetectorTuning.minOCRInterval else { return }
        lastOCR = Date()
        ocrCount += 1

        let elapsed = Date().timeIntervalSince(started)
        let text = recognize(pixelBuffer)
        guard case .speak(let spoken) = gate.admit(text) else { return }
        print(String(format: "[%5.2fs] %@", elapsed, spoken))
    }

    private func recognize(_ buffer: CVPixelBuffer) -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["vi-VT"]
        request.usesLanguageCorrection = true
        request.minimumTextHeight = 0.05
        try? VNImageRequestHandler(cvPixelBuffer: buffer, options: [:]).perform([request])

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

    private func savePNG(_ buffer: CVPixelBuffer, to path: String) {
        let ciImage = CIImage(cvPixelBuffer: buffer)
        let context = CIContext()
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return }
        let rep = NSBitmapImageRep(cgImage: cgImage)
        guard let data = rep.representation(using: .png, properties: [:]) else { return }
        try? data.write(to: URL(fileURLWithPath: path))
    }

    func summary() {
        print("\n--- Tổng kết ---")
        print("Khung nhận được: \(frameCount)")
        print("Lần chạy OCR:    \(ocrCount)")
        print("Mở \(outputPath) và kiểm tra bằng mắt:")
        print("  • Nếu vùng video ĐEN nhưng chữ phụ đề vẫn thấy -> vẫn dùng được.")
        print("  • Nếu TOÀN BỘ đen kể cả chữ -> DRM chặn, không xây tiếp được.")
        print("  • Nếu thấy cả hình lẫn chữ -> không có DRM, tốt nhất.")
    }
}

guard CGPreflightScreenCaptureAccess() else {
    print("Chưa có quyền Screen Recording. Đang xin quyền...")
    CGRequestScreenCaptureAccess()
    print("Cấp quyền cho Terminal trong System Settings › Privacy & Security ›")
    print("Screen & System Audio Recording, rồi chạy lại lệnh này.")
    exit(1)
}

let probe = Probe()
Task {
    do {
        try await probe.run()
    } catch {
        print("LỖI: \(error.localizedDescription)")
        exit(1)
    }
    try? await Task.sleep(for: .seconds(durationSeconds))
    probe.summary()
    exit(0)
}
RunLoop.main.run()
