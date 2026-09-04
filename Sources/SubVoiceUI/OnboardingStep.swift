import Foundation

/// Thứ tự các bước của wizard lần đầu chạy.
///
/// Tách khỏi view để test được: sai thứ tự ở đây là người dùng được mời chọn
/// vùng phụ đề trước khi có quyền đọc màn hình.
public enum OnboardingStep: Int, CaseIterable, Equatable, Sendable {
    case welcome
    case screenRecording
    case voice
    case region
    case done

    public var next: OnboardingStep? { OnboardingStep(rawValue: rawValue + 1) }
    public var previous: OnboardingStep? { OnboardingStep(rawValue: rawValue - 1) }

    public var indicator: String { "\(rawValue + 1)/\(OnboardingStep.allCases.count)" }

    public var title: String {
        switch self {
        case .welcome: "Chào mừng tới SubVoice"
        case .screenRecording: "Cho phép đọc màn hình"
        case .voice: "Chọn giọng đọc"
        case .region: "Chọn vùng phụ đề"
        case .done: "Xong rồi"
        }
    }
}
