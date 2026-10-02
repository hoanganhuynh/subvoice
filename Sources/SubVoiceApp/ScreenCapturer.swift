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

    let captureQueue: DispatchQueue

    init(captureQueue: DispatchQueue = DispatchQueue(
        label: "com.williens.subvoice.capture", qos: .userInteractive
    )) {
        self.captureQueue = captureQueue
        super.init()
    }

    private let streamLock = NSLock()
    private var stream: SCStream?
    @MainActor private var generation = UUID()
    @MainActor private var restartTask: Task<Void, Never>?
    @MainActor private var region: SelectedRegion?
    @MainActor private var restartAttempt = 0
    private static let maxRestartAttempts = 5

    @MainActor
    func start(region: SelectedRegion) async throws {
        try Task.checkCancellation()
        stop()
        self.region = region
        let generation = self.generation
        try await startStream(region: region, generation: generation)
        guard self.generation == generation else { throw CancellationError() }
        restartAttempt = 0
    }

    @MainActor
    func stop() {
        generation = UUID()
        restartTask?.cancel()
        restartTask = nil
        let current = replaceStream(nil)
        region = nil
        restartAttempt = 0
        Task { try? await current?.stopCapture() }
    }

    private func replaceStream(_ next: SCStream?) -> SCStream? {
        streamLock.lock()
        defer { streamLock.unlock() }
        let old = stream
        stream = next
        return old
    }

    private func isCurrent(_ candidate: SCStream) -> Bool {
        streamLock.lock()
        defer { streamLock.unlock() }
        return stream === candidate
    }

    @MainActor
    private func startStream(region: SelectedRegion, generation: UUID) async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(
            false,
            onScreenWindowsOnly: false
        )
        guard self.generation == generation, !Task.isCancelled else {
            throw CancellationError()
        }
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
        _ = replaceStream(stream)
        do {
            try await stream.startCapture()
        } catch {
            if isCurrent(stream) { _ = replaceStream(nil) }
            throw error
        }
        guard self.generation == generation, !Task.isCancelled else {
            if isCurrent(stream) { _ = replaceStream(nil) }
            try? await stream.stopCapture()
            throw CancellationError()
        }
    }

    // MARK: - SCStreamOutput

    func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of type: SCStreamOutputType
    ) {
        guard isCurrent(stream), type == .screen, sampleBuffer.isValid else { return }

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
        Task { @MainActor [weak self] in
            guard let self, self.isCurrent(stream), let region = self.region else { return }
            let generation = self.generation
            _ = self.replaceStream(nil)
            guard self.restartAttempt < Self.maxRestartAttempts else {
                self.onFatalError?("Luồng bắt màn hình dừng: \(error.localizedDescription)")
                return
            }
            self.restartAttempt += 1
            let backoff = [0.5, 1.0, 2.0, 3.0, 5.0][min(self.restartAttempt - 1, 4)]
            self.restartTask = Task { @MainActor [weak self] in
                do {
                    try await Task.sleep(for: .seconds(backoff))
                    guard let self, self.generation == generation else { return }
                    try await self.startStream(region: region, generation: generation)
                } catch {
                    guard let self, self.generation == generation, !Task.isCancelled else { return }
                    self.onFatalError?("Không khởi động lại được: \(error.localizedDescription)")
                }
            }
        }
    }
}
