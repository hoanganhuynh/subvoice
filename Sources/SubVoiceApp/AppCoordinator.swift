import AppKit
import CoreVideo
import Foundation
import SubVoiceCore

/// Trạng thái chỉ thuộc về hàng đợi bắt màn hình.
///
/// Tách hẳn ra khỏi `AppCoordinator` (vốn là `@MainActor`) thay vì để làm
/// thuộc tính, để không thể vô tình đụng tới nó từ main thread.
final class CaptureQueueState {
    private var detector = ChangeDetector()
    private var lastOCRSubmit = Date.distantPast

    func evaluate(_ signature: BrightnessSignature) -> FrameVerdict {
        detector.evaluate(signature)
    }

    /// Giới hạn tần suất OCR cứng. Trả về true và ghi nhận mốc nếu được phép chạy.
    func shouldRunOCR(at now: Date) -> Bool {
        guard now.timeIntervalSince(lastOCRSubmit) >= DetectorTuning.minOCRInterval else {
            return false
        }
        lastOCRSubmit = now
        return true
    }

    func reset() {
        detector.reset()
        lastOCRSubmit = .distantPast
    }
}

@MainActor
final class AppCoordinator {

    private let capturer = ScreenCapturer()
    private let speech = SystemSpeechBackend()
    private let regionSelector = RegionSelector()
    private let hotKeys = HotKeyManager()
    private var menuBar: MenuBarController!

    // Chạm từ hàng đợi bắt màn hình, nên không thể mang isolation của MainActor.
    // OCREngine tự khoá bên trong; CaptureQueueState chỉ có đúng một luồng dùng.
    nonisolated(unsafe) private let ocr = OCREngine()
    nonisolated(unsafe) private let captureState = CaptureQueueState()
    nonisolated(unsafe) private let latencyLock = NSLock()
    nonisolated(unsafe) private var changeDetectedAt: Date?

    private var gate = TextGate()
    private var speechQueue = SpeechQueue()
    private var settings = Store.loadSettings()
    private var region = Store.loadRegion()
    private var isRunning = false

    private var latencies: [Double] = []
    private let measuringLatency = CommandLine.arguments.contains("--measure-latency")

    func start() {
        menuBar = MenuBarController(settings: settings)
        wireMenuBar()
        wirePipeline()

        let failures = hotKeys.registerDefaults(
            onToggle: { [weak self] in self?.toggle() },
            onReselect: { [weak self] in self?.reselectRegion() }
        )
        if !failures.isEmpty {
            NSLog("Không đăng ký được phím tắt: \(failures)")
        }

        ocr.warmUp()
        speech.warmUp()

        if !speech.hasVietnameseVoice {
            menuBar.setState(.warning("Thiếu giọng tiếng Việt — bấm để xem hướng dẫn"))
        } else if !PermissionHelper.hasScreenRecordingAccess {
            menuBar.setState(.warning("Cần quyền Screen Recording — bấm để mở cài đặt"))
        }
    }

    // MARK: - Nối dây

    private func wireMenuBar() {
        menuBar.onToggle = { [weak self] in self?.toggle() }
        menuBar.onReselect = { [weak self] in self?.reselectRegion() }
        menuBar.onRateChange = { [weak self] rate in
            guard let self else { return }
            self.settings.speechRate = rate
            Store.saveSettings(self.settings)
        }
        menuBar.onVolumeChange = { [weak self] volume in
            guard let self else { return }
            self.settings.volume = volume
            Store.saveSettings(self.settings)
        }
        menuBar.onWarningClicked = { [weak self] in
            guard let self else { return }
            if !self.speech.hasVietnameseVoice {
                NSWorkspace.shared.open(URL(
                    string: "x-apple.systempreferences:com.apple.preference.universalaccess?SpeakableItems"
                )!)
            } else {
                PermissionHelper.openScreenRecordingSettings()
            }
        }
        menuBar.onQuit = { NSApp.terminate(nil) }
    }

    private func wirePipeline() {
        capturer.onFrame = { [weak self] frame in self?.handleFrame(frame) }
        capturer.onFatalError = { [weak self] message in
            guard let self else { return }
            self.stop()
            self.menuBar.setState(.warning(message))
        }
        ocr.onText = { [weak self] text in
            Task { @MainActor in self?.handleText(text) }
        }
        speech.onStart = { [weak self] in self?.handleSpeechStarted() }
        speech.onFinish = { [weak self] in self?.handleSpeechFinished() }
    }

    // MARK: - Máy trạng thái

    private func toggle() {
        isRunning ? stop() : startCapturing()
    }

    private func startCapturing() {
        guard PermissionHelper.hasScreenRecordingAccess else {
            PermissionHelper.requestScreenRecordingAccess()
            menuBar.setState(.warning("Cần quyền Screen Recording — bấm để mở cài đặt"))
            return
        }
        guard let region else {
            reselectRegion()   // chưa chọn vùng thì mở overlay trước
            return
        }

        captureState.reset()
        gate.clear()
        speechQueue.reset()
        isRunning = true
        menuBar.setState(.listening)

        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.capturer.start(region: region)
            } catch {
                self.isRunning = false
                self.menuBar.setState(.warning(error.localizedDescription))
            }
        }
    }

    private func stop() {
        isRunning = false
        capturer.stop()
        ocr.reset()
        speech.stop()
        speechQueue.reset()
        gate.clear()
        menuBar.setState(.stopped)
        reportLatenciesIfMeasuring()
    }

    private func reselectRegion() {
        let wasRunning = isRunning
        if wasRunning { stop() }

        regionSelector.begin { [weak self] selected in
            guard let self else { return }
            guard let selected else {
                if wasRunning { self.startCapturing() }
                return
            }
            self.region = selected
            Store.saveRegion(selected)
            self.startCapturing()
        }
    }

    // MARK: - Luồng dữ liệu

    /// Chạy trên `capturer.captureQueue`, KHÔNG phải main thread.
    private nonisolated func handleFrame(_ frame: CVPixelBuffer) {
        CVPixelBufferLockBaseAddress(frame, .readOnly)
        let signature: BrightnessSignature? = CVPixelBufferGetBaseAddress(frame).map { base in
            ChangeDetector.signature(
                bgra: base.assumingMemoryBound(to: UInt8.self),
                width: CVPixelBufferGetWidth(frame),
                height: CVPixelBufferGetHeight(frame),
                bytesPerRow: CVPixelBufferGetBytesPerRow(frame)
            )
        }
        CVPixelBufferUnlockBaseAddress(frame, .readOnly)
        guard let signature else { return }

        switch captureState.evaluate(signature) {
        case .blank:
            // Vùng phụ đề trống -> xoá trạng thái lọc trùng, để câu lặp lại
            // ở cảnh sau vẫn được đọc.
            Task { @MainActor [weak self] in self?.gate.clear() }

        case .unchanged:
            break

        case .changed:
            let now = Date()
            guard captureState.shouldRunOCR(at: now) else { return }
            latencyLock.lock()
            changeDetectedAt = now
            latencyLock.unlock()
            ocr.submit(frame)
        }
    }

    private func handleText(_ text: String) {
        guard isRunning else { return }
        guard case .speak(let sentence) = gate.admit(text) else { return }
        guard let immediate = speechQueue.enqueue(sentence) else { return }
        speech.speak(immediate, rate: settings.speechRate, volume: settings.volume)
    }

    private func handleSpeechStarted() {
        menuBar.setState(isRunning ? .speaking : .stopped)

        guard measuringLatency else { return }
        latencyLock.lock()
        let mark = changeDetectedAt
        changeDetectedAt = nil
        latencyLock.unlock()
        guard let mark else { return }

        let milliseconds = Date().timeIntervalSince(mark) * 1000
        latencies.append(milliseconds)
        NSLog("Độ trễ: %.0fms", milliseconds)
    }

    private func handleSpeechFinished() {
        guard let next = speechQueue.finished() else {
            if isRunning { menuBar.setState(.listening) }
            return
        }
        speech.speak(next, rate: settings.speechRate, volume: settings.volume)
    }

    private func reportLatenciesIfMeasuring() {
        guard measuringLatency, !latencies.isEmpty else { return }
        let sorted = latencies.sorted()
        let p50 = sorted[sorted.count / 2]
        let p95 = sorted[min(Int(Double(sorted.count) * 0.95), sorted.count - 1)]
        NSLog("Độ trễ trên %d câu — p50 %.0fms, p95 %.0fms", sorted.count, p50, p95)
        latencies.removeAll()
    }
}
