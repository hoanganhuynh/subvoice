import Testing
@testable import SubVoiceApp
import SubVoiceCore
import SubVoiceUI

struct KokoroPlatformTests {
    @Test func supportMatchesTheArchitectureAndIsPublishedToUI() {
        #if arch(arm64)
        #expect(KokoroPlatform.isSupported)
        #else
        #expect(!KokoroPlatform.isSupported)
        #endif
        #expect(AppViewState().kokoroSupported == KokoroPlatform.isSupported)
    }

    @Test func intelCannotDiscoverAnArmRuntime() throws {
        #if arch(x86_64)
        #expect(throws: KokoroRuntimeError.self) {
            _ = try KokoroRuntime.discover(environment: [:])
        }
        #endif
    }
}
