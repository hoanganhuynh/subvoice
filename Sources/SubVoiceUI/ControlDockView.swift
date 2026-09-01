import SubVoiceCore
import SwiftUI

/// Ba thẻ điều khiển ở đáy dashboard. Cả ba đều là `Button` thật để có sẵn
/// bàn phím, focus ring và VoiceOver.
struct ControlDockView: View {

    let state: AppViewState
    let viewModel: AppViewModel
    let onOpenVoiceStudio: () -> Void
    let onOpenTranscript: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: AuroraTheme.spacingSmall) {
            DockCard(
                symbolName: "rectangle.dashed",
                title: "Vùng đọc",
                detail: regionDetail,
                accessibilityHint: "Mở lớp phủ để chọn lại vùng phụ đề",
                action: { viewModel.send(.selectRegion) }
            )
            DockCard(
                symbolName: "waveform.and.person.filled",
                title: "Giọng đọc",
                detail: voiceDetail,
                accessibilityHint: "Mở Voice Studio để đổi bộ đọc, giọng, tốc độ và âm lượng",
                action: onOpenVoiceStudio
            )
            DockCard(
                symbolName: "text.quote",
                title: "Vừa đọc",
                detail: latestDetail,
                accessibilityHint: "Mở lịch sử phiên để tìm và sao chép câu đã đọc",
                action: onOpenTranscript
            )
        }
    }

    private var regionDetail: String {
        guard let region = state.region else { return "Chưa chọn vùng" }
        return "Màn hình \(region.displayID) · \(region.pixelWidth)×\(region.pixelHeight)"
    }

    private var voiceDetail: String {
        let engine = state.settings.speechEngine == .kokoro ? "Kokoro" : "Hệ thống"
        guard let name = state.selectedVoiceName else { return "\(engine) · chưa có giọng" }
        return "\(engine) · \(name)"
    }

    private var latestDetail: String {
        state.transcript.entries.first?.text ?? "Chưa có câu nào trong phiên này"
    }
}

private struct DockCard: View {

    let symbolName: String
    let title: String
    let detail: String
    let accessibilityHint: String
    let action: () -> Void

    @Environment(\.aurora) private var theme
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: AuroraTheme.spacingXSmall) {
                Label(title, systemImage: symbolName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(theme.secondaryText)
                Text(detail)
                    .font(.body)
                    .foregroundStyle(theme.primaryText)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
            .padding(AuroraTheme.spacingSmall)
            .background(AuroraCardBackground(isHighlighted: isHovering))
            .contentShape(
                RoundedRectangle(cornerRadius: AuroraTheme.radiusMedium, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityLabel("\(title): \(detail)")
        .accessibilityHint(accessibilityHint)
    }
}
