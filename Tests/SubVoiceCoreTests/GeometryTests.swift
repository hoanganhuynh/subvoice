import Testing
import CoreGraphics
@testable import SubVoiceCore

@Test func convertsRectOnPrimaryDisplay() {
    // Màn hình chính 1920x1080 tại gốc toạ độ.
    let display = CGRect(x: 0, y: 0, width: 1920, height: 1080)
    // Dải phụ đề: cách đáy màn hình 900pt (hệ AppKit), cao 60pt.
    let global = CGRect(x: 100, y: 900, width: 400, height: 60)

    let local = Geometry.toDisplayLocalTopLeft(globalRect: global, displayFrame: display)

    #expect(local == CGRect(x: 100, y: 120, width: 400, height: 60))
}

@Test func convertsRectOnDisplayLeftOfPrimary() {
    // Màn hình phụ đặt bên TRÁI màn hình chính -> toạ độ x âm.
    let display = CGRect(x: -1920, y: 0, width: 1920, height: 1080)
    let global = CGRect(x: -1820, y: 900, width: 400, height: 60)

    let local = Geometry.toDisplayLocalTopLeft(globalRect: global, displayFrame: display)

    #expect(local == CGRect(x: 100, y: 120, width: 400, height: 60))
}

@Test func convertsRectOnDisplayAbovePrimary() {
    // Màn hình phụ 2560x1440 đặt PHÍA TRÊN màn hình chính.
    let display = CGRect(x: 0, y: 1080, width: 2560, height: 1440)
    let global = CGRect(x: 100, y: 2400, width: 400, height: 60)

    let local = Geometry.toDisplayLocalTopLeft(globalRect: global, displayFrame: display)

    #expect(local == CGRect(x: 100, y: 60, width: 400, height: 60))
}

@Test func clampsRectToDisplayBounds() {
    let size = CGSize(width: 1920, height: 1080)
    let overflowing = CGRect(x: 1800, y: 1000, width: 400, height: 200)

    let clamped = Geometry.clamped(overflowing, toDisplaySize: size)

    #expect(clamped == CGRect(x: 1800, y: 1000, width: 120, height: 80))
}

@Test func rejectsRectTooSmallAfterClamping() {
    let size = CGSize(width: 1920, height: 1080)
    let sliver = CGRect(x: 1918, y: 100, width: 400, height: 200)

    #expect(Geometry.clamped(sliver, toDisplaySize: size) == nil)
}

@Test func rejectsRectFullyOutsideDisplay() {
    let size = CGSize(width: 1920, height: 1080)
    let outside = CGRect(x: 5000, y: 5000, width: 100, height: 100)

    #expect(Geometry.clamped(outside, toDisplaySize: size) == nil)
}

@Test func convertsDisplayLocalRectToGlobalTopLeftOnPrimaryDisplay() {
    // CGDisplayBounds của màn hình chính luôn có gốc (0, 0).
    let bounds = CGRect(x: 0, y: 0, width: 1920, height: 1080)
    let local = CGRect(x: 100, y: 120, width: 400, height: 60)

    let global = Geometry.toGlobalTopLeft(displayLocalRect: local, displayBounds: bounds)

    #expect(global == CGRect(x: 100, y: 120, width: 400, height: 60))
}

@Test func convertsDisplayLocalRectToGlobalTopLeftOnSecondaryDisplay() {
    // Màn hình phụ đặt bên PHẢI màn hình chính, trong hệ CGDisplayBounds.
    let bounds = CGRect(x: 1920, y: 0, width: 2560, height: 1440)
    let local = CGRect(x: 100, y: 1300, width: 400, height: 60)

    let global = Geometry.toGlobalTopLeft(displayLocalRect: local, displayBounds: bounds)

    #expect(global == CGRect(x: 2020, y: 1300, width: 400, height: 60))
}

@Test func convertsDisplayLocalRectOnDisplayAbovePrimary() {
    // Phía TRÊN màn hình chính -> y âm trong hệ CGDisplayBounds.
    let bounds = CGRect(x: 0, y: -1440, width: 2560, height: 1440)
    let local = CGRect(x: 50, y: 1380, width: 400, height: 60)

    let global = Geometry.toGlobalTopLeft(displayLocalRect: local, displayBounds: bounds)

    #expect(global == CGRect(x: 50, y: -60, width: 400, height: 60))
}
