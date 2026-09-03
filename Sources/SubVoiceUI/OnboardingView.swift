import SubVoiceCore
import SwiftUI

/// Wizard lần đầu chạy. Luôn bỏ qua được: người đã biết mình đang làm gì không
/// nên bị nhốt trong năm màn hình.
struct OnboardingView: View {

    let state: AppViewState
    let viewModel: AppViewModel

    @Environment(\.aurora) private var theme
    @State private var step: OnboardingStep = .welcome

    var body: some View {
        ZStack {
            AuroraBackground()

            VStack(alignment: .leading, spacing: AuroraTheme.spacingMedium) {
                header
                Text(step.title)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(theme.primaryText)
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                footer
            }
            .padding(AuroraTheme.spacingLarge)
        }
    }

    private var header: some View {
        HStack {
            Text(step.indicator)
                .font(.caption.monospacedDigit())
                .foregroundStyle(theme.secondaryText)
                .accessibilityLabel("Bước \(step.indicator)")
            Spacer()
            Button("Bỏ qua") { viewModel.send(.finishOnboarding) }
                .buttonStyle(.plain)
                .foregroundStyle(theme.secondaryText)
        }
    }

    private var footer: some View {
        HStack {
            if let previous = step.previous {
                Button("Quay lại") { step = previous }
            }
            Spacer()
            if let next = step.next {
                Button("Tiếp tục") { step = next }
                    .keyboardShortcut(.defaultAction)
            } else {
                Button("Vào SubVoice") { viewModel.send(.finishOnboarding) }
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .welcome: welcomeContent
        case .screenRecording: screenRecordingContent
        case .voice: voiceContent
        case .region: regionContent
        case .done: doneContent
        }
    }

    private var welcomeContent: some View {
        VStack(alignment: .leading, spacing: AuroraTheme.spacingSmall) {
            paragraph("SubVoice đọc phụ đề trên màn hình thành tiếng Việt, để bạn nghe "
                + "thoại mà không phải rời mắt khỏi hình.")
            Label(
                "Ảnh màn hình, OCR và giọng đọc đều xử lý trên máy bạn. "
                + "Không có gì rời khỏi thiết bị.",
                systemImage: "lock.shield"
            )
            .foregroundStyle(theme.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var screenRecordingContent: some View {
        VStack(alignment: .leading, spacing: AuroraTheme.spacingSmall) {
            statusLabel(
                ready: state.screenRecordingGranted,
                text: state.screenRecordingGranted ? "Đã được cấp quyền" : "Chưa có quyền"
            )
            paragraph("SubVoice cần quyền Screen Recording để đọc được chữ trong vùng bạn "
                + "chọn. Không có quyền này thì app không thấy gì cả.")

            if !state.screenRecordingGranted {
                Button("Mở System Settings") {
                    viewModel.send(.recover(.openScreenRecordingSettings))
                }
                // Nói thẳng thay vì để người dùng tưởng app hỏng: macOS chỉ áp
                // dụng quyền này ở lần khởi động kế tiếp.
                Text("Sau khi bật, hãy thoát SubVoice rồi mở lại. macOS chỉ áp dụng quyền "
                    + "này ở lần khởi động kế tiếp — đây là giới hạn của hệ điều hành, "
                    + "không phải lỗi của app.")
                    .font(.footnote)
                    .foregroundStyle(theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var voiceContent: some View {
        VStack(alignment: .leading, spacing: AuroraTheme.spacingSmall) {
            statusLabel(
                ready: state.systemVoiceStatus.isReady,
                text: state.systemVoiceStatus.message
            )
            if !state.systemVoiceStatus.isReady {
                Button("Mở Spoken Content") {
                    viewModel.send(.recover(.openSpokenContentSettings))
                }
            }

            Divider().overlay(theme.separator)

            Text("Giọng Kokoro — tự nhiên hơn, vẫn chạy offline")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(theme.primaryText)
            Text("Tải thêm khoảng \(downloadSizeText). Bạn dùng SubVoice bình thường "
                + "trong lúc tải, và bỏ qua bước này thì tải sau trong Voice Studio.")
                .font(.footnote)
                .foregroundStyle(theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            KokoroInstallRow(state: state, viewModel: viewModel)
        }
    }

    private var regionContent: some View {
        VStack(alignment: .leading, spacing: AuroraTheme.spacingSmall) {
            paragraph("Kéo một khung quanh chỗ phụ đề hiện ra. SubVoice chỉ đọc chữ "
                + "bên trong khung đó.")
            if let region = state.region {
                statusLabel(
                    ready: true,
                    text: "Màn hình \(region.displayID) · "
                        + "\(region.pixelWidth)×\(region.pixelHeight)"
                )
            }
            Button(state.region == nil ? "Chọn vùng" : "Chọn lại vùng") {
                viewModel.send(.selectRegion)
            }
        }
    }

    private var doneContent: some View {
        VStack(alignment: .leading, spacing: AuroraTheme.spacingSmall) {
            Label("⌥⌘V — bật hoặc tắt đọc", systemImage: "keyboard")
            Label("⌥⌘R — chọn lại vùng phụ đề", systemImage: "keyboard")
            Label(
                "Đóng cửa sổ không làm SubVoice thoát. App vẫn sống trên menu bar.",
                systemImage: "menubar.arrow.up.rectangle"
            )
        }
        .foregroundStyle(theme.secondaryText)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var downloadSizeText: String {
        let formatter = ByteCountFormatter()
        formatter.allowsNonnumericFormatting = false
        return formatter.string(fromByteCount: KokoroPackage.current.downloadBytes)
    }

    private func paragraph(_ text: String) -> some View {
        Text(text)
            .foregroundStyle(theme.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func statusLabel(ready: Bool, text: String) -> some View {
        Label(text, systemImage: ready ? "checkmark.circle" : "exclamationmark.circle")
            .foregroundStyle(ready ? theme.status : theme.warning)
            .fixedSize(horizontal: false, vertical: true)
    }
}
