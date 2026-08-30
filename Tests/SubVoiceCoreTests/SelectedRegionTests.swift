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
