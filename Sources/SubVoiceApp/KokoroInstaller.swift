import Foundation
import SubVoiceCore
import SubVoiceUI

/// Tải gói Kokoro rồi giao cho `KokoroPackage` cài. Đây là lớp glue mỏng: mọi
/// logic đáng test đã nằm trong SubVoiceCore và chạy được không cần mạng.
@MainActor
final class KokoroInstaller: NSObject, URLSessionDownloadDelegate {

    var onStateChange: ((KokoroInstallState) -> Void)?

    private let package: KokoroPackage
    private let layout: KokoroInstallLayout
    private let resumeDataURL: URL
    private let supportDirectory: URL
    private let sessionConfiguration: URLSessionConfiguration
    private lazy var session = URLSession(
        configuration: sessionConfiguration,
        delegate: self,
        delegateQueue: nil
    )
    private var task: URLSessionDownloadTask?
    // Một hàng đợi nối tiếp: lượt vừa hủy phải dọn incoming xong trước lượt mới.
    private let installQueue = DispatchQueue(label: "SubVoice.KokoroInstall", qos: .utility)
    private var installation: KokoroInstallationJob?
    private let extract: @Sendable (URL, URL) throws -> Void

    private(set) var state: KokoroInstallState = .notInstalled {
        didSet {
            guard state != oldValue else { return }
            onStateChange?(state)
        }
    }

    init(
        package: KokoroPackage = .current,
        fileManager: FileManager = .default,
        applicationSupportDirectory: URL? = nil,
        sessionConfiguration: URLSessionConfiguration = .default,
        extract: @escaping @Sendable (URL, URL) throws -> Void = {
            try KokoroPackage.extractTar(archive: $0, destination: $1)
        }
    ) {
        self.extract = extract
        self.package = package
        self.sessionConfiguration = sessionConfiguration
        let applicationSupport = applicationSupportDirectory
            ?? fileManager.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first
            ?? fileManager.temporaryDirectory
        layout = KokoroInstallLayout(applicationSupport: applicationSupport)
        supportDirectory = applicationSupport
            .appendingPathComponent("SubVoice", isDirectory: true)
        resumeDataURL = supportDirectory.appendingPathComponent("kokoro-resume.data")
        super.init()
    }

    /// Có gói tải dở từ phiên trước không — để mời "tải tiếp" thay vì bắt tải
    /// lại từ đầu hàng trăm MB.
    var hasResumableDownload: Bool {
        FileManager.default.fileExists(atPath: resumeDataURL.path)
    }

    /// Đọc lại bản cài trên đĩa. Người dùng có thể đã xoá thư mục runtime, hoặc
    /// một phiên trước đã cài xong.
    func refreshInstalledState() {
        guard !state.isBusy else { return }
        setInstalledState()
    }

    /// Khác `refreshInstalledState()`, hàm này còn được dùng ngay sau hủy.
    /// Lúc đó state vẫn đang bận nên không được đi qua guard của hàm public.
    private func setInstalledState() {
        if let version = layout.installedVersion(), version == package.version {
            state = .installed(version: version)
        } else {
            state = .notInstalled
        }
    }

    func start() {
        guard !state.isBusy else { return }

        do {
            try FileManager.default.createDirectory(
                at: supportDirectory,
                withIntermediateDirectories: true
            )
            // Kiểm tra chỗ trống TRƯỚC khi đốt băng thông, không phải sau.
            try package.checkDiskSpace(at: supportDirectory)
        } catch {
            state = .failed(message: error.localizedDescription)
            return
        }

        if let resumeData = try? Data(contentsOf: resumeDataURL) {
            try? FileManager.default.removeItem(at: resumeDataURL)
            task = session.downloadTask(withResumeData: resumeData)
        } else {
            task = session.downloadTask(with: package.downloadURL)
        }
        state = .downloading(received: 0, total: package.downloadBytes)
        task?.resume()
    }

    func cancel() {
        guard state.isBusy else { return }
        installation?.cancel()
        installation = nil
        let task = task
        self.task = nil
        // Chuyển về terminal TRƯỚC callback bất đồng bộ của URLSession. Nếu
        // callback download cũ đến trễ, `isCurrentTask` sẽ bỏ qua nó thay vì
        // đưa UI quay lại trạng thái busy.
        setInstalledState()
        task?.cancel { [weak self] resumeData in
            guard let self, let resumeData else { return }
            Task { @MainActor in
                // Người dùng có thể đã bấm tải lại trước khi URLSession kịp
                // trả resume data. Không để lượt hủy cũ ghi đè lượt mới.
                guard self.task == nil, !self.state.isBusy else { return }
                try? resumeData.write(to: self.resumeDataURL)
            }
        }
    }

    // MARK: - URLSessionDownloadDelegate

    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        Task { @MainActor [weak self] in
            guard let self, self.isCurrentTask(downloadTask) else { return }
            self.state = .downloading(
                received: totalBytesWritten,
                total: totalBytesExpectedToWrite
            )
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        // `location` bị xoá ngay khi callback trả về, nên phải chuyển đi trước
        // khi nhảy sang main actor.
        let staged = FileManager.default.temporaryDirectory
            .appendingPathComponent("kokoro-download-\(UUID().uuidString).tar.gz")
        do {
            try FileManager.default.moveItem(at: location, to: staged)
        } catch {
            Task { @MainActor [weak self] in
                guard let self, self.isCurrentTask(downloadTask) else { return }
                self.task = nil
                self.state = .failed(message: error.localizedDescription)
            }
            return
        }
        Task { @MainActor [weak self] in
            guard let self, self.isCurrentTask(downloadTask) else {
                try? FileManager.default.removeItem(at: staged)
                return
            }
            self.task = nil
            self.install(archive: staged)
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        guard let error, (error as NSError).code != NSURLErrorCancelled else { return }
        Task { @MainActor [weak self] in
            guard let self, self.isCurrentTask(task) else { return }
            self.task = nil
            self.state = .failed(message: error.localizedDescription)
        }
    }

    /// URLSession có thể gửi progress/complete của lượt cũ sau `cancel()` hoặc
    /// sau khi người dùng đã bấm tải lại. Chỉ lượt task đang sở hữu state mới
    /// có quyền đổi giao diện.
    private func isCurrentTask(_ candidate: URLSessionTask) -> Bool {
        task === candidate && state.isBusy
    }

    private func install(archive: URL) {
        let job = KokoroInstallationJob()
        installation = job
        state = .verifying
        let package = package, layout = layout, extract = extract
        installQueue.async { [weak self] in
            defer { try? FileManager.default.removeItem(at: archive) }
            let result = Result {
                try package.install(
                    downloadedArchive: archive,
                    into: layout,
                    extract: extract,
                    onPhase: { phase in
                        DispatchQueue.main.async { [weak self] in
                            guard let self, self.installation === job else { return }
                            switch phase {
                            case .verifying: self.state = .verifying
                            case .extracting: self.state = .extracting
                            case .finishing: self.state = .finishing
                            }
                        }
                    },
                    checkCancellation: { try job.checkCancellation() }
                )
            }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                guard self.installation === job else {
                    // Hủy có thể trùng lúc swap đã bắt đầu. Nếu swap hoàn tất,
                    // đọc lại trạng thái trên đĩa khi chưa có lượt mới sở hữu UI.
                    if self.installation == nil, self.task == nil, !self.state.isBusy {
                        self.setInstalledState()
                    }
                    return
                }
                self.installation = nil
                switch result {
                case .success:
                    try? FileManager.default.removeItem(at: self.resumeDataURL)
                    self.state = .installed(version: package.version)
                case .failure(let error):
                    self.state = .failed(message: error.localizedDescription)
                }
            }
        }
    }
}

/// Cờ hủy được ghi từ MainActor và đọc từ hàng đợi cài đặt.
private final class KokoroInstallationJob: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }

    func checkCancellation() throws {
        lock.lock()
        let cancelled = cancelled
        lock.unlock()
        if cancelled { throw CancellationError() }
    }
}
