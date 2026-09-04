import Foundation

/// Quy đổi dải tốc độ của giọng hệ thống sang hệ số mà model Kokoro nhận.
/// Hai nửa được nội suy riêng để mức "Vừa" luôn chính xác là 1×.
public enum SpeechRateMapping {
    public static func kokoroSpeed(for systemRate: Float) -> Double {
        let rate = min(max(systemRate, Settings.minimumRate), Settings.maximumRate)
        let medium: Float = 0.55

        if rate <= medium {
            let progress = Double((rate - Settings.minimumRate) / (medium - Settings.minimumRate))
            return 0.65 + progress * 0.35
        }

        let progress = Double((rate - medium) / (Settings.maximumRate - medium))
        return 1.0 + progress * 0.55
    }
}
