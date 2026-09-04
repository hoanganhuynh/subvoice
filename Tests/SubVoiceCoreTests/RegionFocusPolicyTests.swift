import CoreGraphics
import Testing
@testable import SubVoiceCore

@Suite("Region focus policy")
struct RegionFocusPolicyTests {

    // Vùng phụ đề nằm ở đáy cửa sổ Chrome toàn màn hình 1920x1080.
    static let region = CGRect(x: 400, y: 900, width: 1120, height: 120)
    static let chromeFrame = CGRect(x: 0, y: 0, width: 1920, height: 1080)
    static let ownBundle = "com.williens.subvoice"

    // Giá trị mặc định của tham số KHÔNG tra được thành viên tĩnh không đủ tên,
    // nên phải viết đủ `RegionFocusPolicyTests.chromeFrame`.
    static func chrome(
        number: UInt32 = 7788,
        title: String? = "Phim hay",
        frame: CGRect = RegionFocusPolicyTests.chromeFrame
    ) -> WindowSnapshot {
        WindowSnapshot(
            windowNumber: number,
            bundleIdentifier: "com.google.Chrome",
            applicationName: "Google Chrome",
            title: title,
            frame: frame,
            layer: 0,
            alpha: 1
        )
    }

    static func owner(
        number: UInt32? = 7788,
        title: String? = "Phim hay"
    ) -> RegionOwner {
        RegionOwner(
            bundleIdentifier: "com.google.Chrome",
            applicationName: "Google Chrome",
            windowNumber: number,
            windowTitle: title
        )
    }

    static func verdict(
        owner: RegionOwner?,
        windows: [WindowSnapshot],
        pauseWhenWindowInactive: Bool = true,
        pauseOnTitleChange: Bool = true
    ) -> RegionFocusVerdict {
        RegionFocusPolicy.evaluate(
            owner: owner,
            regionGlobalRect: region,
            windows: windows,
            ownBundleIdentifier: ownBundle,
            pauseWhenWindowInactive: pauseWhenWindowInactive,
            pauseOnTitleChange: pauseOnTitleChange
        )
    }

    @Test func regionWithoutAnOwnerAlwaysReads() {
        #expect(Self.verdict(owner: nil, windows: []) == .active)
    }

    @Test func masterToggleOffAlwaysReads() {
        #expect(
            Self.verdict(
                owner: Self.owner(),
                windows: [],
                pauseWhenWindowInactive: false
            ) == .active
        )
    }

    @Test func ownerThatFailedToReanchorAlwaysReads() {
        #expect(Self.verdict(owner: Self.owner(number: nil), windows: []) == .active)
    }

    @Test func missingWindowPauses() {
        #expect(
            Self.verdict(owner: Self.owner(), windows: [Self.chrome(number: 9999)])
                == .paused(.windowGone("Google Chrome"))
        )
    }

    @Test func recycledWindowNumberOnAnotherAppPauses() {
        let slack = WindowSnapshot(
            windowNumber: 7788,
            bundleIdentifier: "com.tinyspeck.slackmacgap",
            applicationName: "Slack",
            title: "Slack",
            frame: Self.chromeFrame,
            layer: 0,
            alpha: 1
        )
        #expect(
            Self.verdict(owner: Self.owner(), windows: [slack])
                == .paused(.windowGone("Google Chrome"))
        )
    }

    @Test func windowMovedAwayFromTheRegionPauses() {
        let moved = Self.chrome(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        #expect(
            Self.verdict(owner: Self.owner(), windows: [moved])
                == .paused(.regionOutsideWindow("Google Chrome"))
        )
    }

    @Test func frontmostOwnerWindowReads() {
        #expect(Self.verdict(owner: Self.owner(), windows: [Self.chrome()]) == .active)
    }
}
