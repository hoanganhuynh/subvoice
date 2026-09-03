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

    @Test func invalidThemeDoesNotDiscardTheRestOfThePayload() throws {
        let data = Data(#"""
        {
          "storedRate": 0.625,
          "storedVolume": 0.75,
          "storedKokoroVoiceIdentifier": "mai_linh",
          "storedThemeMode": "neon"
        }
        """#.utf8)

        let settings = try JSONDecoder().decode(Settings.self, from: data)

        #expect(settings.speechRate == 0.625)
        #expect(settings.volume == 0.75)
        #expect(settings.kokoroVoiceIdentifier == "mai_linh")
        #expect(settings.themeMode == .system)
    }

    @Test func onboardingFlagDefaultsToFalseAndSurvivesARoundTrip() throws {
        #expect(Settings().hasCompletedOnboarding == false)

        let old = Data(#"{"storedRate":0.55,"storedVolume":1}"#.utf8)
        #expect(try JSONDecoder().decode(Settings.self, from: old).hasCompletedOnboarding == false)

        var settings = Settings()
        settings.hasCompletedOnboarding = true
        let encoded = try JSONEncoder().encode(settings)
        #expect(try JSONDecoder().decode(Settings.self, from: encoded).hasCompletedOnboarding)
    }
}
