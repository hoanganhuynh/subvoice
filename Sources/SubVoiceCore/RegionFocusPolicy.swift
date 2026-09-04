import CoreGraphics

/// Vì sao vùng đọc đang bị tạm dừng. Chuỗi đi kèm là tên app chủ, để giao diện
/// nói được "cửa sổ Google Chrome" thay vì một câu chung chung.
public enum RegionPauseReason: Equatable, Sendable {
    case windowGone(String)
    case windowCovered(String)
    case regionOutsideWindow(String)
    case contentChanged(String)
}

public enum RegionFocusVerdict: Equatable, Sendable {
    case active
    case paused(RegionPauseReason)
}

/// Toàn bộ luật quyết định vùng đọc còn đáng tin hay không.
///
/// Thuần hoàn toàn: nhận ảnh chụp danh sách cửa sổ, trả về kết luận. Phần đọc
/// `CGWindowListCopyWindowInfo` và chạy timer nằm ở `WindowWatcher`.
public enum RegionFocusPolicy {

    /// - Parameter windows: xếp TỪ TRƯỚC RA SAU.
    public static func evaluate(
        owner: RegionOwner?,
        regionGlobalRect: CGRect,
        windows: [WindowSnapshot],
        ownBundleIdentifier: String?,
        pauseWhenWindowInactive: Bool,
        pauseOnTitleChange: Bool
    ) -> RegionFocusVerdict {
        // Neo lại thất bại thì phiên này chạy không khoá cửa sổ, chứ không tạm
        // dừng vĩnh viễn — người dùng vẫn phải nghe được phụ đề.
        guard pauseWhenWindowInactive,
              let owner,
              let number = owner.windowNumber
        else { return .active }

        let name = owner.applicationName

        // Kiểm cả bundle: macOS có cấp lại số hiệu cửa sổ cũ cho app khác.
        guard let index = windows.firstIndex(where: {
            $0.windowNumber == number && $0.bundleIdentifier == owner.bundleIdentifier
        }) else { return .paused(.windowGone(name)) }

        let target = windows[index]

        guard target.frame.contains(regionGlobalRect) else {
            return .paused(.regionOutsideWindow(name))
        }

        // Cố ý KHÔNG hỏi app nào đang ở trước. Mở Slack ở một góc màn hình mà
        // nó không che vùng phụ đề thì phim vẫn hiện, chữ trong vùng vẫn là
        // phụ đề — không có gì để đọc nhầm. Chỉ thứ gì thực sự đè lên vùng đọc
        // mới đáng dừng.
        let isCovered = windows.prefix(index).contains { window in
            window.layer == 0
                && window.alpha > 0
                && (ownBundleIdentifier == nil || window.bundleIdentifier != ownBundleIdentifier)
                && window.frame.intersects(regionGlobalRect)
        }
        if isCovered { return .paused(.windowCovered(name)) }

        // Đọc không ra tiêu đề hiện tại thì bỏ qua bước này: thiếu thông tin
        // không phải là bằng chứng nội dung đã đổi.
        if pauseOnTitleChange,
           let expected = owner.windowTitle,
           let actual = RegionOwner.normalizedTitle(target.title),
           actual != expected {
            return .paused(.contentChanged(name))
        }

        return .active
    }

    /// Tìm lại cửa sổ chủ ở đầu mỗi phiên đọc, vì số hiệu cửa sổ đã lưu không
    /// sống qua lần khởi động lại của app đích.
    ///
    /// - Returns: `owner` với số hiệu mới, hoặc `nil` khi không tìm được — lúc
    ///   đó phiên này chạy không khoá cửa sổ.
    public static func reanchor(
        owner: RegionOwner,
        regionGlobalRect: CGRect,
        windows: [WindowSnapshot],
        ownBundleIdentifier: String?
    ) -> RegionOwner? {
        let candidates = windows.filter {
            $0.bundleIdentifier == owner.bundleIdentifier
                && $0.layer == 0
                && $0.alpha > 0
                && (ownBundleIdentifier == nil || $0.bundleIdentifier != ownBundleIdentifier)
        }

        if let title = owner.windowTitle,
           let match = candidates.first(where: {
               RegionOwner.normalizedTitle($0.title) == title
           }) {
            var anchored = owner
            anchored.windowNumber = match.windowNumber
            return anchored
        }

        guard let fallback = candidates.first(where: {
            $0.frame.contains(regionGlobalRect)
        }) else { return nil }

        // Tiêu đề cũ đã vô nghĩa ở đường này. Không lấy lại tiêu đề đang có thì
        // luật tiêu đề sẽ tạm dừng ngay từ vòng xét đầu tiên.
        var anchored = owner
        anchored.windowNumber = fallback.windowNumber
        anchored.windowTitle = RegionOwner.normalizedTitle(fallback.title)
        return anchored
    }

    /// Cửa sổ nào đã sinh ra vùng vừa khoanh.
    ///
    /// Đòi khung cửa sổ chứa TRỌN vùng, đúng bằng điều kiện mà `evaluate` dùng.
    /// Nếu ở đây chỉ đòi chứa tâm vùng thì một vùng khoanh tràn mép sẽ nhận chủ
    /// rồi bị `evaluate` cho tạm dừng ngay và không đọc được câu nào.
    public static func owner(
        forGlobalRect rect: CGRect,
        windows: [WindowSnapshot],
        ownBundleIdentifier: String?
    ) -> RegionOwner? {
        guard let window = windows.first(where: {
            $0.layer == 0
                && $0.alpha > 0
                && (ownBundleIdentifier == nil || $0.bundleIdentifier != ownBundleIdentifier)
                && $0.frame.contains(rect)
        }), let bundleIdentifier = window.bundleIdentifier else { return nil }

        return RegionOwner(
            bundleIdentifier: bundleIdentifier,
            applicationName: window.applicationName ?? bundleIdentifier,
            windowNumber: window.windowNumber,
            windowTitle: RegionOwner.normalizedTitle(window.title)
        )
    }
}
