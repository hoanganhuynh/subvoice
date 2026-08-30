import Foundation

/// Cài đặt người dùng chỉnh được từ menu.
public struct Settings: Codable, Equatable, Sendable {
    public static let minimumRate: Float = 0.40
    public static let maximumRate: Float = 0.70
    /// Năm nấc hiện trong menu, khớp với dải trên.
    public static let ratePresets: [Float] = [0.40, 0.475, 0.55, 0.625, 0.70]
    public static let volumePresets: [Float] = [0.25, 0.5, 0.75, 1.0]

    private var storedRate: Float = 0.55
    private var storedVolume: Float = 1.0

    public init() {}

    public var speechRate: Float {
        get { storedRate }
        set { storedRate = min(max(newValue, Settings.minimumRate), Settings.maximumRate) }
    }

    public var volume: Float {
        get { storedVolume }
        set { storedVolume = min(max(newValue, 0), 1) }
    }
}
