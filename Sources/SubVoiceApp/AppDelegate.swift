import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let coordinator = AppCoordinator()

    func applicationDidFinishLaunching(_ notification: Notification) {
        coordinator.start()
    }

    /// Bấm Dock icon lúc cửa sổ đã bị đóng phải mở lại cửa sổ, không phải mở
    /// một cửa sổ mới hay không làm gì.
    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows: Bool
    ) -> Bool {
        coordinator.showMainWindow()
        return true
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }
}
