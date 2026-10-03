/// Gói Kokoro hiện phát hành chỉ có Python và thư viện native cho Apple Silicon.
public enum KokoroPlatform {
    public static var isSupported: Bool {
        #if arch(arm64)
        true
        #else
        false
        #endif
    }

    public static let unsupportedMessage = "Kokoro hiện chỉ hỗ trợ Apple Silicon. Máy Intel dùng giọng tiếng Việt của macOS."
}
