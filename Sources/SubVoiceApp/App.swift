import AppKit

// Dùng @main thay cho main.swift: code top-level trong main.swift là nonisolated
// nên không khởi tạo được AppDelegate (vốn @MainActor). File này KHÔNG được
// đặt tên main.swift, nếu không trình biên dịch sẽ báo trùng điểm vào.
@main
struct SubVoiceMain {

    /// `NSApplication.delegate` là tham chiếu yếu, nên phải giữ delegate ở đây.
    @MainActor static var retainedDelegate: AppDelegate?

    @MainActor
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        retainedDelegate = delegate
        application.delegate = delegate
        // Có Dock icon và cửa sổ chính; menu bar vẫn giữ cho thao tác nhanh.
        application.setActivationPolicy(.regular)
        ApplicationMenu.install(into: application)
        application.run()
    }
}
