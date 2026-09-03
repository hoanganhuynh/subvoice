import SubVoiceCore
import SwiftUI

/// Điểm vào của toàn bộ giao diện cửa sổ chính.
///
/// Bảng màu được giải ở đây một lần rồi truyền xuống qua environment, nên
/// Light/Dark và Increase Contrast chỉ có đúng một chỗ quyết định.
public struct SubVoiceRootView: View {

    @ObservedObject private var viewModel: AppViewModel
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var route: SheetRoute?

    private let appVersion: String

    public init(viewModel: AppViewModel, appVersion: String = SubVoiceRootView.bundleVersion) {
        self.viewModel = viewModel
        self.appVersion = appVersion
    }

    public static var bundleVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
    }

    private enum SheetRoute: String, Identifiable {
        case voiceStudio, transcript, settings
        var id: String { rawValue }
    }

    private var theme: AuroraTheme {
        AuroraTheme.resolve(scheme: colorScheme, contrast: contrast)
    }

    public var body: some View {
        Group {
            if viewModel.state.settings.hasCompletedOnboarding {
                dashboard
            } else {
                OnboardingView(state: viewModel.state, viewModel: viewModel)
            }
        }
        .environment(\.aurora, theme)
        .sheet(item: $route) { route in
            sheet(for: route)
                .environment(\.aurora, theme)
        }
    }

    private var dashboard: some View {
        FocusDashboardView(
            state: viewModel.state,
            viewModel: viewModel,
            onOpenSettings: { route = .settings },
            onOpenVoiceStudio: { route = .voiceStudio },
            onOpenTranscript: { route = .transcript }
        )
    }

    @ViewBuilder
    private func sheet(for route: SheetRoute) -> some View {
        switch route {
        case .voiceStudio:
            VoiceStudioView(
                state: viewModel.state,
                viewModel: viewModel,
                onClose: { self.route = nil }
            )
        case .transcript:
            TranscriptDrawerView(
                state: viewModel.state,
                viewModel: viewModel,
                onClose: { self.route = nil }
            )
        case .settings:
            SettingsView(
                state: viewModel.state,
                viewModel: viewModel,
                appVersion: appVersion,
                onClose: { self.route = nil }
            )
        }
    }
}
