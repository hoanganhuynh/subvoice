import SwiftUI

/// Điểm vào của toàn bộ giao diện cửa sổ chính.
public struct SubVoiceRootView: View {

    @ObservedObject private var viewModel: AppViewModel

    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: 24) {
            Text("SubVoice")
                .font(.largeTitle.weight(.semibold))
            Text(statusText)
                .font(.title3)
            Button(viewModel.state.isCapturing ? "Dừng đọc" : "Bắt đầu đọc") {
                viewModel.send(.toggleCapture)
            }
            .keyboardShortcut("v", modifiers: [.command, .option])
            Text("Made by Anthony with ⌨️")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }

    private var statusText: String {
        switch viewModel.state.runState {
        case .stopped: "Đang dừng"
        case .listening: "Đang nghe"
        case .speaking: "Đang đọc"
        case .warning(let warning): warning.message
        }
    }
}
