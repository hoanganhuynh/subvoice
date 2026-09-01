import AppKit
import CoreVideo
import Foundation
import ServiceManagement
import SubVoiceCore
import SubVoiceUI

/// Trạng thái chỉ thuộc về hàng đợi bắt màn hình.
///
/// Tách hẳn ra khỏi `AppCoordinator` (vốn là `@MainActor`) thay vì để làm
/// thuộc tính, để không thể vô tình đụng tới nó từ main thread.
/// Kết quả xét một khung, kèm các số đo dùng để chỉnh ngưỡng.
struct FrameDecision {
    let verdict: FrameVerdict
    /// Verdict có khác khung trước không — để chỉ log lúc đổi trạng thái.
    let isTransition: Bool
    let distance: Float
    let relative: Float
    let brightness: Float
}

final class CaptureQueueState {
    private var detector = ChangeDetector()
    private var lastOCRSubmit = Date.distantPast

    func evaluate(_ signature: BrightnessSignature) -> FrameDecision {
        let before = detector.previousVerdict
        let verdict = detector.evaluate(signature)
        return FrameDecision(
            verdict: verdict,
            isTransition: before != verdict,
            distance: detector.lastDistance,
            relative: detector.lastRelativeDistance,
            brightness: detector.lastTotalBrightness
        )
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
    private let systemSpeech = SystemSpeechBackend()
    private let regionSelector = RegionSelector()
    private let hotKeys = HotKeyManager()
    private var menuBar: MenuBarController!

    /// Nguồn trạng thái duy nhất mà cửa sổ chính và menu bar cùng đọc.
    let viewModel = AppViewModel(state: AppViewState())
    private var mainWindow: MainWindowController!

    // Chạm từ hàng đợi bắt màn hình, nên không thể mang isolation của MainActor.
    // OCREngine tự khoá bên trong; CaptureQueueState chỉ có đúng một luồng dùng.
    nonisolated(unsafe) private let ocr = OCREngine()
    nonisolated(unsafe) private let captureState = CaptureQueueState()
    nonisolated private let latencyLock = NSLock()
    nonisolated(unsafe) private var changeDetectedAt: Date?

    private var gate = TextGate()
    private var speechQueue = SpeechQueue()
    private var settings = Store.loadSettings()
    private lazy var kokoroSpeech = KokoroSpeechBackend(
        voiceIdentifier: settings.kokoroVoiceIdentifier
    )
    private var region = Store.loadRegion()
    private var isRunning = false

    private var speech: SpeechBackend {
        settings.speechEngine == .kokoro ? kokoroSpeech : systemSpeech
    }

    private var latencies: [Double] = []
    private let measuringLatency = CommandLine.arguments.contains("--measure-latency")
    nonisolated private let tracing = CommandLine.arguments.contains("--trace")

    func start() {
        if CommandLine.arguments.contains("--check-permission") {
            // Ghi ra file thay vì stdout: cách đo ĐÚNG là khởi động app qua
            // Finder (`open --args`), lúc đó không có stdout để đọc. Chạy binary
            // thẳng từ Terminal sẽ cho kết quả SAI vì TCC quy trách nhiệm cho
            // Terminal, và Terminal thường đã có sẵn quyền Screen Recording.
            let report = """
            screen-recording-granted: \(PermissionHelper.hasScreenRecordingAccess)
            vietnamese-voice-found:   \(systemSpeech.hasVietnameseVoice)
            bundle-id:                \(Bundle.main.bundleIdentifier ?? "khong co bundle")
            """
            print(report)
            try? report.write(
                toFile: "/tmp/subvoice-permission.txt",
                atomically: true,
                encoding: .utf8
            )
            exit(0)
        }

        // Lựa chọn cũ có thể biến mất khi người dùng gỡ voice pack khỏi macOS;
        // backend sẽ trả về giọng fallback thực sự đang dùng để menu đánh dấu
        // đúng mục và lưu lại lựa chọn hợp lệ.
        settings.speechVoiceIdentifier = systemSpeech.selectVoice(
            identifier: settings.speechVoiceIdentifier
        )
        if settings.speechEngine == .kokoro && !kokoroSpeech.isAvailable {
            NSLog("Không dùng được Kokoro: %@", kokoroSpeech.unavailableReason ?? "không rõ lỗi")
            settings.speechEngine = .system
        }
        Store.saveSettings(settings)
        menuBar = MenuBarController()
        mainWindow = MainWindowController(viewModel: viewModel)
        mainWindow.apply(theme: settings.themeMode)
        viewModel.onIntent = { [weak self] intent in self?.handle(intent) }
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

        if CommandLine.arguments.contains("--smoke-overlay") {
            runOverlaySmokeTest()
            return
        }

        if CommandLine.arguments.contains("--smoke-window") {
            runWindowSmokeTest()
            return
        }

        showMainWindow()

        refreshIdleState()
    }

    /// Chạy trọn một chu trình chọn vùng rồi thoát, để `Scripts/smoke-overlay.sh`
    /// chạy nó dưới NSZombie và bắt lại lỗi over-release cửa sổ overlay.
    private func runOverlaySmokeTest() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            self?.reselectRegion()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                self?.regionSelector.simulateDragForSmokeTest()
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                    print("OVERLAY-SMOKE-OK")
                    exit(0)
                }
            }
        }
    }

    /// Mở cửa sổ chính rồi tự thoát, để `Scripts/smoke-window.sh` xác nhận
    /// vòng đời Dock + cửa sổ vẫn dựng được sau mỗi lần đổi Info.plist hoặc
    /// activation policy.
    private func runWindowSmokeTest() {
        showMainWindow()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let report = self.mainWindow.isVisible ? "WINDOW-SMOKE-OK\n" : "WINDOW-SMOKE-FAIL\n"
            try? report.write(
                toFile: "/tmp/subvoice-window-smoke.txt",
                atomically: true,
                encoding: .utf8
            )
            exit(0)
        }
    }

    // MARK: - Nối dây

    private func wireMenuBar() {
        menuBar.onIntent = { [weak self] intent in self?.handle(intent) }
        menuBar.onOpenWindow = { [weak self] in self?.showMainWindow() }
        menuBar.onMenuWillOpen = { [weak self] in self?.refreshIdleState() }
    }

    func showMainWindow() {
        mainWindow?.show()
    }

    // MARK: - Ảnh chụp trạng thái

    private func regionSummary() -> RegionSummary? {
        region.map {
            RegionSummary(
                displayID: $0.displayID,
                pixelWidth: $0.pixelWidth,
                pixelHeight: $0.pixelHeight
            )
        }
    }

    /// Dựng lại toàn bộ ảnh chụp trạng thái rồi đẩy cho cả cửa sổ và menu bar,
    /// để hai nơi không thể hiển thị lệch nhau.
    private func publishSnapshot(runState: AppRunState? = nil) {
        viewModel.apply { state in
            if let runState { state.runState = runState }
            state.settings = settings
            state.voices = voicesForCurrentEngine()
            state.region = regionSummary()
            state.screenRecordingGranted = PermissionHelper.hasScreenRecordingAccess
            state.systemVoiceStatus = systemSpeech.hasVietnameseVoice
                ? .ready("Giọng tiếng Việt đã sẵn sàng")
                : .unavailable("Thiếu giọng tiếng Việt")
            state.kokoroAvailable = kokoroSpeech.isAvailable
            state.kokoroStatus = kokoroSpeech.isAvailable
                ? .ready("Kokoro đã sẵn sàng")
                : .unavailable(kokoroSpeech.unavailableReason ?? "Chưa cài Kokoro")
            state.launchAtLoginEnabled = SMAppService.mainApp.status == .enabled
        }
        menuBar?.render(viewModel.state)
    }

    // MARK: - Xử lý lệnh

    private func handle(_ intent: AppIntent) {
        switch intent {
        case .toggleCapture:
            toggle()
        case .selectRegion:
            reselectRegion()
        case .changeEngine(let engine):
            switchSpeechEngine(to: engine)
        case .changeVoice(let identifier):
            changeVoice(to: identifier)
        case .changeRate(let rate):
            settings.speechRate = rate
            Store.saveSettings(settings)
            publishSnapshot()
        case .changeVolume(let volume):
            settings.volume = volume
            Store.saveSettings(settings)
            publishSnapshot()
        case .previewVoice:
            previewVoice()
        case .clearTranscript:
            viewModel.apply { $0.transcript.clear() }
            menuBar.render(viewModel.state)
        case .copyTranscript(let identifiers):
            copyTranscript(identifiers)
        case .setTheme(let theme):
            settings.themeMode = theme
            Store.saveSettings(settings)
            publishSnapshot()
            mainWindow.apply(theme: theme)
        case .setLaunchAtLogin(let enabled):
            setLaunchAtLogin(enabled)
        case .downloadKokoro, .cancelKokoroDownload:
            // Bộ tải Kokoro được nối dây ở task sau; hiện chưa làm gì.
            break
        case .recover(let action):
            recover(action)
        case .showMainWindow:
            showMainWindow()
        case .quit:
            NSApp.terminate(nil)
        }
    }

    private func changeVoice(to identifier: String) {
        // Utterance đang đọc đã giữ voice riêng; lựa chọn mới sẽ có hiệu lực ở
        // câu kế tiếp, không làm đứt câu hiện tại.
        if settings.speechEngine == .kokoro {
            settings.kokoroVoiceIdentifier = kokoroSpeech.selectVoice(identifier: identifier)
        } else {
            settings.speechVoiceIdentifier = systemSpeech.selectVoice(identifier: identifier)
        }
        Store.saveSettings(settings)
        publishSnapshot()
    }

    /// Chỉ cho thử giọng lúc đang dừng, để không cắt ngang câu phụ đề đang đọc.
    private func previewVoice() {
        guard !isRunning else { return }
        speech.speak(
            "Xin chào, đây là giọng đọc của SubVoice.",
            rate: settings.speechRate,
            volume: settings.volume
        )
    }

    /// Giữ nguyên thứ tự đang hiển thị mà giao diện gửi xuống.
    private func copyTranscript(_ identifiers: [UUID]) {
        let textByID = Dictionary(
            viewModel.state.transcript.entries.map { ($0.id, $0.text) },
            uniquingKeysWith: { first, _ in first }
        )
        let joined = identifiers.compactMap { textByID[$0] }.joined(separator: "\n")
        guard !joined.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(joined, forType: .string)
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            publishSnapshot()
        } catch {
            NSLog("Không đổi được cài đặt khởi động cùng máy: \(error.localizedDescription)")
            publishSnapshot(runState: .warning(AppWarning(
                message: "Không đổi được cài đặt khởi động cùng máy",
                recovery: .retry
            )))
        }
    }

    private func recover(_ action: RecoveryAction) {
        switch action {
        case .openScreenRecordingSettings:
            PermissionHelper.openScreenRecordingSettings()
        case .openSpokenContentSettings:
            NSWorkspace.shared.open(URL(
                string: "x-apple.systempreferences:com.apple.preference.universalaccess?SpeakableItems"
            )!)
        case .retry:
            refreshIdleState()
        }
    }

    /// Quyền Screen Recording chỉ có hiệu lực sau khi app khởi động lại, và
    /// người dùng hầu như luôn cấp quyền lúc app đang chạy. Tính lại mỗi lần mở
    /// menu để không hiện cảnh báo đã cũ.
    private func refreshIdleState() {
        guard !isRunning else { return }
        publishSnapshot(runState: idleWarning().map(AppRunState.warning) ?? .stopped)
    }

    /// Cảnh báo đáng hiện khi app đang dừng, kèm cách người dùng tự gỡ.
    private func idleWarning() -> AppWarning? {
        if settings.speechEngine == .system && !systemSpeech.hasVietnameseVoice {
            return AppWarning(
                message: "Thiếu giọng tiếng Việt — mở Spoken Content để tải về",
                recovery: .openSpokenContentSettings
            )
        }
        if !PermissionHelper.hasScreenRecordingAccess {
            return AppWarning(
                message: "Cần quyền Screen Recording — mở System Settings để cấp",
                recovery: .openScreenRecordingSettings
            )
        }
        return nil
    }

    private func wirePipeline() {
        capturer.onFrame = { [weak self] frame in self?.handleFrame(frame) }
        capturer.onFatalError = { [weak self] message in
            guard let self else { return }
            self.stop()
            self.publishSnapshot(runState: .warning(
                AppWarning(message: message, recovery: .retry)
            ))
        }
        ocr.onText = { [weak self] text in
            Task { @MainActor in self?.handleText(text) }
        }
        configureSpeechBackend(systemSpeech)
        configureSpeechBackend(kokoroSpeech)
    }

    private func configureSpeechBackend(_ backend: SpeechBackend) {
        backend.onStart = { [weak self] in self?.handleSpeechStarted() }
        backend.onFinish = { [weak self] in self?.handleSpeechFinished() }
        backend.onError = { [weak self, weak backend] message in
            guard let self, let backend, backend === self.kokoroSpeech else { return }
            self.fallbackFromKokoro(message)
        }
    }

    private func voicesForCurrentEngine() -> [SpeechVoiceOption] {
        settings.speechEngine == .kokoro
            ? KokoroSpeechBackend.availableVoices
            : systemSpeech.availableVietnameseVoices
    }

    private func switchSpeechEngine(to engine: SpeechEngine) {
        guard engine != settings.speechEngine else { return }
        if engine == .kokoro && !kokoroSpeech.isAvailable {
            publishSnapshot(runState: .warning(AppWarning(
                message: kokoroSpeech.unavailableReason ?? "Chưa cài Kokoro",
                recovery: nil
            )))
            return
        }

        speechQueue.reset()
        speech.stop()
        settings.speechEngine = engine
        Store.saveSettings(settings)
        speech.warmUp()
        if isRunning { publishSnapshot(runState: .listening) } else { refreshIdleState() }
    }

    private func fallbackFromKokoro(_ message: String) {
        guard settings.speechEngine == .kokoro else { return }
        NSLog("Kokoro lỗi, chuyển về giọng hệ thống: %@", message)
        kokoroSpeech.stop()
        settings.speechEngine = .system
        Store.saveSettings(settings)
        publishSnapshot(runState: .warning(AppWarning(
            message: "Kokoro lỗi — đã chuyển về giọng hệ thống",
            recovery: .retry
        )))
    }

    // MARK: - Máy trạng thái

    private func toggle() {
        isRunning ? stop() : startCapturing()
    }

    private func startCapturing() {
        guard PermissionHelper.hasScreenRecordingAccess else {
            PermissionHelper.requestScreenRecordingAccess()
            publishSnapshot(runState: .warning(AppWarning(
                message: "Cần quyền Screen Recording — mở System Settings để cấp",
                recovery: .openScreenRecordingSettings
            )))
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
        publishSnapshot(runState: .listening)

        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.capturer.start(region: region)
            } catch {
                self.isRunning = false
                self.publishSnapshot(runState: .warning(AppWarning(
                    message: error.localizedDescription,
                    recovery: .retry
                )))
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
        publishSnapshot(runState: .stopped)
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

        let decision = captureState.evaluate(signature)

        if tracing {
            switch decision.verdict {
            case .changed:
                TraceLog.shared.write(String(
                    format: "detector=changed   tuong-doi=%.2f  dist=%.4f  bright=%.4f",
                    decision.relative, decision.distance, decision.brightness))
            case .blank where decision.isTransition:
                TraceLog.shared.write(String(
                    format: "detector=blank    bright=%.4f  (nguong blank=%.4f)",
                    decision.brightness, DetectorTuning.blankFloor))
            case .unchanged where decision.relative >= DetectorTuning.relativeChangeThreshold * 0.5:
                // Suýt vượt ngưỡng. Nếu câu bị bỏ qua thì đây chính là chỗ mất.
                TraceLog.shared.write(String(
                    format: "detector=SUYT-VUOT tuong-doi=%.2f  (nguong=%.2f)  bright=%.4f",
                    decision.relative, DetectorTuning.relativeChangeThreshold,
                    decision.brightness))
            default:
                break
            }
        }

        switch decision.verdict {
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

        if tracing { TraceLog.shared.write("ocr       \"\(text)\"") }

        let verdict = gate.admit(text)
        guard case .speak(let sentence) = verdict else {
            if tracing {
                TraceLog.shared.write("  gate=BO   ly-do=\(gate.lastDropReason?.rawValue ?? "?")")
            }
            return
        }
        if tracing { TraceLog.shared.write("  gate=DOC  \"\(sentence)\"") }

        viewModel.apply { $0.transcript.append(text: sentence) }
        menuBar.render(viewModel.state)

        let immediate = speechQueue.enqueue(sentence)
        if tracing {
            TraceLog.shared.write(
                "  queue=\(immediate == nil ? "xep-hang" : "doc-ngay")"
                + " cho=\(speechQueue.pendingCount)")
        }
        guard let immediate else { return }
        speech.speak(immediate, rate: settings.speechRate, volume: settings.volume)
    }

    private func handleSpeechStarted() {
        publishSnapshot(runState: isRunning ? .speaking : .stopped)

        guard measuringLatency else { return }
        latencyLock.lock()
        let mark = changeDetectedAt
        changeDetectedAt = nil
        latencyLock.unlock()
        guard let mark else { return }

        let milliseconds = Date().timeIntervalSince(mark) * 1000
        latencies.append(milliseconds)
        if tracing { TraceLog.shared.write(String(format: "  do-tre=%.0fms", milliseconds)) }
        NSLog("Độ trễ: %.0fms", milliseconds)
    }

    private func handleSpeechFinished() {
        guard let next = speechQueue.finished() else {
            if isRunning { publishSnapshot(runState: .listening) }
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
