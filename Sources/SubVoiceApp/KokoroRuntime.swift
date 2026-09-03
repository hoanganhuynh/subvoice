import Foundation
import SubVoiceCore

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
        var roots: [URL] = []
        if let configured = environment["KOKORO_ROOT"], !configured.isEmpty {
            roots.append(URL(fileURLWithPath: configured, isDirectory: true))
        }
        if let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first {
            roots.append(KokoroInstallLayout(applicationSupport: applicationSupport).root)
        }

        for root in roots {
            let required = KokoroInstallLayout.requiredFiles(in: root)
            guard required.allSatisfy({ fileManager.fileExists(atPath: $0.path) }) else {
                continue
            }

            // Phiên bản lệch được coi như chưa cài, để bản cài kiểu cũ (thư mục
            // .venv) và bản dở dang đều đi qua đúng một đường: mời tải lại.
            let manifest = root.appendingPathComponent("manifest.json")
            guard let data = fileManager.contents(atPath: manifest.path),
                  let decoded = try? JSONDecoder().decode(KokoroManifest.self, from: data),
                  decoded.version == KokoroPackage.current.version
            else { continue }

            let output = fileManager.temporaryDirectory
                .appendingPathComponent("SubVoice-Kokoro", isDirectory: true)
            try fileManager.createDirectory(at: output, withIntermediateDirectories: true)
            return KokoroRuntime(
                root: root,
                python: root.appendingPathComponent("python/bin/python3"),
                service: root.appendingPathComponent("kokoro_service.py"),
                models: root.appendingPathComponent("models", isDirectory: true),
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
