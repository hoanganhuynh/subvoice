import SubVoiceCore
import SwiftUI

/// Lịch sử phiên: tìm kiếm, sao chép và xoá.
///
/// Danh sách này chỉ sống trong bộ nhớ tiến trình — thoát app là mất, đúng như
/// cam kết riêng tư của SubVoice.
struct TranscriptDrawerView: View {

    let state: AppViewState
    let viewModel: AppViewModel
    let onClose: () -> Void

    @Environment(\.aurora) private var theme
    @State private var query = ""
    @State private var confirmClear = false

    private var filtered: [TranscriptEntry] { state.transcript.matching(query) }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    var body: some View {
        SheetScaffold(title: "Lịch sử phiên", onClose: onClose) {
            VStack(spacing: AuroraTheme.spacingSmall) {
                HStack {
                    Text("\(filtered.count) câu")
                        .font(.subheadline)
                        .foregroundStyle(theme.secondaryText)
                    Spacer()
                    Button("Sao chép kết quả") {
                        viewModel.send(.copyTranscript(filtered.map(\.id)))
                    }
                    .disabled(filtered.isEmpty)
                }

                TextField("Tìm trong phiên", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Tìm trong lịch sử phiên")

                transcriptListOrEmptyState

                HStack {
                    Button("Xoá lịch sử", role: .destructive) { confirmClear = true }
                        .disabled(state.transcript.entries.isEmpty)
                    Spacer()
                    Text("Lịch sử tự xoá khi bạn thoát SubVoice.")
                        .font(.footnote)
                        .foregroundStyle(theme.secondaryText)
                }
            }
            .confirmationDialog(
                "Xoá \(state.transcript.entries.count) câu trong phiên này?",
                isPresented: $confirmClear,
                titleVisibility: .visible
            ) {
                Button("Xoá lịch sử", role: .destructive) {
                    viewModel.send(.clearTranscript)
                }
                Button("Huỷ", role: .cancel) {}
            }
        }
    }

    @ViewBuilder
    private var transcriptListOrEmptyState: some View {
        if filtered.isEmpty {
            VStack(spacing: AuroraTheme.spacingXSmall) {
                Image(systemName: "text.quote")
                    .font(.system(size: 28))
                    .foregroundStyle(theme.secondaryText)
                    .accessibilityHidden(true)
                Text(state.transcript.entries.isEmpty
                    ? "Lịch sử xuất hiện sau khi SubVoice đọc câu đầu tiên."
                    : "Không có câu nào khớp với từ khoá.")
                    .font(.callout)
                    .foregroundStyle(theme.secondaryText)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(AuroraTheme.spacingMedium)
            .background(AuroraCardBackground())
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: AuroraTheme.spacingXSmall) {
                    ForEach(filtered) { entry in
                        TranscriptRow(entry: entry) {
                            viewModel.send(.copyTranscript([entry.id]))
                        }
                    }
                }
            }
            .frame(maxHeight: .infinity)
        }
    }

    private struct TranscriptRow: View {

        let entry: TranscriptEntry
        let onCopy: () -> Void

        @Environment(\.aurora) private var theme

        var body: some View {
            HStack(alignment: .top, spacing: AuroraTheme.spacingSmall) {
                Text(TranscriptDrawerView.timeFormatter.string(from: entry.timestamp))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(theme.secondaryText)
                Text(entry.text)
                    .foregroundStyle(theme.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button(action: onCopy) {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Sao chép câu này")
            }
            .padding(AuroraTheme.spacingXSmall)
            .background(AuroraCardBackground())
        }
    }
}
