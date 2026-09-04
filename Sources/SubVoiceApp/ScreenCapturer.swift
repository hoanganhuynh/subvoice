import ScreenCaptureKit
import CoreMedia
import CoreVideo
import Foundation
import SubVoiceCore

/// Bọc `SCStream`, phát ra các khung hình BGRA của riêng vùng đã chọn.
///
/// Hệ điều hành cắt sẵn vùng ở tầng compositor qua `sourceRect`, nên không bao
/// giờ phải chụp toàn màn hình rồi crop.
final class ScreenCapturer: NSObject, SCStreamOutput, SCStreamDelegate {

    enum CaptureError: LocalizedError {
        case displayNotFound(UInt32)

        var errorDescription: String? {
            switch self {
            case .displayNotFound(let id):
                return "Không tìm thấy màn hình \(id). Vùng đã chọn có thể thuộc về màn hình đã rút."
            }
        }
    }

    /// Gọi trên `captureQueue`, KHÔNG phải main thread.
    var onFrame: ((CVPixelBuffer) -> Void)?
    /// Gọi trên main thread khi đã thử khởi động lại hết số lần cho phép.
    var onFatalError: ((String) -> Void)?

    let captureQueue = DispatchQueue(label: "com.williens.subvoice.capture", qos: .userInteractive)

    private var stream: SCStream?
    private var region: SelectedRegion?
    private var restartAttempt = 0
    private static let maxRestartAttempts = 5

    func start(region: SelectedRegion) async throws {
        self.region = region
        try await startStream(region: region)
        restartAttempt = 0
    }

    func stop() {
        let current = stream
        stream = nil
        region = nil
        restartAttempt = 0
        Task { try? await current?.stopCapture() }
    }

    private func startStream(region: SelectedRegion) async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(
            false,
            onScreenWindowsOnly: false
        )
        guard let display = content.displays.first(where: { $0.displayID == region.displayID })
        else { throw CaptureError.displayNotFound(region.displayID) }

        // Loại chính app khỏi filter để không bao giờ bắt phải overlay của mình.
        let ownApp = content.applications.first {
            $0.bundleIdentifier == Bundle.main.bundleIdentifier
        }
        let filter = SCContentFilter(
            display: display,
            excludingApplications: ownApp.map { [$0] } ?? [],
            exceptingWindows: []
        )

        let config = SCStreamConfiguration()
        config.sourceRect = region.rect
        config.width = region.pixelWidth
        config.height = region.pixelHeight
        config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.queueDepth = 3
        config.showsCursor = false
        config.capturesAudio = false

        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: captureQueue)
        try await stream.startCapture()
        self.stream = stream
    }

    // MARK: - SCStreamOutput

    func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of type: SCStreamOutputType
    ) {
        guard type == .screen, sampleBuffer.isValid else { return }

        // Hệ điều hành tự đánh dấu khung .idle/.blank khi không có gì đổi.
        // Đây là bộ lọc miễn phí, nhưng KHÔNG thay được ChangeDetector vì
        // video vẫn đang chạy phía sau chữ.
        guard
            let attachments = CMSampleBufferGetSampleAttachmentsArray(
                sampleBuffer, createIfNecessary: false
            ) as? [[SCStreamFrameInfo: Any]],
            let rawStatus = attachments.first?[.status] as? Int,
            SCFrameStatus(rawValue: rawStatus) == .complete,
            let pixelBuffer = sampleBuffer.imageBuffer
        else { return }

        onFrame?(pixelBuffer)
    }

    // MARK: - SCStreamDelegate

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        guard let region, restartAttempt < Self.maxRestartAttempts else {
            let message = "Luồng bắt màn hình dừng: \(error.localizedDescription)"
            DispatchQueue.main.async { [weak self] in self?.onFatalError?(message) }
            return
        }

        restartAttempt += 1
        let backoff = [0.5, 1.0, 2.0, 3.0, 5.0][min(restartAttempt - 1, 4)]

        Task { [weak self] in
            try? await Task.sleep(for: .seconds(backoff))
            guard let self else { return }
            do {
                try await self.startStream(region: region)
            } catch {
                let message = "Không khởi động lại được: \(error.localizedDescription)"
                await MainActor.run { self.onFatalError?(message) }
            }
        }
    }
}
