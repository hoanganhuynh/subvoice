import Foundation

/// Cầu nối hai chiều giữa coordinator và SwiftUI: coordinator gọi `apply`,
/// giao diện gọi `send`. Không có đường nào khác.
@MainActor
public final class AppViewModel: ObservableObject {

    @Published public private(set) var state: AppViewState

    /// Coordinator gắn một lần lúc khởi động.
    public var onIntent: ((AppIntent) -> Void)?

    public init(state: AppViewState) {
        self.state = state
    }

    public func send(_ intent: AppIntent) {
        onIntent?(intent)
    }

    public func apply(_ update: (inout AppViewState) -> Void) {
        var next = state
        update(&next)
        guard next != state else { return }
        state = next
    }
}
