import SubVoiceCore
import Testing
@testable import SubVoiceUI

@Suite("Dashboard content")
struct DashboardContentTests {
    @Test func stoppedContentInvitesStarting() {
        let content = DashboardContent(runState: .stopped)
        #expect(content.title == "Nghe phụ đề. Không rời mắt.")
        #expect(content.primaryActionTitle == "Bắt đầu đọc")
        #expect(content.symbolName == "speaker.wave.2")
    }

    @Test func warningUsesMessageAndRecoveryLabel() {
        let content = DashboardContent(runState: .warning(.init(
            message: "Cần quyền Screen Recording",
            recovery: .openScreenRecordingSettings
        )))
        #expect(content.title == "SubVoice cần bạn hỗ trợ")
        #expect(content.detail == "Cần quyền Screen Recording")
        #expect(content.recoveryTitle == "Mở System Settings")
    }

    @Test func pausedContentNamesTheAppAndKeepsTheStopButton() {
        let content = DashboardContent(runState: .paused(.windowGone("Google Chrome")))
        #expect(content.title == "SubVoice đang chờ")
        #expect(content.detail == "Tạm dừng — cửa sổ Google Chrome không còn hiện")
        #expect(content.primaryActionTitle == "Dừng đọc")
        #expect(content.symbolName == "pause.circle")
        #expect(content.recoveryTitle == nil)
    }

    @Test func eachPauseReasonHasItsOwnWording() {
        #expect(
            DashboardContent(runState: .paused(.windowCovered("Google Chrome"))).detail
                == "Tạm dừng — vùng đọc đang bị che"
        )
        #expect(
            DashboardContent(runState: .paused(.regionOutsideWindow("Google Chrome"))).detail
                == "Tạm dừng — cửa sổ Google Chrome đã đổi vị trí"
        )
        #expect(
            DashboardContent(runState: .paused(.contentChanged("Google Chrome"))).detail
                == "Tạm dừng — cửa sổ Google Chrome đã đổi nội dung"
        )
    }

    @Test func pausedStillCountsAsCapturing() {
        var state = AppViewState()
        state.runState = .paused(.windowCovered("Google Chrome"))
        #expect(state.isCapturing)
    }
}
