import Testing
@testable import SubVoiceUI

@Suite("Kokoro install state")
struct KokoroInstallStateTests {

    @Test func downloadProgressIsAFraction() {
        let state = KokoroInstallState.downloading(received: 250, total: 1000)
        #expect(state.progress == 0.25)
        #expect(state.isBusy)
    }

    @Test func unknownTotalHasNoProgress() {
        let state = KokoroInstallState.downloading(received: 250, total: 0)
        #expect(state.progress == nil)
        #expect(state.isBusy)
    }

    @Test func verifyingAndExtractingAreBusyWithoutAFraction() {
        #expect(KokoroInstallState.verifying.progress == nil)
        #expect(KokoroInstallState.verifying.isBusy)
        #expect(KokoroInstallState.extracting.isBusy)
    }

    @Test func terminalStatesAreNotBusy() {
        #expect(!KokoroInstallState.notInstalled.isBusy)
        #expect(!KokoroInstallState.installed(version: "1.0.0").isBusy)
        #expect(!KokoroInstallState.failed(message: "hỏng").isBusy)
    }

    @Test func failureShowsItsOwnMessage() {
        #expect(KokoroInstallState.failed(message: "Mất mạng").statusText == "Mất mạng")
    }
}
