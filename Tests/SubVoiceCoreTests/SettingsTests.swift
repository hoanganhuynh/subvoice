import Foundation
import Testing
@testable import SubVoiceCore

@Suite("Settings")
struct SettingsTests {
    @Test func themeDefaultsToSystem() {
        #expect(Settings().themeMode == .system)
    }

    @Test func oldPayloadWithoutThemeMigratesToSystem() throws {
        let data = Data(#"{"storedRate":0.55,"storedVolume":1}"#.utf8)
        let settings = try JSONDecoder().decode(Settings.self, from: data)
        #expect(settings.themeMode == .system)
    }
}
