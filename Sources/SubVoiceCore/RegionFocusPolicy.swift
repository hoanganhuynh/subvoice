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

        return .active
    }
}
