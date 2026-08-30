import AppKit
import Carbon.HIToolbox

/// Phím tắt toàn cục qua Carbon. Không cần quyền Accessibility.
final class HotKeyManager {

    enum Action: UInt32 {
        case toggleSpeaking = 1
        case reselectRegion = 2
    }

    private var registered: [EventHotKeyRef?] = []
    fileprivate var handlers: [UInt32: () -> Void] = [:]
    private var eventHandler: EventHandlerRef?

    /// Đăng ký `⌥⌘V` bật/tắt đọc và `⌥⌘R` chọn lại vùng.
    /// - Returns: các hành động KHÔNG đăng ký được (phím đã bị app khác chiếm).
    @discardableResult
    func registerDefaults(
        onToggle: @escaping () -> Void,
        onReselect: @escaping () -> Void
    ) -> [Action] {
        installEventHandlerIfNeeded()

        var failures: [Action] = []
        let modifiers = UInt32(optionKey | cmdKey)

        if !register(.toggleSpeaking, keyCode: UInt32(kVK_ANSI_V), modifiers: modifiers, handler: onToggle) {
            failures.append(.toggleSpeaking)
        }
        if !register(.reselectRegion, keyCode: UInt32(kVK_ANSI_R), modifiers: modifiers, handler: onReselect) {
            failures.append(.reselectRegion)
        }
        return failures
    }

    func unregisterAll() {
        registered.forEach { if let ref = $0 { UnregisterEventHotKey(ref) } }
        registered.removeAll()
        handlers.removeAll()
    }

    private func register(
        _ action: Action,
        keyCode: UInt32,
        modifiers: UInt32,
        handler: @escaping () -> Void
    ) -> Bool {
        var ref: EventHotKeyRef?
        let id = EventHotKeyID(signature: OSType(0x53565543), id: action.rawValue)  // 'SVUC'
        let status = RegisterEventHotKey(keyCode, modifiers, id, GetEventDispatcherTarget(), 0, &ref)
        guard status == noErr else { return false }
        registered.append(ref)
        handlers[action.rawValue] = handler
        return true
    }

    private func installEventHandlerIfNeeded() {
        guard eventHandler == nil else { return }
        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let context = Unmanaged.passUnretained(self).toOpaque()

        InstallEventHandler(
            GetEventDispatcherTarget(),
            { _, event, userData in
                guard let event, let userData else { return OSStatus(eventNotHandledErr) }
                var id = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &id
                )
                guard status == noErr else { return status }

                let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
                guard let handler = manager.handlers[id.id] else {
                    return OSStatus(eventNotHandledErr)
                }
                DispatchQueue.main.async(execute: handler)
                return noErr
            },
            1,
            &spec,
            context,
            &eventHandler
        )
    }

    deinit {
        unregisterAll()
        if let eventHandler { RemoveEventHandler(eventHandler) }
    }
}
