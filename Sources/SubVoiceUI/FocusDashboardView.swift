import AppKit
import SwiftUI

/// Bố cục Focus First: trạng thái và nút bật/tắt chiếm trung tâm, thiết lập
/// chi tiết nằm sau control dock.
struct FocusDashboardView: View {

    let state: AppViewState
    let viewModel: AppViewModel
    let onOpenSettings: () -> Void
    let onOpenVoiceStudio: () -> Void
    let onOpenTranscript: () -> Void

    @Environment(\.aurora) private var theme

    private var content: DashboardContent { DashboardContent(runState: state.runState) }

    @ViewBuilder
    private func hero(orbSize: CGFloat) -> some View {
        VStack(spacing: AuroraTheme.spacingMedium) {
            StatusOrbView(runState: state.runState, size: orbSize)
            HeroCopyView(content: content)
            PrimaryCaptureButton(
                title: content.primaryActionTitle,
                isCapturing: state.isCapturing
            ) {
                viewModel.send(.toggleCapture)
            }
            if let recoveryTitle = content.recoveryTitle,
               let recoveryAction = content.recoveryAction {
                Button(recoveryTitle) {
                    viewModel.send(.recover(recoveryAction))
                }
                .buttonStyle(.link)
                .foregroundStyle(theme.accentSoft)
            }
        }
    }

    var body: some View {
        ZStack {
            AuroraBackground()

            VStack(spacing: AuroraTheme.spacingMedium) {
                TopBar(state: state, onOpenSettings: onOpenSettings)

                if let notice = state.notice {
                    NoticeBanner(warning: notice)
                }

                Spacer(minLength: AuroraTheme.spacingXSmall)

                // Vẫn có fallback compact khi người dùng tăng cỡ chữ hoặc cửa
                // sổ bị thu nhỏ gần ngưỡng 620 điểm.
                ViewThatFits(in: .vertical) {
                    hero(orbSize: 176)
                    hero(orbSize: 128)
                    hero(orbSize: 96)
                }

                Spacer(minLength: AuroraTheme.spacingXSmall)

                ControlDockView(
                    state: state,
                    viewModel: viewModel,
                    onOpenVoiceStudio: onOpenVoiceStudio,
                    onOpenTranscript: onOpenTranscript
                )

                Text("Made by Anthony with ⌨️")
                    .font(.footnote)
                    .foregroundStyle(theme.secondaryText)
            }
            .padding(AuroraTheme.spacingLarge)
        }
    }
}

private struct NoticeBanner: View {
    let warning: AppWarning
    @Environment(\.aurora) private var theme

    var body: some View {
        Label(warning.message, systemImage: "exclamationmark.triangle.fill")
            .font(.footnote)
            .foregroundStyle(theme.warning)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, AuroraTheme.spacingSmall)
            .padding(.vertical, AuroraTheme.spacingXSmall)
            .background(AuroraCardBackground())
            .accessibilityLabel("Thông báo: \(warning.message)")
    }
}

private struct TopBar: View {

    let state: AppViewState
    let onOpenSettings: () -> Void

    @Environment(\.aurora) private var theme

    private var statusLabel: String {
        switch state.runState {
        case .stopped: "Đang dừng"
        case .listening: "Đang nghe"
        case .speaking: "Đang đọc"
        case .paused: "Tạm dừng"
        case .warning: "Cần xử lý"
        }
    }

    private var statusSymbol: String {
        switch state.runState {
        case .stopped: "pause.circle"
        case .listening: "waveform"
        case .speaking: "speaker.wave.2.fill"
        case .paused: "pause.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        }
    }

    private var statusColor: Color {
        switch state.runState {
        case .stopped: theme.secondaryText
        case .listening, .speaking: theme.status
        case .paused: theme.secondaryText
        case .warning: theme.warning
        }
    }

    var body: some View {
        HStack(spacing: AuroraTheme.spacingSmall) {
            // Icon thật của app thay cho SF Symbol chung chung. Lấy qua
            // `applicationIconImage` nên không phải nhét thêm file ảnh vào
            // module, và luôn khớp với icon đang hiện ở Dock.
            HStack(spacing: AuroraTheme.spacingXSmall) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 24, height: 24)
                Text("SubVoice")
                    .font(.headline)
                    .foregroundStyle(theme.primaryText)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("SubVoice")

            Spacer()

            Label(statusLabel, systemImage: statusSymbol)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(statusColor)
                .padding(.horizontal, AuroraTheme.spacingSmall)
                .padding(.vertical, AuroraTheme.spacingXSmall)
                .background(
                    Capsule().fill(theme.surface)
                        .overlay(Capsule().strokeBorder(theme.separator, lineWidth: 1))
                )
                .accessibilityLabel("Trạng thái: \(statusLabel)")

            Button(action: onOpenSettings) {
                Image(systemName: "gearshape")
                    .font(.system(size: 16, weight: .medium))
                    .frame(
                        width: AuroraTheme.minimumHitTarget,
                        height: AuroraTheme.minimumHitTarget
                    )
                    .foregroundStyle(theme.primaryText)
                    .background(
                        Circle().fill(theme.surface)
                            .overlay(Circle().strokeBorder(theme.separator, lineWidth: 1))
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Mở cài đặt")
        }
    }
}

private struct HeroCopyView: View {

    let content: DashboardContent

    @Environment(\.aurora) private var theme

    var body: some View {
        VStack(spacing: AuroraTheme.spacingXSmall) {
            Text(content.title)
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(theme.primaryText)
            Text(content.detail)
                .font(.body)
                .foregroundStyle(theme.secondaryText)
        }
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct PrimaryCaptureButton: View {

    let title: String
    let isCapturing: Bool
    let action: () -> Void

    @Environment(\.aurora) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: AuroraTheme.spacingXSmall) {
                Image(systemName: isCapturing ? "stop.fill" : "play.fill")
                Text(title).font(.headline)
                Text("⌥⌘V")
                    .font(.caption.monospaced())
                    .opacity(0.7)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, AuroraTheme.spacingLarge)
            .frame(height: 52)
            .background(
                Capsule().fill(
                    LinearGradient(
                        colors: [theme.accent, isCapturing ? theme.status : theme.accentSoft],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
            )
            .scaleEffect(isHovering && !reduceMotion ? 1.03 : 1.0)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .keyboardShortcut("v", modifiers: [.command, .option])
        .onHover { isHovering = $0 }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: isHovering)
        .accessibilityLabel(title)
        .accessibilityHint("Phím tắt Option Command V")
    }
}
