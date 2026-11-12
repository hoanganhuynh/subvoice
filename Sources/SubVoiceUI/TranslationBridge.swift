import Combine
import Foundation
@preconcurrency import Translation

public enum SubtitleTranslationStatus: Equatable, Sendable {
    case checking, needsDownload, preparing, ready
    case unavailable(String), failed(String)

    public var isReady: Bool { self == .ready }
    public var canPrepare: Bool {
        switch self {
        case .needsDownload, .failed: true
        default: false
        }
    }
    public var message: String {
        switch self {
        case .checking: "Đang kiểm tra bộ dịch Anh → Việt…"
        case .needsDownload: "Cần tải ngôn ngữ Anh và Việt một lần để dịch offline."
        case .preparing: "Đang chuẩn bị ngôn ngữ — hãy xác nhận trong hộp thoại macOS."
        case .ready: "Dịch Anh → Việt offline đã sẵn sàng."
        case .unavailable(let reason), .failed(let reason): reason
        }
    }
}

/// Chỉ chuyển dữ liệu qua ranh giới AppKit/SwiftUI. Session yêu cầu tải model
/// luôn nằm trong translationTask của view, không bị giữ ngoài vòng đời đó.
@MainActor
public final class TranslationBridge: ObservableObject {
    struct Request: Identifiable {
        let id: UUID
        let text: String?
    }

    @Published public private(set) var status: SubtitleTranslationStatus {
        didSet { onStatusChange?(status) }
    }
    @Published private(set) var request: Request?
    public var onStatusChange: ((SubtitleTranslationStatus) -> Void)?
    var hostConnected = false
    private var continuation: CheckedContinuation<String, Error>?
    private var preparationID: UUID?

    public init(supported: Bool = TranslationBridge.platformSupported) {
        status = supported ? .checking : .unavailable("Dịch Anh → Việt cần macOS 15 trở lên.")
    }

    public static var platformSupported: Bool {
        if #available(macOS 15, *) { return true }
        return false
    }

    public func refreshAvailability() async {
        guard #available(macOS 15, *), status != .preparing else { return }
        let availability = await LanguageAvailability().status(
            from: Locale.Language(identifier: "en"), to: Locale.Language(identifier: "vi")
        )
        guard status != .preparing else { return }
        switch availability {
        case .installed: status = .ready
        case .supported: status = .needsDownload
        case .unsupported: status = .unavailable("Máy này chưa hỗ trợ dịch Anh → Việt bằng Apple Translation.")
        @unknown default: status = .unavailable("Không xác định được khả năng dịch trên máy này.")
        }
    }

    public func prepare() async throws {
        if case .unavailable(let reason) = status { throw BridgeError(reason) }
        guard continuation == nil else { throw BridgeError("Đang chuẩn bị bộ dịch.") }
        let id = UUID()
        preparationID = id
        status = .preparing
        do {
            _ = try await perform(text: nil)
            guard preparationID == id else { throw CancellationError() }
            preparationID = nil
            status = .ready
        } catch {
            if preparationID == id {
                preparationID = nil
                status = error is CancellationError ? .needsDownload : .failed(error.localizedDescription)
            }
            throw error
        }
    }

    public func translate(_ text: String) async throws -> String {
        guard status.isReady else { throw BridgeError(status.message) }
        if #available(macOS 26, *) {
            // Không phụ thuộc cửa sổ đang hiện sau khi model đã tải xong.
            let session = TranslationSession(
                installedSource: Locale.Language(identifier: "en"),
                target: Locale.Language(identifier: "vi")
            )
            return try await session.translate(text).targetText
        }
        return try await perform(text: text)
    }

    public func cancel() {
        preparationID = nil
        let pending = continuation
        continuation = nil
        request = nil
        if status == .preparing { status = .needsDownload }
        pending?.resume(throwing: CancellationError())
    }

    private func perform(text: String?) async throws -> String {
        guard hostConnected else { throw BridgeError("Mở cửa sổ SubVoice để chuẩn bị bộ dịch rồi thử lại.") }
        try Task.checkCancellation()
        let id = UUID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { pending in
                guard !Task.isCancelled else { pending.resume(throwing: CancellationError()); return }
                guard continuation == nil else {
                    pending.resume(throwing: BridgeError("Bộ dịch đang xử lý một yêu cầu khác.")); return
                }
                continuation = pending
                request = Request(id: id, text: text)
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                if self?.request?.id == id { self?.cancel() }
            }
        }
    }

    func complete(id: UUID, result: Result<String, Error>) {
        guard request?.id == id else { return }
        let pending = continuation
        continuation = nil
        request = nil
        pending?.resume(with: result)
    }
}

private struct BridgeError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
