import AppKit
import SubVoiceCore

/// Overlay mờ phủ mọi màn hình, cho kéo chuột chọn một vùng.
/// `Esc` huỷ. Trả về vùng đã chuyển sẵn sang hệ toạ độ mà `SCStream` cần.
final class RegionSelector {

    private var overlays: [SelectionOverlay] = []
    private var completion: ((SelectedRegion?) -> Void)?

    func begin(completion: @escaping (SelectedRegion?) -> Void) {
        guard overlays.isEmpty else { return }
        self.completion = completion

        NSApp.activate(ignoringOtherApps: true)
        overlays = NSScreen.screens.map { screen in
            let overlay = SelectionOverlay(screen: screen)
            overlay.onFinish = { [weak self] globalRect in
                self?.finish(globalRect: globalRect, screen: screen)
            }
            overlay.onCancel = { [weak self] in self?.finish(globalRect: nil, screen: nil) }
            overlay.makeKeyAndOrderFront(nil)
            return overlay
        }
    }

    private func finish(globalRect: CGRect?, screen: NSScreen?) {
        overlays.forEach { $0.close() }
        overlays.removeAll()

        let handler = completion
        completion = nil

        guard let globalRect, let screen, globalRect.width >= 8, globalRect.height >= 8 else {
            handler?(nil)
            return
        }

        let displayID = (screen.deviceDescription[.init("NSScreenNumber")] as? NSNumber)?
            .uint32Value ?? CGMainDisplayID()

        let local = Geometry.toDisplayLocalTopLeft(
            globalRect: globalRect,
            displayFrame: screen.frame
        )
        guard let clamped = Geometry.clamped(local, toDisplaySize: screen.frame.size) else {
            handler?(nil)
            return
        }

        handler?(SelectedRegion(
            displayID: displayID,
            rect: clamped,
            scale: screen.backingScaleFactor
        ))
    }
}

/// Một cửa sổ overlay cho một màn hình.
private final class SelectionOverlay: NSWindow {
    var onFinish: ((CGRect) -> Void)?
    var onCancel: (() -> Void)?

    private let selectionView = SelectionView()

    init(screen: NSScreen) {
        // Bản có tham số `screen:` là convenience initializer nên subclass không
        // gọi được. Dùng bản designated rồi tự đặt frame theo màn hình.
        super.init(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        setFrame(screen.frame, display: false)
        level = .screenSaver
        backgroundColor = NSColor.black.withAlphaComponent(0.25)
        isOpaque = false
        hasShadow = false
        ignoresMouseEvents = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        selectionView.frame = NSRect(origin: .zero, size: screen.frame.size)
        selectionView.autoresizingMask = [.width, .height]
        selectionView.onFinish = { [weak self] localRect in
            guard let self else { return }
            // Toạ độ trong view -> toạ độ toàn cục AppKit.
            let global = CGRect(
                x: localRect.minX + self.frame.minX,
                y: localRect.minY + self.frame.minY,
                width: localRect.width,
                height: localRect.height
            )
            self.onFinish?(global)
        }
        selectionView.onCancel = { [weak self] in self?.onCancel?() }
        contentView = selectionView
    }

    override var canBecomeKey: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}

private final class SelectionView: NSView {
    var onFinish: ((CGRect) -> Void)?
    var onCancel: (() -> Void)?

    private var anchor: NSPoint?
    private var current: NSPoint?

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func mouseDown(with event: NSEvent) {
        anchor = convert(event.locationInWindow, from: nil)
        current = anchor
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        current = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        current = convert(event.locationInWindow, from: nil)
        guard let rect = selectionRect else {
            onCancel?()
            return
        }
        onFinish?(rect)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {   // Esc
            onCancel?()
        }
    }

    override var acceptsFirstResponder: Bool { true }

    private var selectionRect: CGRect? {
        guard let anchor, let current else { return nil }
        let rect = CGRect(
            x: min(anchor.x, current.x),
            y: min(anchor.y, current.y),
            width: abs(current.x - anchor.x),
            height: abs(current.y - anchor.y)
        )
        return rect.width >= 8 && rect.height >= 8 ? rect : nil
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let rect = selectionRect else { return }
        // Khoét vùng đã chọn cho sáng lên, viền rõ để thấy chính xác biên.
        NSColor.clear.setFill()
        rect.fill(using: .copy)
        NSColor.systemBlue.setStroke()
        let path = NSBezierPath(rect: rect)
        path.lineWidth = 2
        path.stroke()
    }
}
