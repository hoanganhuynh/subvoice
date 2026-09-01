import AppKit
import SubVoiceCore
import SubVoiceUI
import SwiftUI

/// Cửa sổ chính: `NSWindow` của AppKit bọc lấy root view SwiftUI.
///
/// Giữ lifecycle ở AppKit vì status item, overlay chọn vùng và global hotkey
/// đều đã sống ở đó; SwiftUI chỉ lo layout, animation và accessibility.
@MainActor
final class MainWindowController: NSObject, NSWindowDelegate {

    private let window: NSWindow

    var isVisible: Bool { window.isVisible }

    init(viewModel: AppViewModel) {
        let root = SubVoiceRootView(viewModel: viewModel)
        let host = NSHostingController(rootView: root)
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 620),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        super.init()
        window.delegate = self
        window.contentMinSize = NSSize(width: 720, height: 540)
        window.contentViewController = host
        window.title = "SubVoice"
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("SubVoice.MainWindow")
        window.center()
    }

    func show() {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func apply(theme: ThemeMode) {
        window.appearance = switch theme {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }

    /// Đóng cửa sổ chỉ ẩn nó đi. App vẫn chạy trên menu bar và pipeline đang
    /// đọc không bị ngắt.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }
}
