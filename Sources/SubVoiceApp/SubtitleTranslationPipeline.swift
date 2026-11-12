import Foundation
import SubVoiceCore

/// Chỉ một câu được dịch tại một thời điểm. Generation khoá cả kết quả lẫn
/// lỗi đến trễ khi người dùng dừng, đổi vùng hoặc cửa sổ nguồn bị che.
@MainActor
final class SubtitleTranslationPipeline {
    var onResult: ((String, String) -> Void)?
    var onError: ((Error) -> Void)?

    private let translate: (String) async throws -> String
    private var buffer = SubtitleTextBuffer()
    private var pending: [String] = []
    private var generation = UUID()
    private var worker: Task<Void, Never>?
    private var settle: Task<Void, Never>?
    private var lastInput: String?

    init(translate: @escaping (String) async throws -> String) {
        self.translate = translate
    }

    func submit(_ text: String) {
        guard let normalized = TextGate.normalize(text), normalized != lastInput else { return }
        lastInput = normalized
        for ready in buffer.submit(normalized) { enqueue(ready) }
        settle?.cancel()
        let current = generation
        settle = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(500)) }
            catch { return }
            guard let self, self.generation == current else { return }
            if let ready = self.buffer.flush() { self.enqueue(ready) }
        }
    }

    func endSubtitle() {
        settle?.cancel()
        settle = nil
        lastInput = nil
        if let ready = buffer.endSubtitle() { enqueue(ready) }
    }

    func reset() {
        generation = UUID()
        settle?.cancel()
        settle = nil
        worker?.cancel()
        worker = nil
        pending.removeAll()
        lastInput = nil
        buffer.reset()
    }

    private func enqueue(_ text: String) {
        pending.append(text)
        guard worker == nil else { return }
        let current = generation
        worker = Task { [weak self] in await self?.drain(generation: current) }
    }

    private func drain(generation current: UUID) async {
        defer { if generation == current { worker = nil } }
        while generation == current, !Task.isCancelled, !pending.isEmpty {
            let source = pending.removeFirst()
            do {
                let target = try await translate(source).trimmingCharacters(in: .whitespacesAndNewlines)
                guard generation == current, !Task.isCancelled else { return }
                guard !target.isEmpty else { throw TranslationPipelineError.emptyResult }
                onResult?(source, target)
            } catch {
                guard generation == current, !Task.isCancelled else { return }
                pending.removeAll()
                onError?(error)
                return
            }
        }
    }
}

private enum TranslationPipelineError: LocalizedError {
    case emptyResult
    var errorDescription: String? { "Bộ dịch không trả về bản tiếng Việt. Hãy thử lại." }
}
