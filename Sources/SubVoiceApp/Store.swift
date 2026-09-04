import Foundation
import SubVoiceCore

/// Lưu vùng đã chọn và cài đặt vào UserDefaults dưới dạng JSON.
enum Store {
    private static let regionKey = "subvoice.region"
    private static let settingsKey = "subvoice.settings"

    static func loadRegion() -> SelectedRegion? {
        guard let data = UserDefaults.standard.data(forKey: regionKey) else { return nil }
        return try? JSONDecoder().decode(SelectedRegion.self, from: data)
    }

    static func saveRegion(_ region: SelectedRegion?) {
        guard let region, let data = try? JSONEncoder().encode(region) else {
            UserDefaults.standard.removeObject(forKey: regionKey)
            return
        }
        UserDefaults.standard.set(data, forKey: regionKey)
    }

    static func loadSettings() -> Settings {
        guard let data = UserDefaults.standard.data(forKey: settingsKey),
              let settings = try? JSONDecoder().decode(Settings.self, from: data)
        else { return Settings() }
        return settings
    }

    static func saveSettings(_ settings: Settings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        UserDefaults.standard.set(data, forKey: settingsKey)
    }
}
