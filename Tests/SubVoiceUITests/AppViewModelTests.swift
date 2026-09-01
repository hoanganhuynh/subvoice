import Testing
@testable import SubVoiceUI

@MainActor
@Suite("App view model")
struct AppViewModelTests {
    @Test func sendForwardsOneIntent() {
        let model = AppViewModel(state: AppViewState())
        var received: [AppIntent] = []
        model.onIntent = { received.append($0) }
        model.send(.toggleCapture)
        #expect(received == [.toggleCapture])
    }

    @Test func applyPublishesACompleteSnapshot() {
        let model = AppViewModel(state: AppViewState())
        model.apply { state in state.runState = .listening }
        #expect(model.state.runState == .listening)
    }
}
