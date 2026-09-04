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

    static func overlay(
        bundleIdentifier: String? = "com.tinyspeck.slackmacgap",
        applicationName: String? = "Slack",
        frame: CGRect,
        layer: Int = 0,
        alpha: CGFloat = 1
    ) -> WindowSnapshot {
        WindowSnapshot(
            windowNumber: 4242,
            bundleIdentifier: bundleIdentifier,
            applicationName: applicationName,
            title: "Slack",
            frame: frame,
            layer: layer,
            alpha: alpha
        )
    }

    @Test func windowInFrontCoveringTheRegionPauses() {
        let slack = Self.overlay(frame: CGRect(x: 300, y: 850, width: 900, height: 400))
        #expect(
            Self.verdict(owner: Self.owner(), windows: [slack, Self.chrome()])
                == .paused(.windowCovered("Google Chrome"))
        )
    }

    @Test func windowInFrontThatMissesTheRegionReads() {
        // Slack nằm góc trên bên trái, không chạm dải phụ đề ở đáy.
        let slack = Self.overlay(frame: CGRect(x: 0, y: 0, width: 400, height: 300))
        #expect(Self.verdict(owner: Self.owner(), windows: [slack, Self.chrome()]) == .active)
    }

    @Test func windowBehindTheOwnerNeverCovers() {
        let slack = Self.overlay(frame: Self.chromeFrame)
        #expect(Self.verdict(owner: Self.owner(), windows: [Self.chrome(), slack]) == .active)
    }

    @Test func invisibleWindowInFrontDoesNotCover() {
        let ghost = Self.overlay(frame: Self.chromeFrame, alpha: 0)
        #expect(Self.verdict(owner: Self.owner(), windows: [ghost, Self.chrome()]) == .active)
    }

    @Test func systemLayersInFrontDoNotCover() {
        // Thanh menu và Dock luôn nằm trước mọi cửa sổ thường.
        let menuBar = Self.overlay(
            bundleIdentifier: "com.apple.controlcenter",
            applicationName: "Control Center",
            frame: Self.chromeFrame,
            layer: 24
        )
        #expect(Self.verdict(owner: Self.owner(), windows: [menuBar, Self.chrome()]) == .active)
    }

    @Test func subVoiceOwnWindowInFrontDoesNotCover() {
        let ourWindow = Self.overlay(
            bundleIdentifier: Self.ownBundle,
            applicationName: "SubVoice",
            frame: Self.chromeFrame
        )
        #expect(Self.verdict(owner: Self.owner(), windows: [ourWindow, Self.chrome()]) == .active)
    }
}
