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
}
