import Foundation
import SubVoiceCore

/// Hành động người dùng có thể làm để tự gỡ một cảnh báo.
public enum RecoveryAction: Equatable, Sendable {
    case openScreenRecordingSettings
    case openSpokenContentSettings
    case retry
}

public struct AppWarning: Equatable, Sendable {
    public let message: String
    public let recovery: RecoveryAction?

    public init(message: String, recovery: RecoveryAction?) {
        self.message = message
        self.recovery = recovery
    }
}

/// Trạng thái chạy dùng chung cho cửa sổ chính và menu bar.
public enum AppRunState: Equatable, Sendable {
    case stopped
    case listening
    case speaking
    case warning(AppWarning)
}

/// Mô tả ngắn của vùng đọc, đủ để hiển thị mà không kéo theo AppKit.
public struct RegionSummary: Equatable, Sendable {
    public let displayID: UInt32
    public let pixelWidth: Int
    public let pixelHeight: Int

    public init(displayID: UInt32, pixelWidth: Int, pixelHeight: Int) {
        self.displayID = displayID
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
    }
}

public enum DiagnosticStatus: Equatable, Sendable {
    case ready(String)
    case unavailable(String)

    public var isReady: Bool {
        if case .ready = self { return true }
        return false
    }

    public var message: String {
        switch self {
        case .ready(let text), .unavailable(let text): return text
        }
    }
}

/// Ảnh chụp đầy đủ những gì giao diện cần vẽ. Coordinator là nơi duy nhất
/// tạo ra giá trị này.
public struct AppViewState: Equatable, Sendable {
    public var runState: AppRunState = .stopped
    public var settings = Settings()
    public var voices: [SpeechVoiceOption] = []
    public var region: RegionSummary?
    public var transcript = SessionTranscript()
    public var screenRecordingGranted = false
    public var systemVoiceStatus: DiagnosticStatus = .unavailable("Chưa kiểm tra")
    public var kokoroStatus: DiagnosticStatus = .unavailable("Chưa kiểm tra")
    public var kokoroAvailable = false
    public var kokoroInstall: KokoroInstallState = .notInstalled
    public var launchAtLoginEnabled = false

    public init() {}

    /// Giọng đang chọn của engine hiện tại.
    public var selectedVoiceIdentifier: String? {
        settings.speechEngine == .kokoro
            ? settings.kokoroVoiceIdentifier
            : settings.speechVoiceIdentifier
    }

    public var selectedVoiceName: String? {
        voices.first { $0.identifier == selectedVoiceIdentifier }?.name
    }

    public var isCapturing: Bool {
        switch runState {
        case .listening, .speaking: return true
        case .stopped, .warning: return false
        }
    }
}

/// Lệnh duy nhất giao diện gửi về coordinator.
public enum AppIntent: Equatable, Sendable {
    case toggleCapture
    case selectRegion
    case changeEngine(SpeechEngine)
    case changeVoice(String)
    case changeRate(Float)
    case changeVolume(Float)
    case previewVoice
    case clearTranscript
    case copyTranscript([UUID])
    case setTheme(ThemeMode)
    case setLaunchAtLogin(Bool)
    case downloadKokoro
    case cancelKokoroDownload
    case recover(RecoveryAction)
    case showMainWindow
    case quit
}
