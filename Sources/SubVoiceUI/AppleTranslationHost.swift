import SwiftUI
@preconcurrency import Translation

@available(macOS 15, *)
struct AppleTranslationHost: View {
    @ObservedObject var bridge: TranslationBridge
    @State private var configuration: TranslationSession.Configuration?

    var body: some View {
        Color.clear
            .frame(width: 1, height: 1)
            .accessibilityHidden(true)
            .onAppear { bridge.hostConnected = true }
            .task { await bridge.refreshAvailability() }
            .onDisappear {
                bridge.hostConnected = false
                bridge.cancel()
            }
            .onChange(of: bridge.request?.id) {
                guard bridge.request != nil else { configuration = nil; return }
                if configuration != nil { configuration?.invalidate() }
                else {
                    configuration = TranslationSession.Configuration(
                        source: Locale.Language(identifier: "en"),
                        target: Locale.Language(identifier: "vi")
                    )
                }
            }
            .translationTask(configuration) { session in
                guard let request = bridge.request, !Task.isCancelled else { return }
                do {
                    try await session.prepareTranslation()
                    try Task.checkCancellation()
                    let translated: String
                    if let text = request.text { translated = try await session.translate(text).targetText }
                    else { translated = "" }
                    try Task.checkCancellation()
                    bridge.complete(id: request.id, result: .success(translated))
                } catch {
                    bridge.complete(id: request.id, result: .failure(error))
                }
            }
    }
}
