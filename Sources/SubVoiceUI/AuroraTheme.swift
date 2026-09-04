import SwiftUI

/// Bảng màu và khoảng cách của hướng mỹ thuật Cinematic Aurora.
///
/// Màu được giải theo `ColorScheme` và `ColorSchemeContrast` rồi truyền qua
/// environment, thay vì dùng `NSColor` dynamic provider: cách này giữ toàn bộ
/// target ở Swift 6 concurrency và làm chế độ Increase Contrast trở thành một
/// biến thể tường minh chứ không phải hiệu ứng phụ.
public struct AuroraTheme: Equatable, Sendable {

    // Nền và bề mặt
    public let background: Color
    public let backgroundGlowTop: Color
    public let backgroundGlowBottom: Color
    public let surface: Color
    public let surfaceHover: Color
    public let separator: Color

    // Chữ
    public let primaryText: Color
    public let secondaryText: Color

    // Nhấn và trạng thái
    public let accent: Color
    public let accentSoft: Color
    public let status: Color
    public let warning: Color
    public let error: Color
    public let focus: Color

    // Lưới 8 điểm
    public static let spacingXSmall: CGFloat = 8
    public static let spacingSmall: CGFloat = 16
    public static let spacingMedium: CGFloat = 24
    public static let spacingLarge: CGFloat = 32

    public static let radiusSmall: CGFloat = 8
    public static let radiusMedium: CGFloat = 16
    public static let radiusLarge: CGFloat = 24

    /// Kích thước chạm tối thiểu theo hướng dẫn accessibility của Apple.
    public static let minimumHitTarget: CGFloat = 44

    public static func resolve(
        scheme: ColorScheme,
        contrast: ColorSchemeContrast = .standard
    ) -> AuroraTheme {
        let boosted = contrast == .increased
        return scheme == .dark
            ? dark(boosted: boosted)
            : light(boosted: boosted)
    }

    private static func dark(boosted: Bool) -> AuroraTheme {
        AuroraTheme(
            // Không dùng đen tuyệt đối: nền hơi lạnh giữ được chiều sâu khi
            // đặt cạnh glow tím–cyan.
            background: Color(red: 0.043, green: 0.051, blue: 0.075),
            backgroundGlowTop: Color(red: 0.35, green: 0.20, blue: 0.75)
                .opacity(boosted ? 0.10 : 0.22),
            backgroundGlowBottom: Color(red: 0.05, green: 0.55, blue: 0.70)
                .opacity(boosted ? 0.08 : 0.18),
            surface: Color(red: 0.086, green: 0.098, blue: 0.137),
            surfaceHover: Color(red: 0.125, green: 0.141, blue: 0.196),
            separator: Color.white.opacity(boosted ? 0.34 : 0.12),
            primaryText: boosted ? .white : Color(red: 0.949, green: 0.961, blue: 0.984),
            secondaryText: boosted
                ? Color(red: 0.85, green: 0.87, blue: 0.92)
                : Color(red: 0.604, green: 0.643, blue: 0.722),
            accent: Color(red: 0.635, green: 0.478, blue: 0.988),
            accentSoft: Color(red: 0.769, green: 0.671, blue: 0.996),
            status: Color(red: 0.400, green: 0.851, blue: 0.937),
            warning: Color(red: 0.984, green: 0.749, blue: 0.286),
            error: Color(red: 0.984, green: 0.514, blue: 0.478),
            focus: Color(red: 0.769, green: 0.671, blue: 0.996)
        )
    }

    private static func light(boosted: Bool) -> AuroraTheme {
        AuroraTheme(
            background: Color(red: 0.965, green: 0.969, blue: 0.984),
            backgroundGlowTop: Color(red: 0.45, green: 0.30, blue: 0.85)
                .opacity(boosted ? 0.05 : 0.14),
            backgroundGlowBottom: Color(red: 0.10, green: 0.55, blue: 0.70)
                .opacity(boosted ? 0.04 : 0.10),
            surface: .white,
            surfaceHover: Color(red: 0.937, green: 0.945, blue: 0.969),
            separator: Color.black.opacity(boosted ? 0.34 : 0.12),
            primaryText: boosted ? .black : Color(red: 0.078, green: 0.086, blue: 0.122),
            secondaryText: boosted
                ? Color(red: 0.16, green: 0.18, blue: 0.24)
                : Color(red: 0.353, green: 0.388, blue: 0.475),
            accent: Color(red: 0.427, green: 0.157, blue: 0.851),
            accentSoft: Color(red: 0.545, green: 0.361, blue: 0.965),
            status: Color(red: 0.055, green: 0.455, blue: 0.565),
            warning: Color(red: 0.706, green: 0.325, blue: 0.035),
            error: Color(red: 0.725, green: 0.110, blue: 0.110),
            focus: Color(red: 0.427, green: 0.157, blue: 0.851)
        )
    }
}

private struct AuroraThemeKey: EnvironmentKey {
    static let defaultValue = AuroraTheme.resolve(scheme: .dark)
}

extension EnvironmentValues {
    var aurora: AuroraTheme {
        get { self[AuroraThemeKey.self] }
        set { self[AuroraThemeKey.self] = newValue }
    }
}

/// Nền gradient dùng chung cho cửa sổ chính.
struct AuroraBackground: View {
    @Environment(\.aurora) private var theme

    var body: some View {
        ZStack {
            theme.background
            RadialGradient(
                colors: [theme.backgroundGlowTop, .clear],
                center: .init(x: 0.15, y: 0.0),
                startRadius: 0,
                endRadius: 620
            )
            RadialGradient(
                colors: [theme.backgroundGlowBottom, .clear],
                center: .init(x: 0.9, y: 1.0),
                startRadius: 0,
                endRadius: 560
            )
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

/// Thẻ nền dùng cho control dock và các nhóm cài đặt.
struct AuroraCardBackground: View {
    @Environment(\.aurora) private var theme
    var isHighlighted = false

    var body: some View {
        RoundedRectangle(cornerRadius: AuroraTheme.radiusMedium, style: .continuous)
            .fill(isHighlighted ? theme.surfaceHover : theme.surface)
            .overlay(
                RoundedRectangle(cornerRadius: AuroraTheme.radiusMedium, style: .continuous)
                    .strokeBorder(isHighlighted ? theme.accent : theme.separator, lineWidth: 1)
            )
    }
}
