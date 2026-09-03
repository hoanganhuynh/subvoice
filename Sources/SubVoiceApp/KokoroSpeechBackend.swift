import AVFoundation
import Foundation
import SubVoiceCore

/// Backend neural tiếng Việt chạy hoàn toàn offline qua một tiến trình Python
/// thường trú. Model chỉ nạp một lần; mỗi câu sau đó đi qua JSON-lines.
final class KokoroSpeechBackend: NSObject, SpeechBackend, AVAudioPlayerDelegate {

    static let availableVoices: [SpeechVoiceOption] = [
        .init(identifier: "diem_trinh", name: "Diễm Trinh"),
        .init(identifier: "duc_an", name: "Đức An"),
        .init(identifier: "duc_duy", name: "Đức Duy"),
        .init(identifier: "hung_thinh", name: "Hùng Thịnh"),
        .init(identifier: "mai_linh", name: "Mai Linh"),
        .init(identifier: "mai_loan", name: "Mai Loan"),
        .init(identifier: "manh_dung", name: "Mạnh Dũng"),
        .init(identifier: "my_yen", name: "Mỹ Yến"),
        .init(identifier: "ngoc_huyen", name: "Ngọc Huyền"),
        .init(identifier: "phat_tai", name: "Phát Tài"),
        .init(identifier: "storyvert", name: "Storyvert"),
        .init(identifier: "thanh_dat", name: "Thành Đạt"),
        .init(identifier: "thuc_trinh", name: "Thục Trinh"),
        .init(identifier: "tuan_ngoc", name: "Tuấn Ngọc"),
    ]

    var onStart: (() -> Void)?
    var onFinish: (() -> Void)?
    var onError: ((String) -> Void)?

    private let runtimeResult: Result<KokoroRuntime, Error>
    private let protocolQueue = DispatchQueue(label: "SubVoice.KokoroProtocol")
    private var stdoutBuffer = Data()
    private var process: Process?
    private var stdinPipe: Pipe?
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?
    private var player: AVAudioPlayer?
    private var activeRequestID: String?
    private var activeAudioURL: URL?
    private var requestedVolume: Float = 1
    private(set) var voiceIdentifier: String

    init(
        voiceIdentifier: String,
        runtimeResult: Result<KokoroRuntime, Error> = Result { try KokoroRuntime.discover() }
    ) {
        self.voiceIdentifier = Self.availableVoices.contains { $0.identifier == voiceIdentifier }
            ? voiceIdentifier : "diem_trinh"
        self.runtimeResult = runtimeResult
        super.init()
    }

    var isAvailable: Bool {
        if case .success = runtimeResult { return true }
        return false
    }

    var unavailableReason: String? {
        guard case .failure(let error) = runtimeResult else { return nil }
        return error.localizedDescription
    }

    @discardableResult
    func selectVoice(identifier: String) -> String {
        if Self.availableVoices.contains(where: { $0.identifier == identifier }) {
            voiceIdentifier = identifier
        }
        return voiceIdentifier
    }

    func warmUp() {
        do {
            try startProcessIfNeeded()
        } catch {
            fail(error.localizedDescription, finishRequest: false)
        }
    }

    func speak(_ text: String, rate: Float, volume: Float) {
        do {
            try startProcessIfNeeded()
            guard let input = stdinPipe?.fileHandleForWriting else {
                throw KokoroBackendError.serviceUnavailable
            }

            let identifier = UUID().uuidString
            activeRequestID = identifier
            requestedVolume = volume
            let speed = SpeechRateMapping.kokoroSpeed(for: rate)
            let request = KokoroRequest(
                id: identifier,
                text: text,
                voice: voiceIdentifier,
                speed: speed
            )
            var data = try JSONEncoder().encode(request)
            data.append(0x0A)
            try input.write(contentsOf: data)
        } catch {
            fail(error.localizedDescription, finishRequest: true)
        }
    }

    func stop() {
        activeRequestID = nil
        player?.stop()
        player = nil
        removeActiveAudio()

        let oldProcess = process
        process = nil
        stdinPipe?.fileHandleForWriting.closeFile()
        stdoutPipe?.fileHandleForReading.readabilityHandler = nil
        stderrPipe?.fileHandleForReading.readabilityHandler = nil
        stdinPipe = nil
        stdoutPipe = nil
        stderrPipe = nil
        if oldProcess?.isRunning == true { oldProcess?.terminate() }
        protocolQueue.sync { stdoutBuffer.removeAll(keepingCapacity: false) }
    }

    private func startProcessIfNeeded() throws {
        if process?.isRunning == true { return }
        let runtime = try runtimeResult.get()
        let input = Pipe()
        let output = Pipe()
        let errors = Pipe()
        let service = Process()
        service.executableURL = runtime.python
        service.arguments = [
            runtime.service.path,
            "--models", runtime.models.path,
            "--output-dir", runtime.outputDirectory.path,
        ]
        service.currentDirectoryURL = runtime.root
        var environment = ProcessInfo.processInfo.environment
        // Gói mới không có venv, nên interpreter không tự thấy dependency.
        // PYTHONPATH là thứ duy nhất nối chúng lại.
        environment["PYTHONPATH"] = runtime.root
            .appendingPathComponent("site-packages", isDirectory: true).path
        service.environment = environment
        service.standardInput = input
        service.standardOutput = output
        service.standardError = errors

        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            self?.protocolQueue.async { self?.consumeStdout(data) }
        }
        errors.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let message = String(data: data, encoding: .utf8) else { return }
            NSLog("Kokoro: %@", message.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        service.terminationHandler = { [weak self, weak service] process in
            DispatchQueue.main.async {
                guard let self, let service, self.process === service else { return }
                self.process = nil
                if self.activeRequestID != nil {
                    self.fail(
                        "Kokoro đã dừng (mã \(process.terminationStatus))",
                        finishRequest: true
                    )
                }
            }
        }

        do {
            try service.run()
        } catch {
            output.fileHandleForReading.readabilityHandler = nil
            errors.fileHandleForReading.readabilityHandler = nil
            throw error
        }
        process = service
        stdinPipe = input
        stdoutPipe = output
        stderrPipe = errors
    }

    private func consumeStdout(_ data: Data) {
        stdoutBuffer.append(data)
        while let newline = stdoutBuffer.firstIndex(of: 0x0A) {
            let line = stdoutBuffer[..<newline]
            stdoutBuffer.removeSubrange(...newline)
            guard !line.isEmpty,
                  let response = try? JSONDecoder().decode(KokoroResponse.self, from: Data(line))
            else { continue }
            DispatchQueue.main.async { [weak self] in self?.handle(response) }
        }
    }

    private func handle(_ response: KokoroResponse) {
        guard response.id == activeRequestID else { return }
        if let error = response.error {
            fail(error, finishRequest: true)
            return
        }
        guard let path = response.path else {
            fail("Kokoro không trả về tệp âm thanh", finishRequest: true)
            return
        }

        do {
            let url = URL(fileURLWithPath: path)
            let audio = try AVAudioPlayer(contentsOf: url)
            audio.delegate = self
            audio.volume = requestedVolume
            activeAudioURL = url
            player = audio
            guard audio.prepareToPlay(), audio.play() else {
                throw KokoroBackendError.cannotPlayAudio
            }
            onStart?()
        } catch {
            fail(error.localizedDescription, finishRequest: true)
        }
    }

    private func fail(_ message: String, finishRequest: Bool) {
        let hadRequest = activeRequestID != nil
        activeRequestID = nil
        player?.stop()
        player = nil
        removeActiveAudio()
        onError?(message)
        if finishRequest && hadRequest { onFinish?() }
    }

    private func removeActiveAudio() {
        guard let url = activeAudioURL else { return }
        activeAudioURL = nil
        try? FileManager.default.removeItem(at: url)
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        activeRequestID = nil
        self.player = nil
        removeActiveAudio()
        if !flag { onError?("Không phát hết được âm thanh Kokoro") }
        onFinish?()
    }
}

private struct KokoroRequest: Encodable {
    let id: String
    let text: String
    let voice: String
    let speed: Double
}

private struct KokoroResponse: Decodable {
    let id: String
    let path: String?
    let error: String?
}

private enum KokoroBackendError: LocalizedError {
    case serviceUnavailable
    case cannotPlayAudio

    var errorDescription: String? {
        switch self {
        case .serviceUnavailable: return "Không kết nối được với Kokoro"
        case .cannotPlayAudio: return "Không phát được âm thanh Kokoro"
        }
    }
}
