import Foundation
import Testing
@testable import SubVoiceCore

@Suite("Region owner")
struct RegionOwnerTests {
    @Test func trimsSurroundingWhitespace() {
        #expect(RegionOwner.normalizedTitle("  Phim hay  ") == "Phim hay")
    }

    @Test func stripsNotificationCounterPrefix() {
        #expect(RegionOwner.normalizedTitle("(3) Phim hay - YouTube") == "Phim hay - YouTube")
    }

    @Test func stripsRepeatedCounterPrefixes() {
        #expect(RegionOwner.normalizedTitle("(12) (2) Phim hay") == "Phim hay")
    }

    @Test func keepsParenthesesThatAreNotCounters() {
        #expect(RegionOwner.normalizedTitle("(Trailer) Phim hay") == "(Trailer) Phim hay")
    }

    @Test func treatsMissingAndEmptyTitlesAsNil() {
        #expect(RegionOwner.normalizedTitle(nil) == nil)
        #expect(RegionOwner.normalizedTitle("   ") == nil)
        #expect(RegionOwner.normalizedTitle("(3)") == nil)
    }

    @Test func roundTripsThroughJSON() throws {
        let owner = RegionOwner(
            bundleIdentifier: "com.google.Chrome",
            applicationName: "Google Chrome",
            windowNumber: 7788,
            windowTitle: "Phim hay"
        )

        let data = try JSONEncoder().encode(owner)
        #expect(try JSONDecoder().decode(RegionOwner.self, from: data) == owner)
    }
}
