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

    /// URLSession báo tổng chưa biết bằng -1 (NSURLSessionTransferSizeUnknown),
    /// không phải 0.
    @Test func urlSessionUnknownTotalHasNoProgress() {
        let state = KokoroInstallState.downloading(received: 250, total: -1)
        #expect(state.progress == nil)
        #expect(state.isBusy)
    }

    /// Tải lại phần dở hoặc Content-Length báo thiếu có thể cho received > total.
    @Test func progressNeverLeavesTheZeroToOneRange() {
        #expect(KokoroInstallState.downloading(received: 1500, total: 1000).progress == 1)
        #expect(KokoroInstallState.downloading(received: 0, total: 1000).progress == 0)
    }

    @Test func verifyingExtractingAndFinishingAreBusyWithoutAFraction() {
        for state: KokoroInstallState in [.verifying, .extracting, .finishing] {
            #expect(state.isBusy)
            #expect(state.progress == nil)
        }
    }

    @Test func terminalStatesAreNotBusy() {
        #expect(!KokoroInstallState.notInstalled.isBusy)
        #expect(!KokoroInstallState.installed(version: "1.0.0").isBusy)
        #expect(!KokoroInstallState.failed(message: "hỏng").isBusy)
    }

    @Test func failureExplainsItIsTheKokoroInstall() {
        #expect(
            KokoroInstallState.failed(message: "Mất mạng").statusText
                == "Cài Kokoro thất bại: Mất mạng"
        )
    }

    @Test func eachPhaseNamesWhatIsActuallyHappening() {
        #expect(KokoroInstallState.notInstalled.statusText == "Chưa cài")
        #expect(KokoroInstallState.verifying.statusText == "Đang kiểm tra gói tải về…")
        #expect(KokoroInstallState.extracting.statusText == "Đang giải nén…")
        #expect(KokoroInstallState.finishing.statusText == "Đang hoàn tất…")
    }

    @Test func phaseTextsAreDistinctFromEachOther() {
        let phases: [KokoroInstallState] = [.notInstalled, .verifying, .extracting, .finishing]
        #expect(Set(phases.map(\.statusText)).count == phases.count)
    }

    @Test func installedTextCarriesTheVersion() {
        let text = KokoroInstallState.installed(version: "1.2.3").statusText
        #expect(text.contains("1.2.3"))
        #expect(text == "Đã cài bản 1.2.3")
    }

    @Test func knownTotalShowsReceivedOverTotal() {
        let text = KokoroInstallState.downloading(received: 250, total: 1000).statusText
        #expect(text.contains("/"))
        #expect(!text.contains("Zero"))
    }

    @Test func unknownTotalShowsOnlyWhatArrivedSoFar() {
        let text = KokoroInstallState.downloading(received: 250, total: -1).statusText
        #expect(text.hasSuffix("…"))
        #expect(!text.contains("/"))
        #expect(!text.contains("Zero"))
    }

    /// Ngay khi bắt đầu tải, received == 0; ByteCountFormatter mặc định trả
    /// "Zero KB" (tiếng Anh) nên phải tắt allowsNonnumericFormatting.
    @Test func zeroBytesNeverPrintsTheEnglishWordZero() {
        #expect(!KokoroInstallState.downloading(received: 0, total: 550_000_000)
            .statusText.contains("Zero"))
        #expect(!KokoroInstallState.downloading(received: 0, total: -1)
            .statusText.contains("Zero"))
    }
}
