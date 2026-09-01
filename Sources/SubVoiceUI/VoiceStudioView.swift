import SubVoiceCore
import SwiftUI

/// Voice Studio: bộ đọc, giọng, tốc độ, âm lượng và nút thử giọng.
struct VoiceStudioView: View {

    let state: AppViewState
    let viewModel: AppViewModel
    let onClose: () -> Void

    @Environment(\.aurora) private var theme

    private static let rateLabels = ["Rất chậm", "Chậm", "Vừa", "Nhanh", "Rất nhanh"]

    private var rateLabel: String {
        let index = Settings.ratePresets.firstIndex {
            abs($0 - state.settings.speechRate) < 0.001
        } ?? 2
        let label = Self.rateLabels[index]
        guard state.settings.speechEngine == .kokoro else { return label }
        // Kokoro nhận hệ số nhân chứ không nhận dải rate của giọng hệ thống,
        // nên hiện luôn con số đã quy đổi để người dùng biết mình đang chọn gì.
        let speed = SpeechRateMapping.kokoroSpeed(for: state.settings.speechRate)
        return String(format: "%@ · %.2f×", label, speed)
    }

    private var previewDisabledReason: String? {
        state.isCapturing ? "Dừng đọc phụ đề trước khi thử giọng." : nil
    }

    var body: some View {
        SheetScaffold(title: "Voice Studio", onClose: onClose) {
            VStack(alignment: .leading, spacing: AuroraTheme.spacingMedium) {
                VStack(alignment: .leading, spacing: AuroraTheme.spacingXSmall) {
                    Text("Bộ đọc").font(.subheadline.weight(.semibold))
                        .foregroundStyle(theme.primaryText)
                    EngineSelector(state: state, viewModel: viewModel)
                    if !state.kokoroAvailable {
                        Label(state.kokoroStatus.message, systemImage: "info.circle")
                            .font(.footnote)
                            .foregroundStyle(theme.secondaryText)
                    }
                }

                if state.voices.isEmpty {
                    Label("Không có giọng khả dụng", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(theme.warning)
                } else {
                    Picker("Giọng đọc", selection: Binding(
                        get: { state.selectedVoiceIdentifier ?? state.voices[0].identifier },
                        set: { viewModel.send(.changeVoice($0)) }
                    )) {
                        ForEach(state.voices) { voice in
                            Text(voice.name).tag(voice.identifier)
                        }
                    }
                }

                LabeledSlider(
                    title: "Tốc độ đọc",
                    valueLabel: rateLabel,
                    value: Double(state.settings.speechRate),
                    range: Double(Settings.minimumRate)...Double(Settings.maximumRate),
                    step: 0.075,
                    accessibilityValue: rateLabel
                ) { viewModel.send(.changeRate(Float($0))) }

                LabeledSlider(
                    title: "Âm lượng",
                    valueLabel: "\(Int(state.settings.volume * 100))%",
                    value: Double(state.settings.volume),
                    range: 0...1,
                    step: 0.05,
                    accessibilityValue: "\(Int(state.settings.volume * 100)) phần trăm"
                ) { viewModel.send(.changeVolume(Float($0))) }

                HStack(spacing: AuroraTheme.spacingSmall) {
                    Button("Thử giọng") { viewModel.send(.previewVoice) }
                        .disabled(previewDisabledReason != nil)
                        .help(previewDisabledReason ?? "Đọc thử câu mẫu bằng cấu hình hiện tại")
                    if let previewDisabledReason {
                        Text(previewDisabledReason)
                            .font(.footnote)
                            .foregroundStyle(theme.secondaryText)
                    }
                }

                Text("Thay đổi có hiệu lực từ câu kế tiếp.")
                    .font(.footnote)
                    .foregroundStyle(theme.secondaryText)
            }
        }
    }
}

/// Bộ chọn engine dựng bằng hai `Button` thật thay vì `Picker`, để mục Kokoro
/// có thể bị vô hiệu hoá riêng khi runtime chưa được cài.
private struct EngineSelector: View {

    let state: AppViewState
    let viewModel: AppViewModel

    @Environment(\.aurora) private var theme

    var body: some View {
        HStack(spacing: AuroraTheme.spacingXSmall) {
            option(.system, title: "Hệ thống", detail: "Nhanh", enabled: true)
            option(
                .kokoro,
                title: "Kokoro",
                detail: "Tự nhiên, offline",
                enabled: state.kokoroAvailable
            )
        }
    }

    private func option(
        _ engine: SpeechEngine,
        title: String,
        detail: String,
        enabled: Bool
    ) -> some View {
        let isSelected = state.settings.speechEngine == engine
        return Button {
            viewModel.send(.changeEngine(engine))
        } label: {
            HStack(spacing: AuroraTheme.spacingXSmall) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.body.weight(.medium))
                    Text(detail).font(.caption).foregroundStyle(theme.secondaryText)
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(theme.primaryText)
            .padding(AuroraTheme.spacingXSmall)
            .frame(maxWidth: .infinity, minHeight: AuroraTheme.minimumHitTarget)
            .background(AuroraCardBackground(isHighlighted: isSelected))
            .contentShape(
                RoundedRectangle(cornerRadius: AuroraTheme.radiusMedium, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.5)
        .accessibilityLabel("\(title), \(detail)")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

private struct LabeledSlider: View {

    let title: String
    let valueLabel: String
    let value: Double
    let range: ClosedRange<Double>
    let step: Double
    let accessibilityValue: String
    let onChange: @MainActor (Double) -> Void

    @Environment(\.aurora) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: AuroraTheme.spacingXSmall) {
            HStack {
                Text(title).font(.subheadline.weight(.semibold))
                    .foregroundStyle(theme.primaryText)
                Spacer()
                Text(valueLabel).foregroundStyle(theme.secondaryText)
            }
            Slider(
                value: Binding(get: { value }, set: { onChange($0) }),
                in: range,
                step: step
            ) {
                Text(title)
            }
            .accessibilityValue(accessibilityValue)
        }
    }
}

/// Khung chung cho mọi sheet: tiêu đề, nút đóng và phím Escape.
struct SheetScaffold<Content: View>: View {

    let title: String
    let onClose: () -> Void
    @ViewBuilder let content: Content

    @Environment(\.aurora) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: AuroraTheme.spacingMedium) {
            HStack {
                Text(title).font(.title2.weight(.semibold))
                    .foregroundStyle(theme.primaryText)
                Spacer()
                Button("Đóng", action: onClose)
                    .keyboardShortcut(.cancelAction)
            }
            content
            Spacer(minLength: 0)
        }
        .padding(AuroraTheme.spacingLarge)
        .frame(minWidth: 520, minHeight: 420)
        .background(theme.background)
    }
}
