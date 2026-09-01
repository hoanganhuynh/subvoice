import Testing
@testable import SubVoiceUI

@Suite("Onboarding step")
struct OnboardingStepTests {

    @Test func stepsRunInTheDocumentedOrder() {
        #expect(OnboardingStep.allCases == [
            .welcome, .screenRecording, .voice, .region, .done,
        ])
    }

    @Test func firstStepHasNoPreviousAndLastHasNoNext() {
        #expect(OnboardingStep.welcome.previous == nil)
        #expect(OnboardingStep.welcome.next == .screenRecording)
        #expect(OnboardingStep.done.next == nil)
        #expect(OnboardingStep.done.previous == .region)
    }

    @Test func indicatorCountsFromOne() {
        #expect(OnboardingStep.welcome.indicator == "1/5")
        #expect(OnboardingStep.voice.indicator == "3/5")
        #expect(OnboardingStep.done.indicator == "5/5")
    }
}
