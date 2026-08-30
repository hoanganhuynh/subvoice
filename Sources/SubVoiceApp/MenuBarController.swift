import AppKit
import ServiceManagement
import SubVoiceCore

@MainActor
final class MenuBarController {

    enum State {
        case stopped
        case listening
        case speaking
        case warning(String)
    }

    var onToggle: (() -> Void)?
    var onReselect: (() -> Void)?
    var onRateChange: ((Float) -> Void)?
    var onVolumeChange: ((Float) -> Void)?
    var onWarningClicked: (() -> Void)?
    var onQuit: (() -> Void)?

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private let toggleItem = NSMenuItem()
    private let warningItem = NSMenuItem()
    private var rateItems: [NSMenuItem] = []
    private var volumeItems: [NSMenuItem] = []
    private let launchAtLoginItem = NSMenuItem()

    private var settings: Settings

    init(settings: Settings) {
        self.settings = settings
        buildMenu()
        setState(.stopped)
    }

    // MARK: - Trạng thái

    func setState(_ state: State) {
        switch state {
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
        case .warning(let message):
            setSymbol("exclamationmark.triangle.fill", description: message)
            toggleItem.title = "Bật đọc"
            warningItem.title = message
            warningItem.isHidden = false
        }
    }

    private func setSymbol(_ name: String, description: String) {
        statusItem.button?.image = NSImage(
            systemSymbolName: name,
            accessibilityDescription: description
        )
        statusItem.button?.toolTip = description
    }

    // MARK: - Dựng menu

    private func buildMenu() {
        warningItem.action = #selector(warningClicked)
        warningItem.target = self
        warningItem.isHidden = true
        menu.addItem(warningItem)

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

        let rateMenu = NSMenu()
        let rateLabels = ["Rất chậm", "Chậm", "Vừa", "Nhanh", "Rất nhanh"]
        for (index, rate) in Settings.ratePresets.enumerated() {
            let item = NSMenuItem(
                title: rateLabels[index],
                action: #selector(rateClicked(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.tag = index
            item.state = abs(rate - settings.speechRate) < 0.001 ? .on : .off
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
            item.state = abs(volume - settings.volume) < 0.001 ? .on : .off
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
        launchAtLoginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(launchAtLoginItem)

        let quit = NSMenuItem(title: "Thoát SubVoice", action: #selector(quitClicked), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu
    }

    // MARK: - Hành động

    @objc private func toggleClicked() { onToggle?() }
    @objc private func reselectClicked() { onReselect?() }
    @objc private func warningClicked() { onWarningClicked?() }
    @objc private func quitClicked() { onQuit?() }

    @objc private func rateClicked(_ sender: NSMenuItem) {
        let rate = Settings.ratePresets[sender.tag]
        settings.speechRate = rate
        rateItems.enumerated().forEach { $0.element.state = $0.offset == sender.tag ? .on : .off }
        onRateChange?(rate)
    }

    @objc private func volumeClicked(_ sender: NSMenuItem) {
        let volume = Settings.volumePresets[sender.tag]
        settings.volume = volume
        volumeItems.enumerated().forEach { $0.element.state = $0.offset == sender.tag ? .on : .off }
        onVolumeChange?(volume)
    }

    @objc private func launchAtLoginClicked() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
                launchAtLoginItem.state = .off
            } else {
                try SMAppService.mainApp.register()
                launchAtLoginItem.state = .on
            }
        } catch {
            NSLog("Không đổi được cài đặt khởi động cùng máy: \(error.localizedDescription)")
        }
    }
}
