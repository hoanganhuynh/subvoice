// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SubVoice",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "SubVoiceCore"),
        .target(name: "SubVoiceUI", dependencies: ["SubVoiceCore"]),
        // Hai target dưới chạm trực tiếp vào API hệ thống (ScreenCaptureKit,
        // AppKit, Carbon) mà phần lớn chưa được chú thích Sendable. Ép chúng
        // sang chế độ ngôn ngữ Swift 5 để khỏi phải rải @unchecked Sendable
        // khắp nơi. SubVoiceCore — nơi chứa toàn bộ logic thật — vẫn ở Swift 6.
        .executableTarget(
            name: "SubVoiceApp",
            dependencies: ["SubVoiceCore", "SubVoiceUI"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "SubVoiceProbe",
            dependencies: ["SubVoiceCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "SubVoiceCoreTests",
            dependencies: ["SubVoiceCore"]
        ),
        .testTarget(
            name: "SubVoiceUITests",
            dependencies: ["SubVoiceUI", "SubVoiceCore"]
        ),
    ]
)
