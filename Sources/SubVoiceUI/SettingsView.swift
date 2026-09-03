import SubVoiceCore
import SwiftUI

/// Cài đặt, chẩn đoán và About.
struct SettingsView: View {

    let state: AppViewState
    let viewModel: AppViewModel
    let appVersion: String
    let onClose: () -> Void

    @Environment(\.aurora) private var theme

    var body: some View {
        SheetScaffold(title: "Cài đặt", onClose: onClose) {
            ScrollView {
                VStack(alignment: .leading, spacing: AuroraTheme.spacingMedium) {
                    section("Giao diện") {
                        ThemePicker(
                            selected: state.settings.themeMode,
                            onSelect: { viewModel.send(.setTheme($0)) }
                        )
                    }

                    section("Khởi động") {
                        Toggle(
                            "Khởi động cùng máy",
                            isOn: Binding(
                                get: { state.launchAtLoginEnabled },
                                set: { viewModel.send(.setLaunchAtLogin($0)) }
                            )
                        )
                        .toggleStyle(.switch)
                    }

                    section("Chẩn đoán") {
                        DiagnosticRow(
                            symbolName: "record.circle",
                            title: "Screen Recording",
                            status: state.screenRecordingGranted
                                ? .ready("Đã được cấp quyền")
                                : .unavailable("Chưa có quyền"),
                            actionTitle: state.screenRecordingGranted
                                ? nil : "Mở System Settings",
                            action: { viewModel.send(.recover(.openScreenRecordingSettings)) }
                        )
                        DiagnosticRow(
                            symbolName: "person.wave.2",
                            title: "Giọng hệ thống",
                            status: state.systemVoiceStatus,
                            actionTitle: state.systemVoiceStatus.isReady
                                ? nil : "Mở Spoken Content",
                            action: { viewModel.send(.recover(.openSpokenContentSettings)) }
                        )
                        VStack(alignment: .leading, spacing: AuroraTheme.spacingXSmall) {
                            DiagnosticRow(
                                symbolName: "cpu",
                                title: "Kokoro",
                                status: state.kokoroStatus,
                                actionTitle: nil,
                                action: {}
                            )
                            if !state.kokoroAvailable {
                                KokoroInstallRow(state: state, viewModel: viewModel)
                            }
                        }
                    }

                    section("Giới thiệu") {
                        VStack(alignment: .leading, spacing: AuroraTheme.spacingXSmall) {
                            Text("SubVoice \(appVersion)")
                                .foregroundStyle(theme.primaryText)
                            Text("Đọc phụ đề trên màn hình bằng tiếng Việt, xử lý hoàn toàn "
                                + "trên máy. Ảnh màn hình, OCR và giọng đọc không rời khỏi thiết bị.")
                                .font(.footnote)
                                .foregroundStyle(theme.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                            Text("Giọng Kokoro dùng model Kokoro tiếng Việt chạy offline; "
                                + "giấy phép đi kèm trong thư mục runtime.")
                                .font(.footnote)
                                .foregroundStyle(theme.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                            Text("Made by Anthony with ⌨️")
                                .font(.footnote)
                                .foregroundStyle(theme.secondaryText)
                        }
                    }
                }
            }
        }
    }

    private func section<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: AuroraTheme.spacingXSmall) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(theme.secondaryText)
            VStack(alignment: .leading, spacing: AuroraTheme.spacingSmall) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(AuroraTheme.spacingSmall)
            .background(AuroraCardBackground())
        }
    }
}

/// Theme chỉ đổi khi người dùng KÍCH HOẠT một nút — không đổi khi hover hay
/// khi focus đi ngang qua.
private struct ThemePicker: View {

    let selected: ThemeMode
    let onSelect: (ThemeMode) -> Void

    @Environment(\.aurora) private var theme

    private func title(_ mode: ThemeMode) -> String {
        switch mode {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    private func symbol(_ mode: ThemeMode) -> String {
        switch mode {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max"
        case .dark: "moon"
        }
    }

    var body: some View {
        HStack(spacing: AuroraTheme.spacingXSmall) {
            ForEach(ThemeMode.allCases, id: \.self) { mode in
                let isSelected = mode == selected
                Button {
                    onSelect(mode)
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: symbol(mode))
                        Text(title(mode)).font(.caption)
                    }
                    .foregroundStyle(theme.primaryText)
                    .frame(maxWidth: .infinity, minHeight: AuroraTheme.minimumHitTarget)
                    .padding(.vertical, AuroraTheme.spacingXSmall)
                    .background(AuroraCardBackground(isHighlighted: isSelected))
                    .contentShape(
                        RoundedRectangle(cornerRadius: AuroraTheme.radiusMedium, style: .continuous)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Giao diện \(title(mode))")
                .accessibilityAddTraits(isSelected ? [.isSelected] : [])
            }
        }
    }
}

private struct DiagnosticRow: View {

    let symbolName: String
    let title: String
    let status: DiagnosticStatus
    let actionTitle: String?
    let action: () -> Void

    @Environment(\.aurora) private var theme

    var body: some View {
        HStack(spacing: AuroraTheme.spacingSmall) {
            Image(systemName: symbolName)
                .foregroundStyle(theme.secondaryText)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).foregroundStyle(theme.primaryText)
                Label(
                    status.message,
                    systemImage: status.isReady ? "checkmark.circle" : "exclamationmark.circle"
                )
                .font(.footnote)
                .foregroundStyle(status.isReady ? theme.status : theme.warning)
            }
            Spacer(minLength: 0)
            if let actionTitle {
                Button(actionTitle, action: action)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(title): \(status.message)")
    }
}
