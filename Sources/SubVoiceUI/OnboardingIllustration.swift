import SwiftUI

/// Minh hoạ cho từng bước onboarding.
///
/// Vẽ bằng SF Symbols và hình khối thay vì nhúng ảnh bitmap: sắc nét ở mọi độ
/// phân giải, tự đổi màu theo light/dark và Increase Contrast, và không kéo
/// theo một pipeline asset chỉ để phục vụ năm màn hình.
struct OnboardingIllustration: View {

    let step: OnboardingStep

    @Environment(\.aurora) private var theme

    var body: some View {
        ZStack {
            heroGradient
            artwork
        }
        .frame(height: 272)
        .frame(maxWidth: .infinity)
        .clipShape(
            RoundedRectangle(cornerRadius: AuroraTheme.radiusLarge, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AuroraTheme.radiusLarge, style: .continuous)
                .strokeBorder(theme.separator, lineWidth: 1)
        )
        .accessibilityHidden(true)
    }

    /// Mỗi bước một góc gradient khác nhau, để lật qua lại thấy rõ mình đã đi
    /// tới đâu mà không cần đọc số.
    private var heroGradient: some View {
        let pair: (Color, Color) = switch step {
        case .welcome: (theme.accent, theme.status)
        case .screenRecording: (theme.status, theme.accentSoft)
        case .voice: (theme.accentSoft, theme.status)
        case .region: (theme.accent, theme.accentSoft)
        case .done: (theme.status, theme.accent)
        }
        return LinearGradient(
            colors: [pair.0.opacity(0.28), pair.1.opacity(0.16)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    @ViewBuilder
    private var artwork: some View {
        switch step {
        case .welcome: GlyphTile(symbol: "captions.bubble.fill")
        case .screenRecording: ScreenPermissionArt()
        case .voice: VoiceWaveArt()
        case .region: RegionArt()
        case .done: ShortcutKeysArt()
        }
    }
}

/// Ô vuông bo tròn nổi trên nền gradient, kiểu icon tile của macOS.
private struct GlyphTile: View {

    let symbol: String
    var size: CGFloat = 120

    @Environment(\.aurora) private var theme

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
            .fill(theme.surface)
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: symbol)
                    .font(.system(size: size * 0.44, weight: .medium))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [theme.accent, theme.status],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                    .strokeBorder(theme.separator, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.18), radius: 18, y: 8)
    }
}

/// Một màn hình thu nhỏ với dải phụ đề được khoanh vùng — nói bằng hình cái mà
/// bước cấp quyền đang xin.
private struct ScreenPermissionArt: View {

    @Environment(\.aurora) private var theme

    var body: some View {
        MiniScreen {
            VStack {
                Spacer()
                RoundedRectangle(cornerRadius: AuroraTheme.radiusSmall, style: .continuous)
                    .strokeBorder(theme.status, style: StrokeStyle(lineWidth: 2, dash: [5, 4]))
                    .background(
                        RoundedRectangle(
                            cornerRadius: AuroraTheme.radiusSmall,
                            style: .continuous
                        )
                        .fill(theme.status.opacity(0.14))
                    )
                    .frame(height: 26)
                    .padding(.horizontal, 22)
                    .padding(.bottom, 16)
            }
        }
        .overlay(alignment: .topTrailing) {
            Image(systemName: "record.circle")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(theme.warning)
                .padding(10)
                .background(Circle().fill(theme.surface))
                .shadow(color: .black.opacity(0.2), radius: 8, y: 3)
                .offset(x: 14, y: -10)
        }
    }
}

/// Dải cột sóng âm cạnh biểu tượng người nói.
private struct VoiceWaveArt: View {

    @Environment(\.aurora) private var theme

    private let heights: [CGFloat] = [14, 30, 46, 62, 44, 26, 38, 54, 22, 12]

    var body: some View {
        HStack(spacing: AuroraTheme.spacingSmall) {
            GlyphTile(symbol: "person.wave.2.fill", size: 84)
            HStack(alignment: .center, spacing: 6) {
                ForEach(Array(heights.enumerated()), id: \.offset) { index, height in
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [theme.accent, theme.status],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: 7, height: height)
                        .opacity(0.55 + Double(index % 3) * 0.15)
                }
            }
        }
    }
}

/// Màn hình thu nhỏ với khung chọn vùng đang được kéo.
private struct RegionArt: View {

    @Environment(\.aurora) private var theme

    var body: some View {
        MiniScreen {
            ZStack {
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(0..<3, id: \.self) { index in
                        Capsule()
                            .fill(theme.separator)
                            .frame(width: index == 1 ? 96 : 132, height: 6)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(18)

                VStack {
                    Spacer()
                    RoundedRectangle(cornerRadius: AuroraTheme.radiusSmall, style: .continuous)
                        .strokeBorder(theme.accent, lineWidth: 2)
                        .background(
                            RoundedRectangle(
                                cornerRadius: AuroraTheme.radiusSmall,
                                style: .continuous
                            )
                            .fill(theme.accent.opacity(0.16))
                        )
                        .frame(height: 30)
                        .overlay(alignment: .bottomTrailing) {
                            Circle()
                                .fill(theme.accent)
                                .frame(width: 9, height: 9)
                                .offset(x: 4, y: 4)
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 14)
                }
            }
        }
    }
}

/// Ba phím ⌥ ⌘ V dựng như key cap thật.
private struct ShortcutKeysArt: View {
    var body: some View {
        HStack(spacing: AuroraTheme.spacingSmall) {
            KeyCap(label: "⌥")
            KeyCap(label: "⌘")
            KeyCap(label: "V")
        }
    }
}

private struct KeyCap: View {

    let label: String

    @Environment(\.aurora) private var theme

    var body: some View {
        RoundedRectangle(cornerRadius: AuroraTheme.radiusMedium, style: .continuous)
            .fill(theme.surface)
            .frame(width: 74, height: 74)
            .overlay(
                Text(label)
                    .font(.system(size: 30, weight: .medium, design: .rounded))
                    .foregroundStyle(theme.primaryText)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AuroraTheme.radiusMedium, style: .continuous)
                    .strokeBorder(theme.separator, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.16), radius: 12, y: 5)
    }
}

/// Khung "màn hình" dùng chung cho hai minh hoạ có bối cảnh màn hình.
private struct MiniScreen<Content: View>: View {

    @ViewBuilder let content: Content

    @Environment(\.aurora) private var theme

    var body: some View {
        RoundedRectangle(cornerRadius: AuroraTheme.radiusMedium, style: .continuous)
            .fill(theme.surface)
            .frame(width: 210, height: 132)
            .overlay(content)
            .overlay(
                RoundedRectangle(cornerRadius: AuroraTheme.radiusMedium, style: .continuous)
                    .strokeBorder(theme.separator, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.18), radius: 16, y: 7)
    }
}

/// Chấm chỉ báo bước. Số thứ tự thật nằm ở nhãn accessibility của thanh trên,
/// nên chỗ này thuần trang trí.
struct OnboardingDots: View {

    let current: OnboardingStep

    @Environment(\.aurora) private var theme

    var body: some View {
        HStack(spacing: 7) {
            ForEach(OnboardingStep.allCases, id: \.self) { step in
                Capsule()
                    .fill(step == current ? theme.accent : theme.separator)
                    .frame(width: step == current ? 20 : 7, height: 7)
            }
        }
        .accessibilityHidden(true)
    }
}
