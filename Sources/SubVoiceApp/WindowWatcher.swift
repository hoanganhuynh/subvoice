import AppKit
import CoreGraphics
import SubVoiceCore

/// Theo dõi cửa sổ chủ của vùng đọc và báo khi nào được đọc, khi nào phải chờ.
///
/// Poll là bắt buộc: đổi tab và bị cửa sổ khác che đều không bắn ra thông báo
/// hệ thống nào. Hai quan sát viên `NSWorkspace` chỉ để phản ứng tức thì lúc
/// đổi app hoặc đổi Space, không thay được poll.
@MainActor
final class WindowWatcher {

    /// Chỉ bắn khi kết luận đổi so với lần xét trước.
    var onVerdictChange: ((RegionFocusVerdict) -> Void)?

    private static let interval: TimeInterval = 0.4

    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var owner: RegionOwner?
    private var regionGlobalRect: CGRect = .zero
    private var settings = Settings()
    private var lastVerdict: RegionFocusVerdict = .active

    func start(owner: RegionOwner, regionGlobalRect: CGRect, settings: Settings) {
        stop()
        self.owner = owner
        self.regionGlobalRect = regionGlobalRect
        self.settings = settings

        let timer = Timer.scheduledTimer(withTimeInterval: Self.interval, repeats: true) { _ in
            MainActor.assumeIsolated { [weak self] in self?.evaluate() }
        }
        // .common để vòng poll không chết trong lúc người dùng đang kéo cửa sổ
        // hay cuộn menu.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer

        let center = NSWorkspace.shared.notificationCenter
        for name in [
            NSWorkspace.didActivateApplicationNotification,
            NSWorkspace.activeSpaceDidChangeNotification,
        ] {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { [weak self] in self?.evaluate() }
            }
            observers.append(token)
        }

        evaluate()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        let center = NSWorkspace.shared.notificationCenter
        observers.forEach { center.removeObserver($0) }
        observers.removeAll()
        owner = nil
        lastVerdict = .active
    }

    private func evaluate() {
        guard let owner else { return }

        let ownBundleIdentifier = Bundle.main.bundleIdentifier

        // Người dùng mở cửa sổ SubVoice để chỉnh giọng giữa chừng không phải là
        // chuyển app: bỏ qua vòng này và giữ nguyên kết luận cũ.
        if let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
           front == ownBundleIdentifier {
            return
        }

        // Danh sách rỗng là lỗi đọc, không phải bằng chứng vùng đọc bị che.
        let windows = Self.snapshot()
        guard !windows.isEmpty else { return }

        let verdict = RegionFocusPolicy.evaluate(
            owner: owner,
            regionGlobalRect: regionGlobalRect,
            windows: windows,
            ownBundleIdentifier: ownBundleIdentifier,
            pauseWhenWindowInactive: settings.pauseWhenWindowInactive,
            pauseOnTitleChange: settings.pauseOnWindowTitleChange
        )

        guard verdict != lastVerdict else { return }
        lastVerdict = verdict
        onVerdictChange?(verdict)
    }

    /// Danh sách cửa sổ đang hiện, xếp TỪ TRƯỚC RA SAU — đúng thứ tự mà
    /// `CGWindowListCopyWindowInfo` trả về.
    ///
    /// `kCGWindowName` chỉ có giá trị khi app đã được cấp quyền Screen
    /// Recording. App này luôn có quyền đó trước khi bắt đầu đọc.
    static func snapshot() -> [WindowSnapshot] {
        guard let raw = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else { return [] }

        // Một app hay có hàng chục cửa sổ; tra bundle ID theo PID đúng một lần.
        var bundleByPID: [pid_t: String?] = [:]

        return raw.compactMap { entry -> WindowSnapshot? in
            guard let number = entry[kCGWindowNumber as String] as? NSNumber,
                  let boundsDict = entry[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: boundsDict)
            else { return nil }

            let pid = (entry[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value ?? 0
            let bundleIdentifier: String?
            if let cached = bundleByPID[pid] {
                bundleIdentifier = cached
            } else {
                let resolved = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
                bundleByPID[pid] = resolved
                bundleIdentifier = resolved
            }

            return WindowSnapshot(
                windowNumber: number.uint32Value,
                bundleIdentifier: bundleIdentifier,
                applicationName: entry[kCGWindowOwnerName as String] as? String,
                title: entry[kCGWindowName as String] as? String,
                frame: frame,
                layer: (entry[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0,
                alpha: CGFloat((entry[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1)
            )
        }
    }
}
