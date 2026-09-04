import Foundation

public enum SpeechEngine: String, Codable, Equatable, Sendable {
    case system
    case kokoro
}

/// Cài đặt người dùng chỉnh được từ menu.
public struct Settings: Codable, Equatable, Sendable {
    public static let minimumRate: Float = 0.40
    public static let maximumRate: Float = 0.70
    /// Năm nấc hiện trong menu, khớp với dải trên.
    public static let ratePresets: [Float] = [0.40, 0.475, 0.55, 0.625, 0.70]
    public static let volumePresets: [Float] = [0.25, 0.5, 0.75, 1.0]

    private var storedRate: Float = 0.55
    private var storedVolume: Float = 1.0
    private var storedVoiceIdentifier: String?
    private var storedSpeechEngine: SpeechEngine = .system
    private var storedKokoroVoiceIdentifier = "diem_trinh"
    private var storedThemeMode: ThemeMode = .system
    private var storedHasCompletedOnboarding = false

    public init() {}

    private enum CodingKeys: String, CodingKey {
        case storedRate
        case storedVolume
        case storedVoiceIdentifier
        case storedSpeechEngine
        case storedKokoroVoiceIdentifier
        case storedThemeMode
        case storedHasCompletedOnboarding
    }

    public init(from decoder: Decoder) throws {
        self.init()
        let values = try decoder.container(keyedBy: CodingKeys.self)
        speechRate = try values.decodeIfPresent(Float.self, forKey: .storedRate) ?? 0.55
        volume = try values.decodeIfPresent(Float.self, forKey: .storedVolume) ?? 1.0
        speechVoiceIdentifier = try values.decodeIfPresent(
            String.self,
            forKey: .storedVoiceIdentifier
        )
        speechEngine = try values.decodeIfPresent(
            SpeechEngine.self,
            forKey: .storedSpeechEngine
        ) ?? .system
        kokoroVoiceIdentifier = try values.decodeIfPresent(
            String.self,
            forKey: .storedKokoroVoiceIdentifier
        ) ?? "diem_trinh"
        // Bản cũ chưa có khoá này, và giá trị lạ (do sửa tay UserDefaults) cũng
        // không nên làm hỏng toàn bộ cài đặt — cả hai đều quay về `.system`.
        let decodedTheme = try? values.decodeIfPresent(
            ThemeMode.self,
            forKey: .storedThemeMode
        )
        themeMode = (decodedTheme ?? nil) ?? .system
        hasCompletedOnboarding = try values.decodeIfPresent(
            Bool.self,
            forKey: .storedHasCompletedOnboarding
        ) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(storedRate, forKey: .storedRate)
        try values.encode(storedVolume, forKey: .storedVolume)
        try values.encodeIfPresent(storedVoiceIdentifier, forKey: .storedVoiceIdentifier)
        try values.encode(storedSpeechEngine, forKey: .storedSpeechEngine)
        try values.encode(storedKokoroVoiceIdentifier, forKey: .storedKokoroVoiceIdentifier)
        try values.encode(storedThemeMode, forKey: .storedThemeMode)
        try values.encode(storedHasCompletedOnboarding, forKey: .storedHasCompletedOnboarding)
    }

    public var speechRate: Float {
        get { storedRate }
        set { storedRate = min(max(newValue, Settings.minimumRate), Settings.maximumRate) }
    }

    public var volume: Float {
        get { storedVolume }
        set { storedVolume = min(max(newValue, 0), 1) }
    }

    /// Mã định danh giọng macOS mà người dùng đã chọn. `nil` nghĩa là để app
    /// tự chọn giọng tiếng Việt mặc định.
    public var speechVoiceIdentifier: String? {
        get { storedVoiceIdentifier }
        set { storedVoiceIdentifier = newValue }
    }

    public var speechEngine: SpeechEngine {
        get { storedSpeechEngine }
        set { storedSpeechEngine = newValue }
    }

    public var kokoroVoiceIdentifier: String {
        get { storedKokoroVoiceIdentifier }
        set { storedKokoroVoiceIdentifier = newValue }
    }

    public var themeMode: ThemeMode {
        get { storedThemeMode }
        set { storedThemeMode = newValue }
    }

    public var hasCompletedOnboarding: Bool {
        get { storedHasCompletedOnboarding }
        set { storedHasCompletedOnboarding = newValue }
    }
}
