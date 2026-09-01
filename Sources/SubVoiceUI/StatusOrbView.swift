import SwiftUI

/// Chỉ báo trạng thái ở trung tâm màn hình.
///
/// Màu KHÔNG bao giờ là kênh thông tin duy nhất: mỗi trạng thái có icon riêng
/// và một nhãn accessibility riêng.
struct StatusOrbView: View {

    let runState: AppRunState

    @Environment(\.aurora) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPulsing = false

    private var content: DashboardContent { DashboardContent(runState: runState) }

    private var tint: Color {
        switch runState {
        case .stopped: theme.accent
        case .listening, .speaking: theme.status
        case .warning: theme.warning
        }
    }

    private var accessibilityText: String {
        switch runState {
        case .stopped: "Trạng thái: đang dừng"
        case .listening: "Trạng thái: đang nghe"
        case .speaking: "Trạng thái: đang đọc"
        case .warning(let warning): "Trạng thái: cảnh báo. \(warning.message)"
        }
    }

    private var isActive: Bool {
        switch runState {
        case .listening, .speaking: true
        case .stopped, .warning: false
        }
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [tint.opacity(0.45), tint.opacity(0.0)],
                        center: .center,
                        startRadius: 8,
                        endRadius: 96
                    )
                )
                .frame(width: 192, height: 192)
                .scaleEffect(isPulsing ? 1.06 : 1.0)

            Circle()
                .fill(
                    LinearGradient(
                        colors: [theme.accent.opacity(0.9), tint.opacity(0.9)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 112, height: 112)
                .overlay(Circle().strokeBorder(theme.separator, lineWidth: 1))

            Image(systemName: content.symbolName)
                .font(.system(size: 44, weight: .medium))
                .foregroundStyle(.white)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .onAppear { updatePulse() }
        .onChange(of: runState) { _, _ in updatePulse() }
        .onChange(of: reduceMotion) { _, _ in updatePulse() }
    }

    private func updatePulse() {
        guard isActive, !reduceMotion else {
            withAnimation(.easeOut(duration: 0.2)) { isPulsing = false }
            return
        }
        withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
            isPulsing = true
        }
    }
}
