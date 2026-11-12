import Foundation
import SubVoiceCore

/// Chỉ một câu được dịch tại một thời điểm. Generation khoá cả kết quả lẫn
/// lỗi đến trễ khi người dùng dừng, đổi vùng hoặc cửa sổ nguồn bị che.
@MainActor
final class SubtitleTranslationPipeline {
    var onResult: ((String, String) -> Void)?
    var onError: ((Error) -> Void)?
    var onWaitingChange: ((Bool) -> Void)?

    private let translate: (String) async throws -> String
    private let stabilizationDelay: Duration
    private let unpunctuatedDelay: Duration
    private var buffer = SubtitleTextBuffer()
    private var pending: [String] = []
    private var generation = UUID()
    private var worker: Task<Void, Never>?
    private var settle: Task<Void, Never>?
    private var lastInput: String?
    private var wasWaiting = false

    init(translate: @escaping (String) async throws -> String,
         stabilizationDelay: Duration = .milliseconds(350),
         unpunctuatedDelay: Duration = .milliseconds(1800)) {
        self.translate = translate
        self.stabilizationDelay = max(.zero, stabilizationDelay)
        self.unpunctuatedDelay = max(self.stabilizationDelay, unpunctuatedDelay)
    }

    func submit(_ text: String) {
        guard let normalized = TextGate.normalize(text), normalized != lastInput else { return }
        lastInput = normalized
        for ready in buffer.submit(normalized) { enqueue(ready) }
        publishWaiting()
        settle?.cancel()
        let current = generation
        settle = Task { [weak self] in
            guard let self else { return }
            do { try await Task.sleep(for: self.stabilizationDelay) }
            catch { return }
            guard self.generation == current else { return }
            self.flushReady(allowUnpunctuated: false)
            do { try await Task.sleep(for: self.unpunctuatedDelay - self.stabilizationDelay) }
            catch { return }
            guard self.generation == current else { return }
            // Chờ lâu hơn cho nguồn không có dấu câu. Cụm còn thiếu bổ ngữ
            // hoặc mệnh đề phụ vẫn ở lại buffer, không bị timeout ép đi dịch.
            self.flushReady(allowUnpunctuated: true)
        }
    }

    func endSubtitle() {
        settle?.cancel()
        settle = nil
        lastInput = nil
        if let ready = buffer.endSubtitle() { enqueue(ready) }
        flushReady(allowUnpunctuated: true)
    }

    private func flushReady(allowUnpunctuated: Bool) {
        while let ready = buffer.flush(allowUnpunctuated: allowUnpunctuated) { enqueue(ready) }
        publishWaiting()
    }

    private func publishWaiting() {
        let waiting = buffer.hasPendingText
        guard waiting != wasWaiting else { return }
        wasWaiting = waiting
        onWaitingChange?(waiting)
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
        publishWaiting()
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
