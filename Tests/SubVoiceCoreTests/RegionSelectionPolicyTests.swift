import Testing
@testable import SubVoiceCore

@Suite("Region selection policy")
struct RegionSelectionPolicyTests {
    @Test func manualSelectionWhileStoppedDoesNotStartCapture() {
        #expect(!RegionSelectionPolicy.shouldResumeCapture(
            captureWasRunning: false,
            initiatedByStart: false
        ))
    }

    @Test func startWithoutARegionResumesAfterSelection() {
        #expect(RegionSelectionPolicy.shouldResumeCapture(
            captureWasRunning: false,
            initiatedByStart: true
        ))
    }

    @Test func selectingANewRegionWhileCapturingResumes() {
        #expect(RegionSelectionPolicy.shouldResumeCapture(
            captureWasRunning: true,
            initiatedByStart: false
        ))
    }
}
