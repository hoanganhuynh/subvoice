import AppKit
import SubVoiceCore
import SubVoiceUI

/// Menu bar chỉ VẼ lại `AppViewState` và phát intent. Nó không giữ bản sao
/// `Settings` riêng nữa — trước đây menu và cửa sổ dễ lệch nhau vì mỗi bên tự
/// nhớ một phần trạng thái.
@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {

    var onIntent: ((AppIntent) -> Void)?
    var onOpenWindow: (() -> Void)?
    /// Quyền hệ thống có thể đổi lúc app đang chạy, nên trạng thái phải được
    /// tính lại mỗi lần mở menu thay vì chỉ tính một lần lúc khởi động.
    var onMenuWillOpen: (() -> Void)?

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private let toggleItem = NSMenuItem()
    private let warningItem = NSMenuItem()
    private let voiceMenu = NSMenu()
    private var engineItems: [NSMenuItem] = []
    private var voiceItems: [NSMenuItem] = []
    private var rateItems: [NSMenuItem] = []
    private var volumeItems: [NSMenuItem] = []
    private let launchAtLoginItem = NSMenuItem()

    /// Danh sách giọng đang hiện, để chỉ dựng lại submenu khi nó thực sự đổi.
    private var renderedVoices: [SpeechVoiceOption] = []

    override init() {
        super.init()
        buildMenu()
    }

    // MARK: - Vẽ lại theo state

    func render(_ state: AppViewState) {
        renderRunState(state.runState)
        renderNotice(state.notice, runState: state.runState)
        renderVoices(state.voices, selectedIdentifier: state.selectedVoiceIdentifier)

        for item in engineItems {
            guard let raw = item.representedObject as? String,
                  let engine = SpeechEngine(rawValue: raw)
            else { continue }
            item.state = engine == state.settings.speechEngine ? .on : .off
            item.isEnabled = engine != .kokoro || state.kokoroAvailable
        }
        for (index, rate) in Settings.ratePresets.enumerated() {
            rateItems[index].state = abs(rate - state.settings.speechRate) < 0.001 ? .on : .off
        }
        for (index, volume) in Settings.volumePresets.enumerated() {
            volumeItems[index].state = abs(volume - state.settings.volume) < 0.001 ? .on : .off
        }
        launchAtLoginItem.state = state.launchAtLoginEnabled ? .on : .off
    }

    private func renderRunState(_ runState: AppRunState) {
        switch runState {
        case .stopped:
            setSymbol("speaker.slash", description: "SubVoice đang tắt")
            toggleItem.title = "Bật đọc"
            warningItem.isHidden = true
        case .listening:
            setSymbol("waveform", description: "SubVoice đang nghe")
            toggleItem.title = "Tắt đọc"
            warningItem.isHidden = true
        case .speaking:
            setSymbol("waveform.circle.fill", description: "SubVoice đang đọc")
            toggleItem.title = "Tắt đọc"
            warningItem.isHidden = true
        case .paused:
            // Lấy đúng câu chữ mà cửa sổ chính đang hiện, để hai nơi không nói
            // lệch nhau về cùng một trạng thái.
            let detail = DashboardContent(runState: runState).detail
            setSymbol("pause.circle", description: detail)
            toggleItem.title = "Tắt đọc"
            warningItem.isHidden = true
        case .warning(let warning):
            setSymbol("exclamationmark.triangle.fill", description: warning.message)
            toggleItem.title = "Bật đọc"
            warningItem.title = warning.message
            warningItem.representedObject = warning.recovery.map(RecoveryBox.init)
            warningItem.isHidden = false
        }
    }

    /// Cảnh báo fallback không thay thế trạng thái nghe/đọc. Nhờ vậy menu vẫn
    /// phản ánh hoạt động thật, đồng thời người dùng không bỏ lỡ lý do đổi
    /// engine.
    private func renderNotice(_ notice: AppWarning?, runState: AppRunState) {
        let warning: AppWarning?
        if case .warning(let stateWarning) = runState {
            warning = stateWarning
        } else {
            warning = notice
        }
        guard let warning else {
            warningItem.isHidden = true
            warningItem.representedObject = nil
            return
        }
        warningItem.title = warning.message
        warningItem.representedObject = RecoveryBox(warning.recovery ?? .retry)
        warningItem.isHidden = false
    }

    /// `RecoveryAction` là enum Swift thuần nên không đặt thẳng vào
    /// `representedObject` (vốn cần AnyObject) được.
    private final class RecoveryBox: NSObject {
        let action: RecoveryAction
        init(_ action: RecoveryAction) { self.action = action }
    }

    private func renderVoices(_ voices: [SpeechVoiceOption], selectedIdentifier: String?) {
        if voices != renderedVoices {
            renderedVoices = voices
            voiceItems.removeAll()
            voiceMenu.removeAllItems()

            guard !voices.isEmpty else {
                let unavailable = NSMenuItem(
                    title: "Không có giọng khả dụng",
                    action: nil,
                    keyEquivalent: ""
                )
                unavailable.isEnabled = false
                voiceMenu.addItem(unavailable)
                return
            }

            for voice in voices {
                let item = NSMenuItem(
                    title: voice.name,
                    action: #selector(voiceClicked(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = voice.identifier
                voiceMenu.addItem(item)
                voiceItems.append(item)
            }
        }
        for item in voiceItems {
            item.state = item.representedObject as? String == selectedIdentifier ? .on : .off
        }
    }

    private func setSymbol(_ name: String, description: String) {
        statusItem.button?.image = NSImage(
            systemSymbolName: name,
            accessibilityDescription: description
        )
        statusItem.button?.toolTip = description
    }

    nonisolated func menuWillOpen(_ menu: NSMenu) {
        MainActor.assumeIsolated { onMenuWillOpen?() }
    }

    // MARK: - Dựng menu

    private func buildMenu() {
        warningItem.action = #selector(warningClicked(_:))
        warningItem.target = self
        warningItem.isHidden = true
        menu.addItem(warningItem)

        let openWindow = NSMenuItem(
            title: "Mở SubVoice",
            action: #selector(openWindowClicked),
            keyEquivalent: ""
        )
        openWindow.target = self
        menu.addItem(openWindow)

        toggleItem.title = "Bật đọc"
        toggleItem.action = #selector(toggleClicked)
        toggleItem.target = self
        toggleItem.keyEquivalent = "v"
        toggleItem.keyEquivalentModifierMask = [.command, .option]
        menu.addItem(toggleItem)

        let reselect = NSMenuItem(
            title: "Chọn lại vùng…",
            action: #selector(reselectClicked),
            keyEquivalent: "r"
        )
        reselect.keyEquivalentModifierMask = [.command, .option]
        reselect.target = self
        menu.addItem(reselect)

        menu.addItem(.separator())

        let engineMenu = NSMenu()
        let engines: [(SpeechEngine, String)] = [
            (.system, "Hệ thống — nhanh"),
            (.kokoro, "Kokoro — tự nhiên, offline"),
        ]
        for (engine, title) in engines {
            let item = NSMenuItem(
                title: title,
                action: #selector(engineClicked(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = engine.rawValue
            engineMenu.addItem(item)
            engineItems.append(item)
        }
        let engineRoot = NSMenuItem(title: "Bộ đọc", action: nil, keyEquivalent: "")
        engineRoot.submenu = engineMenu
        menu.addItem(engineRoot)

        let voiceRoot = NSMenuItem(title: "Giọng đọc", action: nil, keyEquivalent: "")
        voiceRoot.submenu = voiceMenu
        menu.addItem(voiceRoot)

        let rateMenu = NSMenu()
        let rateLabels = ["Rất chậm", "Chậm", "Vừa", "Nhanh", "Rất nhanh"]
        for (index, _) in Settings.ratePresets.enumerated() {
            let item = NSMenuItem(
                title: rateLabels[index],
                action: #selector(rateClicked(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.tag = index
            rateMenu.addItem(item)
            rateItems.append(item)
        }
        let rateRoot = NSMenuItem(title: "Tốc độ đọc", action: nil, keyEquivalent: "")
        rateRoot.submenu = rateMenu
        menu.addItem(rateRoot)

        let volumeMenu = NSMenu()
        for (index, volume) in Settings.volumePresets.enumerated() {
            let item = NSMenuItem(
                title: "\(Int(volume * 100))%",
                action: #selector(volumeClicked(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.tag = index
            volumeMenu.addItem(item)
            volumeItems.append(item)
        }
        let volumeRoot = NSMenuItem(title: "Âm lượng", action: nil, keyEquivalent: "")
        volumeRoot.submenu = volumeMenu
        menu.addItem(volumeRoot)

        menu.addItem(.separator())

        launchAtLoginItem.title = "Khởi động cùng máy"
        launchAtLoginItem.action = #selector(launchAtLoginClicked)
        launchAtLoginItem.target = self
        menu.addItem(launchAtLoginItem)

        let quit = NSMenuItem(
            title: "Thoát SubVoice",
            action: #selector(quitClicked),
            keyEquivalent: "q"
        )
        quit.target = self
        menu.addItem(quit)

        menu.delegate = self
        statusItem.menu = menu
    }

    // MARK: - Hành động

    @objc private func toggleClicked() { onIntent?(.toggleCapture) }
    @objc private func reselectClicked() { onIntent?(.selectRegion) }
    @objc private func quitClicked() { onIntent?(.quit) }
    @objc private func openWindowClicked() { onOpenWindow?() }

    @objc private func warningClicked(_ sender: NSMenuItem) {
        let recovery = (sender.representedObject as? RecoveryBox)?.action ?? .retry
        onIntent?(.recover(recovery))
    }

    @objc private func engineClicked(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let engine = SpeechEngine(rawValue: raw)
        else { return }
        onIntent?(.changeEngine(engine))
    }

    @objc private func voiceClicked(_ sender: NSMenuItem) {
        guard let identifier = sender.representedObject as? String else { return }
        onIntent?(.changeVoice(identifier))
    }

    @objc private func rateClicked(_ sender: NSMenuItem) {
        onIntent?(.changeRate(Settings.ratePresets[sender.tag]))
    }

    @objc private func volumeClicked(_ sender: NSMenuItem) {
        onIntent?(.changeVolume(Settings.volumePresets[sender.tag]))
    }

    @objc private func launchAtLoginClicked() {
        onIntent?(.setLaunchAtLogin(launchAtLoginItem.state != .on))
    }
}
