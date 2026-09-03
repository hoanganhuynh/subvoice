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
        // Mặc định NSHostingController ép cửa sổ co giãn theo kích thước lý
        // tưởng của SwiftUI, làm cửa sổ mở ra cao gấp ba lần thiết kế. Cửa sổ
        // tự quyết kích thước của nó.
        host.sizingOptions = []
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        super.init()
        window.delegate = self
        // Control dock ba thẻ và notice fallback cần không gian thật. 540pt
        // khiến nội dung dưới cùng bị cắt ở một số cỡ chữ Accessibility.
        window.contentMinSize = NSSize(width: 720, height: 620)
        window.contentViewController = host
        window.title = "SubVoice"
        // Thanh tiêu đề trong suốt để nền aurora chảy hết khung; nếu không,
        // `fullSizeContentView` sẽ vẽ thanh tiêu đề ĐÈ lên top bar.
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 820, height: 700))
        // Khôi phục vị trí người dùng đã kéo, nhưng chỉ SAU khi kích thước mặc
        // định đã được đặt, để một frame cũ hỏng không khoá cửa sổ ở kích
        // thước sai.
        window.setFrameAutosaveName("SubVoice.MainWindow")
        if !window.setFrameUsingName("SubVoice.MainWindow") {
            window.center()
        }
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
