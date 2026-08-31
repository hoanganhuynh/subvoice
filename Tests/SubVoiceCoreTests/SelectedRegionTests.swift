import Testing
import Foundation
import CoreGraphics
@testable import SubVoiceCore

@Test func regionRoundTripsThroughJSON() throws {
    let region = SelectedRegion(
        displayID: 42,
        rect: CGRect(x: 100, y: 120, width: 400, height: 60),
        scale: 2
    )

    let data = try JSONEncoder().encode(region)
    let decoded = try JSONDecoder().decode(SelectedRegion.self, from: data)

    #expect(decoded == region)
}

@Test func regionReportsPixelDimensions() {
    let region = SelectedRegion(
        displayID: 1,
        rect: CGRect(x: 0, y: 0, width: 1200, height: 110),
        scale: 2
    )

    #expect(region.pixelWidth == 2400)
    #expect(region.pixelHeight == 220)
}

@Test func settingsClampSpeechRateIntoSupportedRange() {
    var settings = Settings()

    settings.speechRate = 9.0
    #expect(settings.speechRate == Settings.maximumRate)

    settings.speechRate = -1.0
    #expect(settings.speechRate == Settings.minimumRate)
}

@Test func settingsDefaultsMatchSpec() {
    let settings = Settings()
    #expect(settings.speechRate == 0.55)
    #expect(settings.volume == 1.0)
}

@Test func settingsClampVolume() {
    var settings = Settings()
    settings.volume = 3
    #expect(settings.volume == 1.0)
    settings.volume = -3
    #expect(settings.volume == 0.0)
}

@Test func settingsPreserveSelectedVietnameseVoice() {
    var settings = Settings()
    #expect(settings.speechVoiceIdentifier == nil)

    settings.speechVoiceIdentifier = "com.apple.voice.compact.vi-VN.Linh"
    #expect(settings.speechVoiceIdentifier == "com.apple.voice.compact.vi-VN.Linh")
}

@Test func settingsPersistKokoroEngineAndVoice() throws {
    var settings = Settings()
    #expect(settings.speechEngine == .system)
    #expect(settings.kokoroVoiceIdentifier == "diem_trinh")

    settings.speechEngine = .kokoro
    settings.kokoroVoiceIdentifier = "mai_linh"
    let restored = try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(settings))

    #expect(restored.speechEngine == .kokoro)
    #expect(restored.kokoroVoiceIdentifier == "mai_linh")
}

@Test func settingsDecodeLegacyDataBeforeEngineWasAdded() throws {
    let legacy = Data(#"{"storedRate":0.475,"storedVolume":0.75,"storedVoiceIdentifier":"legacy-linh"}"#.utf8)

    let restored = try JSONDecoder().decode(Settings.self, from: legacy)

    #expect(restored.speechRate == 0.475)
    #expect(restored.volume == 0.75)
    #expect(restored.speechVoiceIdentifier == "legacy-linh")
    #expect(restored.speechEngine == .system)
    #expect(restored.kokoroVoiceIdentifier == "diem_trinh")
}

@Test func kokoroRatePresetsSpanAnAudiblyDistinctRange() {
    let verySlow = SpeechRateMapping.kokoroSpeed(for: Settings.minimumRate)
    let medium = SpeechRateMapping.kokoroSpeed(for: 0.55)
    let veryFast = SpeechRateMapping.kokoroSpeed(for: Settings.maximumRate)

    #expect(verySlow <= 0.65)
    #expect(abs(medium - 1.0) < 0.001)
    #expect(veryFast >= 1.55)
    #expect(veryFast / verySlow >= 2.3)
}
