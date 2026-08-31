import Foundation

struct KokoroRuntime {
    let root: URL
    let python: URL
    let service: URL
    let models: URL
    let outputDirectory: URL

    static func discover(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) throws -> KokoroRuntime {
        var candidates: [URL] = []
        if let configured = environment["KOKORO_ROOT"], !configured.isEmpty {
            candidates.append(URL(fileURLWithPath: configured, isDirectory: true))
        }

        if let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first {
            candidates.append(
                applicationSupport
                    .appendingPathComponent("SubVoice", isDirectory: true)
                    .appendingPathComponent("Kokoro", isDirectory: true)
            )
        }

        // Cho phép chạy trực tiếp từ source tree khi phát triển. Bản .app đã
        // đóng gói sẽ dùng thư mục Application Support ở trên.
        candidates.append(
            URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true)
                .appendingPathComponent("ThirdParty", isDirectory: true)
                .appendingPathComponent("Kokoro-Vietnamese", isDirectory: true)
        )

        for root in candidates {
            let python = root.appendingPathComponent(".venv/bin/python")
            let bundledService = root.appendingPathComponent("kokoro_service.py")
            let sourceService = URL(
                fileURLWithPath: fileManager.currentDirectoryPath,
                isDirectory: true
            ).appendingPathComponent("Resources/kokoro_service.py")
            let service = fileManager.fileExists(atPath: bundledService.path)
                ? bundledService : sourceService
            let models = root.appendingPathComponent("models", isDirectory: true)

            let required = [
                python.path,
                service.path,
                models.appendingPathComponent("kokoro_vi.onnx").path,
                models.appendingPathComponent("config.json").path,
                models.appendingPathComponent("voicepacks/diem_trinh.pt").path,
            ]
            guard required.allSatisfy(fileManager.fileExists(atPath:)) else { continue }

            let output = fileManager.temporaryDirectory
                .appendingPathComponent("SubVoice-Kokoro", isDirectory: true)
            try fileManager.createDirectory(
                at: output,
                withIntermediateDirectories: true
            )
            return KokoroRuntime(
                root: root,
                python: python,
                service: service,
                models: models,
                outputDirectory: output
            )
        }

        throw KokoroRuntimeError.notInstalled
    }
}

enum KokoroRuntimeError: LocalizedError {
    case notInstalled

    var errorDescription: String? {
        switch self {
        case .notInstalled:
            return "Chưa cài bộ giọng Kokoro"
        }
    }
}
