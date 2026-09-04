import SubVoiceCore
import Testing

@Suite("Capture toggle policy")
struct CaptureTogglePolicyTests {

    @Test func toggleStopsPreviewInsteadOfStartingCapture() {
        #expect(
            CaptureTogglePolicy.action(isCaptureRunning: false, isPreviewing: true)
                == .stopPreview
        )
    }

    @Test func toggleKeepsNormalCaptureBehavior() {
        #expect(
            CaptureTogglePolicy.action(isCaptureRunning: false, isPreviewing: false)
                == .startCapture
        )
        #expect(
            CaptureTogglePolicy.action(isCaptureRunning: true, isPreviewing: false)
                == .stopCapture
        )
    }
}
