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

    var body: some View {
        ZStack {
            AuroraBackground()

            VStack(spacing: AuroraTheme.spacingMedium) {
                TopBar(state: state, onOpenSettings: onOpenSettings)

                Spacer(minLength: AuroraTheme.spacingXSmall)

                StatusOrbView(runState: state.runState)
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

private struct TopBar: View {

    let state: AppViewState
    let onOpenSettings: () -> Void

    @Environment(\.aurora) private var theme

    private var statusLabel: String {
        switch state.runState {
        case .stopped: "Đang dừng"
        case .listening: "Đang nghe"
        case .speaking: "Đang đọc"
        case .warning: "Cần xử lý"
        }
    }

    private var statusSymbol: String {
        switch state.runState {
        case .stopped: "pause.circle"
        case .listening: "waveform"
        case .speaking: "speaker.wave.2.fill"
        case .warning: "exclamationmark.triangle.fill"
        }
    }

    private var statusColor: Color {
        switch state.runState {
        case .stopped: theme.secondaryText
        case .listening, .speaking: theme.status
        case .warning: theme.warning
        }
    }

    var body: some View {
        HStack(spacing: AuroraTheme.spacingSmall) {
            Label("SubVoice", systemImage: "captions.bubble.fill")
                .font(.headline)
                .foregroundStyle(theme.primaryText)
                .labelStyle(.titleAndIcon)

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
