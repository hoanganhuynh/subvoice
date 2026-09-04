# Kokoro On-Demand Install and First-Run Onboarding Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make SubVoice installable on someone else's Mac by shipping Kokoro as a self-contained archive the app downloads on demand, and by adding a first-run wizard that walks a new user through permission, voice and region.

**Architecture:** A maintainer-run script builds a relocatable CPython plus dependencies plus models into one `tar.zst` published on GitHub Releases. `SubVoiceCore` owns the pure install pipeline (checksum, extract, atomic swap) so it is testable without a network. `SubVoiceApp` owns only the `URLSession` glue and rebuilds `KokoroSpeechBackend` once the install lands, so Kokoro becomes usable without relaunching. `SubVoiceUI` gains one install-state value and an onboarding wizard, both driven by the existing single-snapshot state flow.

**Tech Stack:** Swift 6, SwiftUI, AppKit, Swift Testing, CryptoKit, URLSession, bsdtar (zstd), python-build-standalone, ONNX Runtime.

**Spec:** `docs/design/2026-09-01-kokoro-download-onboarding.md`

## Global constraints

- macOS 14.0 remains the minimum supported version. Apple Silicon only for the Kokoro runtime.
- Do not change `ChangeDetector`, `OCREngine`, `TextGate`, `SpeechQueue`, `RegionSelector` or `HotKeyManager`.
- `AppCoordinator` remains the only producer of `AppViewState`; views only read state and send intents.
- The session transcript stays memory-only. Nothing in this plan writes it anywhere.
- Never install an archive whose SHA-256 does not match the embedded constant.
- The app must remain fully usable while a download runs, and after the user skips every wizard step.
- Add no third-party Swift dependency.

## File map

### New production files

- `Scripts/package-kokoro.sh` — maintainer-run packaging script.
- `Sources/SubVoiceCore/KokoroPackage.swift` — package description, install layout, manifest and the pure install pipeline.
- `Sources/SubVoiceApp/KokoroInstaller.swift` — `URLSession` download, progress, resume data.
- `Sources/SubVoiceUI/KokoroInstallState.swift` — install state and derived display values.
- `Sources/SubVoiceUI/OnboardingStep.swift` — wizard step order.
- `Sources/SubVoiceUI/OnboardingView.swift` — the wizard.

### New test files

- `Tests/SubVoiceCoreTests/KokoroPackageTests.swift`
- `Tests/SubVoiceUITests/KokoroInstallStateTests.swift`
- `Tests/SubVoiceUITests/OnboardingStepTests.swift`

### Existing files modified

- `Resources/kokoro_service.py`
- `Sources/SubVoiceApp/KokoroRuntime.swift`
- `Sources/SubVoiceApp/AppCoordinator.swift`
- `Sources/SubVoiceUI/AppViewState.swift`
- `Sources/SubVoiceUI/SubVoiceRootView.swift`
- `Sources/SubVoiceUI/VoiceStudioView.swift`
- `Sources/SubVoiceUI/SettingsView.swift`
- `Sources/SubVoiceCore/Settings.swift`
- `Scripts/bundle.sh`
- `README.md`

---

### Task 1: Retire the two packaging risks before building anything

This task writes no product code. It answers two questions that can invalidate the
whole design. Do it first.

**Files:** none. Work in a scratch directory outside the repo.

- [ ] **Step 1: Download a relocatable CPython and confirm it runs**

```bash
cd "$(mktemp -d)"
PBS_TAG="20250818"
PBS_FILE="cpython-3.12.11+${PBS_TAG}-aarch64-apple-darwin-install_only.tar.gz"
curl -fL -o python.tar.gz \
  "https://github.com/astral-sh/python-build-standalone/releases/download/${PBS_TAG}/${PBS_FILE}"
tar -xf python.tar.gz
./python/bin/python3 -c 'import sys; print(sys.version)'
```

Expected: prints a 3.12 version string.

If the tag or filename 404s, open
<https://github.com/astral-sh/python-build-standalone/releases> and pick the newest
release that has an `aarch64-apple-darwin-install_only.tar.gz` asset. Record the tag
and filename you used — Task 2 hard-codes them.

- [ ] **Step 2: Install the runtime dependencies with no venv**

```bash
./python/bin/python3 -m pip install --upgrade pip
./python/bin/python3 -m pip install --target ./site-packages \
  onnxruntime numpy soundfile sea-g2p \
  "kokoro-vietnamese @ git+https://github.com/iamdinhthuan/Kokoro-Vietnamese.git"
```

Expected: completes without error.

- [ ] **Step 3: Answer risk 2 — does anything pull in torch?**

```bash
ls ./site-packages | grep -i '^torch' || echo "NO-TORCH"
du -sh ./site-packages
```

Expected: `NO-TORCH`, and `site-packages` well under 400 MB.

**STOP CONDITION:** if `torch` is present, do not continue this plan. Report which
package requires it. The spec's ~550 MB payload and the `.npy` conversion both
depend on this answer, and the design must be revisited.

- [ ] **Step 4: Answer risk 1 — do the downloaded binaries run unsigned?**

```bash
codesign -dv ./python/bin/python3 2>&1 | head -3
xattr -l ./python/bin/python3
# PYTHONPATH là bắt buộc: `pip install --target` đặt package ra ngoài thư mục
# mặc định của interpreter, nên thiếu nó sẽ báo ModuleNotFoundError và làm ta
# tưởng gói hỏng.
PYTHONPATH=./site-packages ./python/bin/python3 -c "import onnxruntime, numpy, soundfile; print('IMPORT-OK')"
```

Expected: `IMPORT-OK`. Record whether `codesign -dv` reports a signature.

If the imports fail with a code-signature error, Task 2 Step 5 must add a
`codesign --force --sign - --deep` pass over the staged tree. Record which it is.

- [ ] **Step 5: Confirm a voicepack loads as numpy without torch**

```bash
./python/bin/python3 - <<'PY'
import numpy as np
a = np.zeros((512, 1, 256), dtype=np.float32)
np.save('/tmp/vp.npy', a)
b = np.load('/tmp/vp.npy')
print('SHAPE-OK', b.shape, b.dtype)
PY
```

Expected: `SHAPE-OK (512, 1, 256) float32`. This is the exact shape
`select_voice_style()` in `onnx_utils.py` validates, so a `.npy` voicepack of this
shape satisfies it with no upstream change.

- [ ] **Step 6: Record the findings**

No commit. Carry three facts into Task 2: the python-build-standalone tag, the
asset filename, and whether re-signing is required.

---

### Task 2: Build the self-contained Kokoro archive

**Files:**

- Create: `Scripts/package-kokoro.sh`
- Modify: `Resources/kokoro_service.py`

**Interfaces:**

- Produces: `kokoro-runtime-<version>-arm64.tar.zst` and its SHA-256.
- The archive expands with **no wrapper directory**: `python/`, `site-packages/`, `models/`, `kokoro_service.py` sit at the root of wherever it is extracted.

- [ ] **Step 1: Drop torch from the sidecar**

Replace the two torch lines in `Resources/kokoro_service.py`. Change the imports
from:

```python
import soundfile as sf
import torch
from kokoro_vietnamese.core import SAMPLE_RATE, VOICES
```

to:

```python
import numpy as np
import soundfile as sf
from kokoro_vietnamese.core import SAMPLE_RATE, VOICES
```

and change the voicepack load from:

```python
            tts.voicepack = torch.load(models / VOICES[voice]["filename"], map_location="cpu", weights_only=True)
```

to:

```python
            # Voicepack đã được convert sang .npy lúc đóng gói. Đây là chỗ duy
            # nhất từng cần torch, và torch nặng hơn toàn bộ phần còn lại cộng
            # lại — nên nó bị loại khỏi gói runtime.
            filename = Path(VOICES[voice]["filename"]).with_suffix(".npy")
            tts.voicepack = np.load(models / filename)
```

- [ ] **Step 2: Write the packaging script**

Create `Scripts/package-kokoro.sh` with mode `755`. Replace `PBS_TAG` and
`PBS_FILE` with the values recorded in Task 1.

```bash
#!/bin/bash
# Đóng gói runtime Kokoro thành một archive tự chứa, chạy được trên máy chưa
# từng cài Python. Script này dành cho người bảo trì, không phải người dùng.
#
# Khác biệt cốt lõi so với cách cũ: KHÔNG dùng venv. Venv ghi đường dẫn tuyệt
# đối của máy build vào pyvenv.cfg và symlink, nên gói chép sang máy khác là
# chết. CPython relocatable + `pip install --target` thì không có gì để hỏng.
set -euo pipefail

cd "$(dirname "$0")/.."
PROJECT_DIR="$(pwd)"

VERSION="${1:-1.0.0}"
PBS_TAG="20250818"
PBS_FILE="cpython-3.12.11+${PBS_TAG}-aarch64-apple-darwin-install_only.tar.gz"
STAGE="$(mktemp -d)"
OUT_DIR="${PROJECT_DIR}/build"
OUT="${OUT_DIR}/kokoro-runtime-${VERSION}-arm64.tar.zst"

trap 'rm -rf "${STAGE}"' EXIT

echo "==> CPython relocatable"
curl -fL -o "${STAGE}/python.tar.gz" \
  "https://github.com/astral-sh/python-build-standalone/releases/download/${PBS_TAG}/${PBS_FILE}"
tar -xf "${STAGE}/python.tar.gz" -C "${STAGE}"
rm "${STAGE}/python.tar.gz"

PY="${STAGE}/python/bin/python3"

echo "==> Dependency (khong torch, khong gradio)"
"${PY}" -m pip install --quiet --upgrade pip
"${PY}" -m pip install --quiet --target "${STAGE}/site-packages" \
  onnxruntime numpy soundfile sea-g2p \
  "kokoro-vietnamese @ git+https://github.com/iamdinhthuan/Kokoro-Vietnamese.git"

if ls "${STAGE}/site-packages" | grep -qi '^torch'; then
    echo "LOI: torch lot vao goi. Dung lai." >&2
    exit 1
fi

echo "==> Model"
mkdir -p "${STAGE}/models"
"${PY}" -m pip install --quiet --target "${STAGE}/hftmp" huggingface_hub
PYTHONPATH="${STAGE}/hftmp" "${PY}" - "${STAGE}/models" <<'PY'
import sys
from huggingface_hub import snapshot_download
snapshot_download("contextboxai/Kokoro-Vietnamese", local_dir=sys.argv[1])
PY
rm -rf "${STAGE}/hftmp"

echo "==> Convert voicepack .pt -> .npy"
"${PY}" -m pip install --quiet --target "${STAGE}/torchtmp" torch --index-url https://download.pytorch.org/whl/cpu
PYTHONPATH="${STAGE}/torchtmp" "${PY}" - "${STAGE}/models/voicepacks" <<'PY'
import sys
from pathlib import Path
import numpy as np
import torch

folder = Path(sys.argv[1])
count = 0
for source in sorted(folder.glob("*.pt")):
    tensor = torch.load(source, map_location="cpu", weights_only=True)
    np.save(source.with_suffix(".npy"), tensor.detach().cpu().numpy())
    source.unlink()
    count += 1
print(f"Da convert {count} voicepack")
PY
rm -rf "${STAGE}/torchtmp"

cp "${PROJECT_DIR}/Resources/kokoro_service.py" "${STAGE}/kokoro_service.py"

cat > "${STAGE}/manifest.json" <<EOF
{"version": "${VERSION}"}
EOF

echo "==> Don rac"
find "${STAGE}" -name '__pycache__' -type d -prune -exec rm -rf {} +
find "${STAGE}" -name '*.pyc' -delete
rm -rf "${STAGE}/site-packages/gradio" "${STAGE}/site-packages/gradio_client"

echo "==> Nen"
mkdir -p "${OUT_DIR}"
tar --zstd -cf "${OUT}" -C "${STAGE}" .

echo
echo "Archive: ${OUT}"
echo "SIZE:    $(stat -f%z "${OUT}")"
echo "SHA256:  $(shasum -a 256 "${OUT}" | awk '{print $1}')"
echo
echo "Dan SIZE va SHA256 vao KokoroPackage.current trong"
echo "Sources/SubVoiceCore/KokoroPackage.swift, roi attach archive vao GitHub Release."
```

If Task 1 Step 4 found the binaries need re-signing, insert this immediately before
the `==> Nen` block:

```bash
echo "==> Ky lai binary"
codesign --force --sign - --deep "${STAGE}/python/bin/python3"
find "${STAGE}/site-packages" -name '*.so' -o -name '*.dylib' \
  | while read -r lib; do codesign --force --sign - "${lib}"; done
```

- [ ] **Step 3: Make it executable and run it**

Run:

```bash
chmod +x Scripts/package-kokoro.sh && ./Scripts/package-kokoro.sh 1.0.0
```

Expected: finishes and prints `Archive:`, `SIZE:` and `SHA256:`. **Write those two
values down — Task 3 Step 5 pastes them into Swift.**

- [ ] **Step 4: Prove the archive works with nothing else installed**

```bash
VERIFY="$(mktemp -d)"
tar --zstd -xf build/kokoro-runtime-1.0.0-arm64.tar.zst -C "${VERIFY}"
ls "${VERIFY}"
env -i PYTHONPATH="${VERIFY}/site-packages" "${VERIFY}/python/bin/python3" - "${VERIFY}" <<'PY'
import sys
from pathlib import Path
root = Path(sys.argv[1])
from kokoro_vietnamese.onnx_cli import KokoroVietnameseONNX
tts = KokoroVietnameseONNX(
    voice="diem_trinh",
    onnx_path=root / "models/kokoro_vi.onnx",
    voicepack_path=root / "models/voicepacks/diem_trinh.npy",
    config_path=root / "models/config.json",
)
import numpy as np
tts.voicepack = np.load(root / "models/voicepacks/diem_trinh.npy")
audio, _ = tts.synthesize("Xin chào, đây là giọng đọc của SubVoice.", speed=1.0)
print("SYNTH-OK", audio.shape)
PY
```

Expected: `ls` shows `python`, `site-packages`, `models`, `kokoro_service.py`,
`manifest.json` at the top level with no wrapper directory, and the script prints
`SYNTH-OK` with a non-empty shape. `env -i` clears the environment, so a pass here
means the archive does not depend on anything already on the build machine.

- [ ] **Step 5: Commit**

```bash
git add Scripts/package-kokoro.sh Resources/kokoro_service.py
git commit -m "feat: package Kokoro runtime as a relocatable archive"
```

The `.tar.zst` lives in `build/`, which is already git-ignored. Attach it to a
GitHub Release manually.

---

### Task 3: Add the pure install pipeline to SubVoiceCore

**Files:**

- Create: `Sources/SubVoiceCore/KokoroPackage.swift`
- Create: `Tests/SubVoiceCoreTests/KokoroPackageTests.swift`

**Interfaces:**

- Produces: `KokoroPackage`, `KokoroInstallLayout`, `KokoroManifest`, `KokoroInstallError`.
- `KokoroPackage.install(downloadedArchive:into:)` is the only way the app installs anything.
- No networking in this file. The caller hands it a file that is already on disk.

- [ ] **Step 1: Write the failing tests**

```swift
import CryptoKit
import Foundation
import Testing
@testable import SubVoiceCore

@Suite("Kokoro package")
struct KokoroPackageTests {

    /// Dựng một archive tar.zst thật trong thư mục tạm, giống hệt cái mà
    /// Scripts/package-kokoro.sh tạo ra: không có thư mục bọc ngoài.
    private func makeArchive(in directory: URL, marker: String) throws -> URL {
        let stage = directory.appendingPathComponent("stage", isDirectory: true)
        let python = stage.appendingPathComponent("python/bin", isDirectory: true)
        let models = stage.appendingPathComponent("models", isDirectory: true)
        try FileManager.default.createDirectory(at: python, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: models, withIntermediateDirectories: true)
        try marker.write(
            to: python.appendingPathComponent("python3"),
            atomically: true,
            encoding: .utf8
        )
        try marker.write(
            to: models.appendingPathComponent("kokoro_vi.onnx"),
            atomically: true,
            encoding: .utf8
        )

        let archive = directory.appendingPathComponent("runtime.tar.zst")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.arguments = ["--zstd", "-cf", archive.path, "-C", stage.path, "."]
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
        return archive
    }

    private func sha256(of url: URL) throws -> String {
        let digest = SHA256.hash(data: try Data(contentsOf: url))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("KokoroPackageTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func installPutsTheRuntimeInPlaceAndWritesAManifest() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let archive = try makeArchive(in: directory, marker: "moi")
        let layout = KokoroInstallLayout(applicationSupport: directory)
        let package = KokoroPackage(
            version: "1.0.0",
            downloadURL: URL(string: "https://example.invalid/runtime.tar.zst")!,
            sha256: try sha256(of: archive),
            downloadBytes: 1
        )

        try package.install(downloadedArchive: archive, into: layout)

        #expect(FileManager.default.fileExists(atPath: layout.python.path))
        #expect(!FileManager.default.fileExists(atPath: layout.incoming.path))
        let manifest = try JSONDecoder().decode(
            KokoroManifest.self,
            from: Data(contentsOf: layout.manifest)
        )
        #expect(manifest.version == "1.0.0")
    }

    @Test func wrongChecksumIsRefusedAndLeavesNothingBehind() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let archive = try makeArchive(in: directory, marker: "moi")
        let layout = KokoroInstallLayout(applicationSupport: directory)
        let package = KokoroPackage(
            version: "1.0.0",
            downloadURL: URL(string: "https://example.invalid/runtime.tar.zst")!,
            sha256: String(repeating: "0", count: 64),
            downloadBytes: 1
        )

        #expect(throws: KokoroInstallError.self) {
            try package.install(downloadedArchive: archive, into: layout)
        }
        #expect(!FileManager.default.fileExists(atPath: layout.root.path))
        #expect(!FileManager.default.fileExists(atPath: layout.incoming.path))
    }

    @Test func aFailedInstallLeavesTheExistingRuntimeUntouched() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let layout = KokoroInstallLayout(applicationSupport: directory)
        let goodArchive = try makeArchive(in: directory, marker: "cu")
        let installed = KokoroPackage(
            version: "1.0.0",
            downloadURL: URL(string: "https://example.invalid/runtime.tar.zst")!,
            sha256: try sha256(of: goodArchive),
            downloadBytes: 1
        )
        try installed.install(downloadedArchive: goodArchive, into: layout)

        let broken = KokoroPackage(
            version: "2.0.0",
            downloadURL: URL(string: "https://example.invalid/runtime.tar.zst")!,
            sha256: String(repeating: "0", count: 64),
            downloadBytes: 1
        )
        #expect(throws: KokoroInstallError.self) {
            try broken.install(downloadedArchive: goodArchive, into: layout)
        }

        let marker = try String(contentsOf: layout.python, encoding: .utf8)
        #expect(marker == "cu")
        let manifest = try JSONDecoder().decode(
            KokoroManifest.self,
            from: Data(contentsOf: layout.manifest)
        )
        #expect(manifest.version == "1.0.0")
    }

    @Test func installedVersionIsReportedOnlyWhenTheManifestMatches() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let layout = KokoroInstallLayout(applicationSupport: directory)
        #expect(layout.installedVersion() == nil)

        let archive = try makeArchive(in: directory, marker: "moi")
        let package = KokoroPackage(
            version: "1.0.0",
            downloadURL: URL(string: "https://example.invalid/runtime.tar.zst")!,
            sha256: try sha256(of: archive),
            downloadBytes: 1
        )
        try package.install(downloadedArchive: archive, into: layout)

        #expect(layout.installedVersion() == "1.0.0")
    }
}
```

- [ ] **Step 2: Run the tests and confirm they fail**

Run: `swift test --filter KokoroPackageTests`

Expected: compilation fails with `cannot find 'KokoroInstallLayout' in scope`.

- [ ] **Step 3: Implement the package model and layout**

Create `Sources/SubVoiceCore/KokoroPackage.swift`:

```swift
import CryptoKit
import Foundation

/// Nội dung `manifest.json` nằm trong thư mục runtime đã cài.
public struct KokoroManifest: Codable, Equatable, Sendable {
    public let version: String

    public init(version: String) {
        self.version = version
    }
}

/// Các đường dẫn liên quan tới một lần cài. Gom vào một chỗ để không có
/// chuỗi đường dẫn nào bị viết tay hai lần.
public struct KokoroInstallLayout: Equatable, Sendable {
    public let root: URL
    public let incoming: URL
    public let previous: URL

    public init(applicationSupport: URL) {
        let base = applicationSupport.appendingPathComponent("SubVoice", isDirectory: true)
        root = base.appendingPathComponent("Kokoro", isDirectory: true)
        incoming = base.appendingPathComponent("Kokoro.incoming", isDirectory: true)
        previous = base.appendingPathComponent("Kokoro.old", isDirectory: true)
    }

    public var manifest: URL { root.appendingPathComponent("manifest.json") }
    public var python: URL { root.appendingPathComponent("python/bin/python3") }
    public var sitePackages: URL {
        root.appendingPathComponent("site-packages", isDirectory: true)
    }
    public var models: URL { root.appendingPathComponent("models", isDirectory: true) }
    public var service: URL { root.appendingPathComponent("kokoro_service.py") }

    /// Phiên bản đang cài, hoặc `nil` nếu chưa cài hoặc bản cài hỏng.
    public func installedVersion(fileManager: FileManager = .default) -> String? {
        guard let data = fileManager.contents(atPath: manifest.path),
              let decoded = try? JSONDecoder().decode(KokoroManifest.self, from: data),
              fileManager.fileExists(atPath: python.path)
        else { return nil }
        return decoded.version
    }
}

/// Giai đoạn của một lần cài, để giao diện nói đúng việc đang diễn ra thay vì
/// gộp tất cả vào một chữ "đang cài".
public enum KokoroInstallPhase: Equatable, Sendable {
    case verifying
    case extracting
    case finishing
}

public enum KokoroInstallError: LocalizedError, Equatable {
    case checksumMismatch(expected: String, actual: String)
    case extractionFailed(String)
    case incompleteArchive
    case notEnoughDiskSpace(requiredBytes: Int64, availableBytes: Int64)

    public var errorDescription: String? {
        switch self {
        case .checksumMismatch:
            return "Gói tải về không toàn vẹn. Hãy thử tải lại."
        case .extractionFailed(let detail):
            return "Không giải nén được gói Kokoro: \(detail)"
        case .incompleteArchive:
            return "Gói Kokoro thiếu tệp bắt buộc."
        case .notEnoughDiskSpace(let required, let available):
            let formatter = ByteCountFormatter()
            return "Cần \(formatter.string(fromByteCount: required)) trống, "
                + "máy chỉ còn \(formatter.string(fromByteCount: available))."
        }
    }
}

/// Gói runtime Kokoro mà bản app này biết cách cài.
public struct KokoroPackage: Equatable, Sendable {
    public let version: String
    public let downloadURL: URL
    public let sha256: String
    public let downloadBytes: Int64

    public init(version: String, downloadURL: URL, sha256: String, downloadBytes: Int64) {
        self.version = version
        self.downloadURL = downloadURL
        self.sha256 = sha256
        self.downloadBytes = downloadBytes
    }
}
```

- [ ] **Step 4: Implement the install pipeline**

Append to the same file:

```swift
extension KokoroPackage {

    /// Cần chỗ cho cả archive lẫn bản giải nén cùng lúc.
    public var requiredFreeBytes: Int64 { downloadBytes * 3 }

    public static func availableBytes(
        at url: URL
    ) -> Int64 {
        let values = try? url.resourceValues(
            forKeys: [.volumeAvailableCapacityForImportantUsageKey]
        )
        return values?.volumeAvailableCapacityForImportantUsage ?? 0
    }

    public func checkDiskSpace(at url: URL) throws {
        let available = Self.availableBytes(at: url)
        guard available >= requiredFreeBytes else {
            throw KokoroInstallError.notEnoughDiskSpace(
                requiredBytes: requiredFreeBytes,
                availableBytes: available
            )
        }
    }

    /// Cài gói đã tải về. Không đụng tới mạng.
    ///
    /// Thứ tự đổi tên ở cuối là chỗ quan trọng nhất: bản cũ chỉ bị xoá SAU khi
    /// bản mới đã nằm đúng chỗ, nên không có thời điểm nào người dùng còn lại
    /// một bản cài dở.
    public func install(
        downloadedArchive archive: URL,
        into layout: KokoroInstallLayout,
        fileManager: FileManager = .default,
        extract: (URL, URL) throws -> Void = KokoroPackage.extractTarZstd(archive:destination:),
        onPhase: (KokoroInstallPhase) -> Void = { _ in }
    ) throws {
        onPhase(.verifying)
        let actual = try Self.sha256Hex(of: archive)
        guard actual == sha256 else {
            try? fileManager.removeItem(at: archive)
            throw KokoroInstallError.checksumMismatch(expected: sha256, actual: actual)
        }

        onPhase(.extracting)
        try? fileManager.removeItem(at: layout.incoming)
        try fileManager.createDirectory(
            at: layout.incoming,
            withIntermediateDirectories: true
        )

        var installed = false
        defer { if !installed { try? fileManager.removeItem(at: layout.incoming) } }

        try extract(archive, layout.incoming)

        let required = [
            layout.incoming.appendingPathComponent("python/bin/python3").path,
            layout.incoming.appendingPathComponent("models/kokoro_vi.onnx").path,
        ]
        guard required.allSatisfy(fileManager.fileExists(atPath:)) else {
            throw KokoroInstallError.incompleteArchive
        }

        let manifest = try JSONEncoder().encode(KokoroManifest(version: version))
        try manifest.write(to: layout.incoming.appendingPathComponent("manifest.json"))

        onPhase(.finishing)
        try? fileManager.removeItem(at: layout.previous)
        let hadPrevious = fileManager.fileExists(atPath: layout.root.path)
        if hadPrevious {
            try fileManager.moveItem(at: layout.root, to: layout.previous)
        }
        do {
            try fileManager.moveItem(at: layout.incoming, to: layout.root)
        } catch {
            if hadPrevious {
                try? fileManager.moveItem(at: layout.previous, to: layout.root)
            }
            throw error
        }
        installed = true
        try? fileManager.removeItem(at: layout.previous)
    }

    static func sha256Hex(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// macOS 14 có sẵn bsdtar hỗ trợ zstd, nên không cần thư viện giải nén nào.
    public static func extractTarZstd(archive: URL, destination: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.arguments = ["--zstd", "-xf", archive.path, "-C", destination.path]
        let errors = Pipe()
        process.standardError = errors
        try process.run()
        let detail = String(
            data: errors.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw KokoroInstallError.extractionFailed(
                detail.isEmpty ? "tar thoát với mã \(process.terminationStatus)" : detail
            )
        }
    }
}
```

- [ ] **Step 5: Add the published package constants**

Append to the same file. Replace `<SHA256>` and `<SIZE>` with the two values
Task 2 Step 3 printed.

```swift
extension KokoroPackage {
    /// Gói mà bản app này biết cách cài. Đổi gói thì phải đổi cả ba giá trị.
    public static let current = KokoroPackage(
        version: "1.0.0",
        downloadURL: URL(string: "https://github.com/hoanganhuynh/subvoice/releases/download/kokoro-runtime-1.0.0/kokoro-runtime-1.0.0-arm64.tar.zst")!,
        sha256: "<SHA256>",
        downloadBytes: <SIZE>
    )
}
```

- [ ] **Step 6: Run the tests**

Run: `swift test --filter KokoroPackageTests`

Expected: all four tests pass.

- [ ] **Step 7: Commit**

```bash
git add Sources/SubVoiceCore/KokoroPackage.swift Tests/SubVoiceCoreTests/KokoroPackageTests.swift
git commit -m "feat: add atomic Kokoro install pipeline"
```

---

### Task 4: Teach the runtime and backend about the new layout

**Files:**

- Modify: `Sources/SubVoiceApp/KokoroRuntime.swift`
- Modify: `Sources/SubVoiceApp/AppCoordinator.swift:75-79`

**Interfaces:**

- Consumes: `KokoroInstallLayout` from Task 3.
- Produces: `AppCoordinator.rebuildKokoroBackend()`.
- After this task Kokoro is discovered through `manifest.json`, not through `.venv`.

- [ ] **Step 1: Rewrite runtime discovery**

Replace the whole body of `KokoroRuntime.discover(environment:fileManager:)` in
`Sources/SubVoiceApp/KokoroRuntime.swift` with:

```swift
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
            let python = root.appendingPathComponent("python/bin/python3")
            let service = root.appendingPathComponent("kokoro_service.py")
            let models = root.appendingPathComponent("models", isDirectory: true)
            let manifest = root.appendingPathComponent("manifest.json")

            let required = [
                python.path,
                service.path,
                manifest.path,
                models.appendingPathComponent("kokoro_vi.onnx").path,
                models.appendingPathComponent("config.json").path,
                models.appendingPathComponent("voicepacks/diem_trinh.npy").path,
            ]
            guard required.allSatisfy(fileManager.fileExists(atPath:)) else { continue }

            // Phiên bản lệch được coi như chưa cài, để bản cài kiểu cũ và bản
            // dở dang đều đi qua đúng một đường: mời người dùng tải lại.
            guard let data = fileManager.contents(atPath: manifest.path),
                  let decoded = try? JSONDecoder().decode(KokoroManifest.self, from: data),
                  decoded.version == KokoroPackage.current.version
            else { continue }

            let output = fileManager.temporaryDirectory
                .appendingPathComponent("SubVoice-Kokoro", isDirectory: true)
            try fileManager.createDirectory(at: output, withIntermediateDirectories: true)
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
```

Add `import SubVoiceCore` at the top of the file if it is not already there.

- [ ] **Step 2: Point PYTHONPATH at the vendored site-packages**

In `Sources/SubVoiceApp/KokoroSpeechBackend.swift`, inside `startProcessIfNeeded()`,
change:

```swift
        environment["PYTHONPATH"] = runtime.root
            .appendingPathComponent("src", isDirectory: true).path
```

to:

```swift
        // Gói mới không có venv, nên interpreter không tự thấy dependency.
        // PYTHONPATH là thứ duy nhất nối chúng lại.
        environment["PYTHONPATH"] = runtime.root
            .appendingPathComponent("site-packages", isDirectory: true).path
```

- [ ] **Step 3: Make the Kokoro backend rebuildable**

In `Sources/SubVoiceApp/AppCoordinator.swift`, replace lines 75-79:

```swift
    private var settings = Store.loadSettings()
    private lazy var kokoroSpeech = KokoroSpeechBackend(
        voiceIdentifier: settings.kokoroVoiceIdentifier
    )
    private var region = Store.loadRegion()
```

with:

```swift
    private var settings: Settings
    // Không còn `lazy`: `runtimeResult` được tính đúng một lần lúc khởi tạo, nên
    // sau khi cài xong Kokoro phải dựng một instance MỚI thì app mới thấy nó.
    private var kokoroSpeech: KokoroSpeechBackend
    private var region = Store.loadRegion()

    init() {
        let loaded = Store.loadSettings()
        settings = loaded
        kokoroSpeech = KokoroSpeechBackend(voiceIdentifier: loaded.kokoroVoiceIdentifier)
    }
```

- [ ] **Step 4: Add the rebuild method**

In the same file, immediately after `private func configureSpeechBackend(_:)`, add:

```swift
    /// Dựng lại backend Kokoro sau khi cài xong, để 14 giọng xuất hiện ngay mà
    /// người dùng không phải khởi động lại app.
    private func rebuildKokoroBackend() {
        kokoroSpeech.stop()
        kokoroSpeech = KokoroSpeechBackend(voiceIdentifier: settings.kokoroVoiceIdentifier)
        configureSpeechBackend(kokoroSpeech)
    }
```

- [ ] **Step 5: Build and run the full suite**

Run: `swift build --product SubVoiceApp && swift test`

Expected: builds with no errors, and all existing tests plus Task 3's four tests pass.

- [ ] **Step 6: Commit**

```bash
git add Sources/SubVoiceApp/KokoroRuntime.swift Sources/SubVoiceApp/KokoroSpeechBackend.swift Sources/SubVoiceApp/AppCoordinator.swift
git commit -m "refactor: discover Kokoro through the packaged manifest"
```

---

### Task 5: Add install state to the shared snapshot

**Files:**

- Create: `Sources/SubVoiceUI/KokoroInstallState.swift`
- Create: `Tests/SubVoiceUITests/KokoroInstallStateTests.swift`
- Modify: `Sources/SubVoiceUI/AppViewState.swift`

**Interfaces:**

- Produces: `KokoroInstallState`, and `AppIntent.downloadKokoro` / `.cancelKokoroDownload`.
- Consumed by Voice Studio, Settings and the wizard in later tasks — all three read this one value.

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
@testable import SubVoiceUI

@Suite("Kokoro install state")
struct KokoroInstallStateTests {

    @Test func downloadProgressIsAFraction() {
        let state = KokoroInstallState.downloading(received: 250, total: 1000)
        #expect(state.progress == 0.25)
        #expect(state.isBusy)
    }

    @Test func unknownTotalHasNoProgress() {
        let state = KokoroInstallState.downloading(received: 250, total: 0)
        #expect(state.progress == nil)
        #expect(state.isBusy)
    }

    @Test func verifyingAndExtractingAreBusyWithoutAFraction() {
        #expect(KokoroInstallState.verifying.progress == nil)
        #expect(KokoroInstallState.verifying.isBusy)
        #expect(KokoroInstallState.extracting.isBusy)
    }

    @Test func terminalStatesAreNotBusy() {
        #expect(!KokoroInstallState.notInstalled.isBusy)
        #expect(!KokoroInstallState.installed(version: "1.0.0").isBusy)
        #expect(!KokoroInstallState.failed(message: "hỏng").isBusy)
    }

    @Test func failureShowsItsOwnMessage() {
        #expect(KokoroInstallState.failed(message: "Mất mạng").statusText == "Mất mạng")
    }
}
```

- [ ] **Step 2: Run the tests and confirm they fail**

Run: `swift test --filter KokoroInstallStateTests`

Expected: compilation fails with `cannot find 'KokoroInstallState' in scope`.

- [ ] **Step 3: Implement the state**

Create `Sources/SubVoiceUI/KokoroInstallState.swift`:

```swift
import Foundation

/// Tiến trình cài Kokoro. Onboarding, Voice Studio và Settings cùng đọc giá trị
/// này, nên không có nơi nào tự đếm tiến trình riêng.
public enum KokoroInstallState: Equatable, Sendable {
    case notInstalled
    case downloading(received: Int64, total: Int64)
    case verifying
    case extracting
    case installed(version: String)
    case failed(message: String)

    public var isBusy: Bool {
        switch self {
        case .downloading, .verifying, .extracting: true
        case .notInstalled, .installed, .failed: false
        }
    }

    /// `nil` khi không xác định được phần trăm — thanh tiến trình phải chạy ở
    /// chế độ indeterminate chứ không đứng im ở 0%.
    public var progress: Double? {
        guard case .downloading(let received, let total) = self, total > 0 else {
            return nil
        }
        return Double(received) / Double(total)
    }

    public var statusText: String {
        switch self {
        case .notInstalled:
            "Chưa cài"
        case .downloading(let received, let total):
            Self.byteProgressText(received: received, total: total)
        case .verifying:
            "Đang kiểm tra gói tải về…"
        case .extracting:
            "Đang cài…"
        case .installed(let version):
            "Đã cài bản \(version)"
        case .failed(let message):
            message
        }
    }

    private static func byteProgressText(received: Int64, total: Int64) -> String {
        let formatter = ByteCountFormatter()
        guard total > 0 else {
            return "Đang tải \(formatter.string(fromByteCount: received))…"
        }
        return "Đang tải \(formatter.string(fromByteCount: received))"
            + " / \(formatter.string(fromByteCount: total))"
    }
}
```

- [ ] **Step 4: Add the state and intents to the snapshot**

In `Sources/SubVoiceUI/AppViewState.swift`, add this property to `AppViewState`
immediately after `public var kokoroAvailable = false`:

```swift
    public var kokoroInstall: KokoroInstallState = .notInstalled
```

and add these cases to `AppIntent`, immediately after `case setLaunchAtLogin(Bool)`:

```swift
    case downloadKokoro
    case cancelKokoroDownload
```

- [ ] **Step 5: Run the tests**

Run: `swift test --filter 'KokoroInstallStateTests|AppViewModelTests'`

Expected: all tests pass.

- [ ] **Step 6: Commit**

```bash
git add Sources/SubVoiceUI/KokoroInstallState.swift Sources/SubVoiceUI/AppViewState.swift Tests/SubVoiceUITests/KokoroInstallStateTests.swift
git commit -m "feat: add Kokoro install state to the app snapshot"
```

---

### Task 6: Download Kokoro in the background

**Files:**

- Create: `Sources/SubVoiceApp/KokoroInstaller.swift`
- Modify: `Sources/SubVoiceApp/AppCoordinator.swift`
- Modify: `Sources/SubVoiceUI/VoiceStudioView.swift`
- Modify: `Sources/SubVoiceUI/SettingsView.swift`

**Interfaces:**

- Consumes: `KokoroPackage.current`, `KokoroInstallLayout`, `KokoroInstallState`.
- Produces: `KokoroInstaller.start()`, `KokoroInstaller.cancel()`, `KokoroInstaller.onStateChange`.
- The app stays fully usable while a download runs.

- [ ] **Step 1: Implement the installer**

Create `Sources/SubVoiceApp/KokoroInstaller.swift`:

```swift
import Foundation
import SubVoiceCore

/// Tải gói Kokoro rồi giao cho `KokoroPackage` cài. Đây là lớp glue mỏng: mọi
/// logic đáng test đã nằm trong SubVoiceCore.
@MainActor
final class KokoroInstaller: NSObject, URLSessionDownloadDelegate {

    var onStateChange: ((KokoroInstallState) -> Void)?

    private let package: KokoroPackage
    private let layout: KokoroInstallLayout
    private let resumeDataURL: URL
    private var session: URLSession?
    private var task: URLSessionDownloadTask?

    private(set) var state: KokoroInstallState = .notInstalled {
        didSet { onStateChange?(state) }
    }

    init(package: KokoroPackage = .current, fileManager: FileManager = .default) {
        self.package = package
        let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? fileManager.temporaryDirectory
        layout = KokoroInstallLayout(applicationSupport: applicationSupport)
        resumeDataURL = applicationSupport
            .appendingPathComponent("SubVoice", isDirectory: true)
            .appendingPathComponent("kokoro-resume.data")
        super.init()
        refreshInstalledState()
    }

    /// Có gói tải dở từ phiên trước không.
    var hasResumableDownload: Bool {
        FileManager.default.fileExists(atPath: resumeDataURL.path)
    }

    func refreshInstalledState() {
        if let version = layout.installedVersion(), version == package.version {
            state = .installed(version: version)
        } else if !state.isBusy {
            state = .notInstalled
        }
    }

    func start() {
        guard !state.isBusy else { return }

        do {
            try FileManager.default.createDirectory(
                at: resumeDataURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try package.checkDiskSpace(at: layout.root.deletingLastPathComponent())
        } catch {
            state = .failed(message: error.localizedDescription)
            return
        }

        let session = self.session ?? URLSession(
            configuration: .default,
            delegate: self,
            delegateQueue: nil
        )
        self.session = session

        // Tải tiếp từ chỗ dở nếu phiên trước bị ngắt, thay vì đốt lại 500 MB.
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
        guard let task else { return }
        task.cancel { [weak self] resumeData in
            guard let self, let resumeData else { return }
            Task { @MainActor in
                try? resumeData.write(to: self.resumeDataURL)
            }
        }
        self.task = nil
        state = .notInstalled
    }

    // MARK: - URLSessionDownloadDelegate

    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        let expected = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : 0
        Task { @MainActor [weak self] in
            guard let self, self.state.isBusy else { return }
            self.state = .downloading(received: totalBytesWritten, total: expected)
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        // `location` bị xoá ngay khi callback trả về, nên phải chuyển đi trước.
        let staged = FileManager.default.temporaryDirectory
            .appendingPathComponent("kokoro-download-\(UUID().uuidString).tar.zst")
        try? FileManager.default.moveItem(at: location, to: staged)
        Task { @MainActor [weak self] in
            self?.finish(archive: staged)
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        guard let error else { return }
        let message = (error as NSError).code == NSURLErrorCancelled
            ? nil : error.localizedDescription
        Task { @MainActor [weak self] in
            guard let self, let message else { return }
            self.state = .failed(message: message)
        }
    }

    private func finish(archive: URL) {
        do {
            // Nhãn `onPhase:` viết rõ chứ không dùng trailing closure: hàm này
            // có hai tham số closure, và trailing closure sẽ khớp nhầm sang
            // `extract` nếu ai đó đổi thứ tự tham số sau này.
            try package.install(
                downloadedArchive: archive,
                into: layout,
                onPhase: { phase in
                    switch phase {
                    case .verifying: state = .verifying
                    case .extracting, .finishing: state = .extracting
                    }
                }
            )
            try? FileManager.default.removeItem(at: archive)
            try? FileManager.default.removeItem(at: resumeDataURL)
            state = .installed(version: package.version)
        } catch {
            try? FileManager.default.removeItem(at: archive)
            state = .failed(message: error.localizedDescription)
        }
    }
}
```

- [ ] **Step 2: Own the installer in the coordinator**

In `Sources/SubVoiceApp/AppCoordinator.swift`, add this property immediately after
`private var mainWindow: MainWindowController!`:

```swift
    private let kokoroInstaller = KokoroInstaller()
```

In `wirePipeline()`, add these lines at the end of the method:

```swift
        kokoroInstaller.onStateChange = { [weak self] state in
            guard let self else { return }
            // Cài xong thì dựng lại backend TRƯỚC khi phát state, để ảnh chụp
            // đầu tiên người dùng thấy đã có `kokoroAvailable == true`.
            if case .installed = state { self.rebuildKokoroBackend() }
            self.viewModel.apply { $0.kokoroInstall = state }
            self.menuBar?.render(self.viewModel.state)
        }
        kokoroInstaller.refreshInstalledState()
```

- [ ] **Step 3: Handle the two new intents**

In `handle(_:)`, add these cases immediately after `case .setLaunchAtLogin(let enabled):`
and its body:

```swift
        case .downloadKokoro:
            kokoroInstaller.start()
        case .cancelKokoroDownload:
            kokoroInstaller.cancel()
```

In `publishSnapshot(runState:)`, add this line immediately after the
`state.launchAtLoginEnabled = ...` line:

```swift
            state.kokoroInstall = kokoroInstaller.state
```

- [ ] **Step 4: Show progress in Voice Studio**

In `Sources/SubVoiceUI/VoiceStudioView.swift`, replace this block inside `body`:

```swift
                    if !state.kokoroAvailable {
                        Label(state.kokoroStatus.message, systemImage: "info.circle")
                            .font(.footnote)
                            .foregroundStyle(theme.secondaryText)
                    }
```

with:

```swift
                    if !state.kokoroAvailable {
                        KokoroInstallRow(state: state, viewModel: viewModel)
                    }
```

and add this view at the end of the same file:

```swift
/// Dòng tải Kokoro, dùng chung giữa Voice Studio và Settings.
struct KokoroInstallRow: View {

    let state: AppViewState
    let viewModel: AppViewModel

    @Environment(\.aurora) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: AuroraTheme.spacingXSmall) {
            Text(state.kokoroInstall.statusText)
                .font(.footnote)
                .foregroundStyle(isFailed ? theme.warning : theme.secondaryText)

            if state.kokoroInstall.isBusy {
                HStack(spacing: AuroraTheme.spacingSmall) {
                    if let progress = state.kokoroInstall.progress {
                        ProgressView(value: progress)
                    } else {
                        ProgressView()
                            .progressViewStyle(.linear)
                    }
                    Button("Huỷ") { viewModel.send(.cancelKokoroDownload) }
                }
            } else {
                Button(isFailed ? "Thử lại" : "Tải giọng Kokoro") {
                    viewModel.send(.downloadKokoro)
                }
                .help("Tải bộ giọng Kokoro để đọc tự nhiên hơn")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Cài Kokoro: \(state.kokoroInstall.statusText)")
    }

    private var isFailed: Bool {
        if case .failed = state.kokoroInstall { return true }
        return false
    }
}
```

- [ ] **Step 5: Show the same row in Settings diagnostics**

In `Sources/SubVoiceUI/SettingsView.swift`, replace this block:

```swift
                        DiagnosticRow(
                            symbolName: "cpu",
                            title: "Kokoro",
                            status: state.kokoroStatus,
                            actionTitle: nil,
                            action: {}
                        )
```

with:

```swift
                        VStack(alignment: .leading, spacing: AuroraTheme.spacingXSmall) {
                            DiagnosticRow(
                                symbolName: "cpu",
                                title: "Kokoro",
                                status: state.kokoroStatus,
                                actionTitle: nil,
                                action: {}
                            )
                            if !state.kokoroAvailable {
                                KokoroInstallRow(state: state, viewModel: viewModel)
                            }
                        }
```

- [ ] **Step 6: Build and run the full suite**

Run: `swift build --product SubVoiceApp && swift test`

Expected: builds with no errors and every test passes.

- [ ] **Step 7: Verify the download end to end**

Run:

```bash
rm -rf "$HOME/Library/Application Support/SubVoice/Kokoro"
./Scripts/bundle.sh debug
open "$HOME/Applications/SubVoice.app"
```

Then in the app: open Settings, confirm Kokoro shows "Chưa cài" with a
**Tải giọng Kokoro** button, press it, and check all of the following:

- The progress text advances and the window stays responsive.
- Starting and stopping capture still works while the download runs.
- When it finishes, Kokoro becomes selectable in Voice Studio **without relaunching**.
- Selecting a Kokoro voice and pressing **Thử giọng** produces audio.

- [ ] **Step 8: Commit**

```bash
git add Sources/SubVoiceApp/KokoroInstaller.swift Sources/SubVoiceApp/AppCoordinator.swift Sources/SubVoiceUI/VoiceStudioView.swift Sources/SubVoiceUI/SettingsView.swift
git commit -m "feat: download and install Kokoro in the background"
```

---

### Task 7: Add the first-run onboarding wizard

**Files:**

- Create: `Sources/SubVoiceUI/OnboardingStep.swift`
- Create: `Sources/SubVoiceUI/OnboardingView.swift`
- Create: `Tests/SubVoiceUITests/OnboardingStepTests.swift`
- Modify: `Sources/SubVoiceCore/Settings.swift`
- Modify: `Sources/SubVoiceUI/AppViewState.swift`
- Modify: `Sources/SubVoiceUI/SubVoiceRootView.swift`
- Modify: `Sources/SubVoiceUI/SettingsView.swift`
- Modify: `Sources/SubVoiceApp/AppCoordinator.swift`

**Interfaces:**

- Produces: `OnboardingStep`, `OnboardingView`, `AppIntent.finishOnboarding`, `AppIntent.restartOnboarding`.
- Step navigation is local view state. Only service-touching actions become intents.

- [ ] **Step 1: Write the failing step tests**

```swift
import Testing
@testable import SubVoiceUI

@Suite("Onboarding step")
struct OnboardingStepTests {

    @Test func stepsRunInTheDocumentedOrder() {
        #expect(OnboardingStep.allCases == [
            .welcome, .screenRecording, .voice, .region, .done,
        ])
    }

    @Test func firstStepHasNoPreviousAndLastHasNoNext() {
        #expect(OnboardingStep.welcome.previous == nil)
        #expect(OnboardingStep.welcome.next == .screenRecording)
        #expect(OnboardingStep.done.next == nil)
        #expect(OnboardingStep.done.previous == .region)
    }

    @Test func indicatorCountsFromOne() {
        #expect(OnboardingStep.welcome.indicator == "1/5")
        #expect(OnboardingStep.voice.indicator == "3/5")
        #expect(OnboardingStep.done.indicator == "5/5")
    }
}
```

- [ ] **Step 2: Run the tests and confirm they fail**

Run: `swift test --filter OnboardingStepTests`

Expected: compilation fails with `cannot find 'OnboardingStep' in scope`.

- [ ] **Step 3: Implement the step model**

Create `Sources/SubVoiceUI/OnboardingStep.swift`:

```swift
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
```

- [ ] **Step 4: Persist whether onboarding is done**

In `Sources/SubVoiceCore/Settings.swift`, add this stored property immediately after
`private var storedThemeMode: ThemeMode = .system`:

```swift
    private var storedHasCompletedOnboarding = false
```

add this coding key immediately after `case storedThemeMode`:

```swift
        case storedHasCompletedOnboarding
```

add this to `init(from:)` immediately after the `themeMode` assignment:

```swift
        hasCompletedOnboarding = try values.decodeIfPresent(
            Bool.self,
            forKey: .storedHasCompletedOnboarding
        ) ?? false
```

add this to `encode(to:)` immediately after the `storedThemeMode` line:

```swift
        try values.encode(storedHasCompletedOnboarding, forKey: .storedHasCompletedOnboarding)
```

and add this computed property immediately after `themeMode`:

```swift
    public var hasCompletedOnboarding: Bool {
        get { storedHasCompletedOnboarding }
        set { storedHasCompletedOnboarding = newValue }
    }
```

- [ ] **Step 5: Add the onboarding flag and intents to the snapshot**

In `Sources/SubVoiceUI/AppViewState.swift`, add these cases to `AppIntent`
immediately after `case cancelKokoroDownload`:

```swift
    case finishOnboarding
    case restartOnboarding
```

- [ ] **Step 6: Build the wizard**

Create `Sources/SubVoiceUI/OnboardingView.swift`:

```swift
import SubVoiceCore
import SwiftUI

/// Wizard lần đầu chạy. Luôn bỏ qua được: người dùng đã biết mình đang làm gì
/// không nên bị nhốt trong năm màn hình.
struct OnboardingView: View {

    let state: AppViewState
    let viewModel: AppViewModel

    @Environment(\.aurora) private var theme
    @State private var step: OnboardingStep = .welcome

    var body: some View {
        ZStack {
            AuroraBackground()

            VStack(alignment: .leading, spacing: AuroraTheme.spacingMedium) {
                HStack {
                    Text(step.indicator)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(theme.secondaryText)
                    Spacer()
                    Button("Bỏ qua") { viewModel.send(.finishOnboarding) }
                        .buttonStyle(.plain)
                        .foregroundStyle(theme.secondaryText)
                }

                Text(step.title)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(theme.primaryText)

                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                HStack {
                    if let previous = step.previous {
                        Button("Quay lại") { step = previous }
                    }
                    Spacer()
                    if let next = step.next {
                        Button("Tiếp tục") { step = next }
                            .keyboardShortcut(.defaultAction)
                    } else {
                        Button("Vào SubVoice") { viewModel.send(.finishOnboarding) }
                            .keyboardShortcut(.defaultAction)
                    }
                }
            }
            .padding(AuroraTheme.spacingLarge)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .welcome:
            welcomeContent
        case .screenRecording:
            screenRecordingContent
        case .voice:
            voiceContent
        case .region:
            regionContent
        case .done:
            doneContent
        }
    }

    private var welcomeContent: some View {
        VStack(alignment: .leading, spacing: AuroraTheme.spacingSmall) {
            Text("SubVoice đọc phụ đề trên màn hình thành tiếng Việt, để bạn nghe "
                + "thoại mà không phải rời mắt khỏi hình.")
                .foregroundStyle(theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Label(
                "Ảnh màn hình, OCR và giọng đọc đều xử lý trên máy bạn. Không có gì "
                + "rời khỏi thiết bị.",
                systemImage: "lock.shield"
            )
            .foregroundStyle(theme.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var screenRecordingContent: some View {
        VStack(alignment: .leading, spacing: AuroraTheme.spacingSmall) {
            Label(
                state.screenRecordingGranted ? "Đã được cấp quyền" : "Chưa có quyền",
                systemImage: state.screenRecordingGranted
                    ? "checkmark.circle" : "exclamationmark.circle"
            )
            .foregroundStyle(state.screenRecordingGranted ? theme.status : theme.warning)

            Text("SubVoice cần quyền Screen Recording để đọc được chữ trong vùng bạn chọn. "
                + "Không có quyền này thì app không thấy gì cả.")
                .foregroundStyle(theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            if !state.screenRecordingGranted {
                Button("Mở System Settings") {
                    viewModel.send(.recover(.openScreenRecordingSettings))
                }
                Text("Sau khi bật, hãy thoát SubVoice rồi mở lại. macOS chỉ áp dụng "
                    + "quyền này ở lần khởi động kế tiếp — đây là giới hạn của hệ điều "
                    + "hành, không phải lỗi của app.")
                    .font(.footnote)
                    .foregroundStyle(theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var voiceContent: some View {
        VStack(alignment: .leading, spacing: AuroraTheme.spacingSmall) {
            Label(
                state.systemVoiceStatus.message,
                systemImage: state.systemVoiceStatus.isReady
                    ? "checkmark.circle" : "exclamationmark.circle"
            )
            .foregroundStyle(state.systemVoiceStatus.isReady ? theme.status : theme.warning)

            if !state.systemVoiceStatus.isReady {
                Button("Mở Spoken Content") {
                    viewModel.send(.recover(.openSpokenContentSettings))
                }
            }

            Divider().overlay(theme.separator)

            Text("Giọng Kokoro — tự nhiên hơn, vẫn chạy offline")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(theme.primaryText)
            Text("Tải thêm khoảng \(sizeText). Bạn có thể dùng SubVoice bình thường "
                + "trong lúc tải, và bỏ qua bước này để tải sau trong Voice Studio.")
                .font(.footnote)
                .foregroundStyle(theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            KokoroInstallRow(state: state, viewModel: viewModel)
        }
    }

    private var sizeText: String {
        ByteCountFormatter().string(fromByteCount: KokoroPackage.current.downloadBytes)
    }

    private var regionContent: some View {
        VStack(alignment: .leading, spacing: AuroraTheme.spacingSmall) {
            Text("Kéo một khung quanh chỗ phụ đề hiện ra. SubVoice chỉ đọc chữ "
                + "bên trong khung đó.")
                .foregroundStyle(theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            if let region = state.region {
                Label(
                    "Màn hình \(region.displayID) · \(region.pixelWidth)×\(region.pixelHeight)",
                    systemImage: "checkmark.circle"
                )
                .foregroundStyle(theme.status)
            }

            Button(state.region == nil ? "Chọn vùng" : "Chọn lại vùng") {
                viewModel.send(.selectRegion)
            }
        }
    }

    private var doneContent: some View {
        VStack(alignment: .leading, spacing: AuroraTheme.spacingSmall) {
            Label("⌥⌘V — bật hoặc tắt đọc", systemImage: "keyboard")
            Label("⌥⌘R — chọn lại vùng phụ đề", systemImage: "keyboard")
            Label(
                "Đóng cửa sổ không làm SubVoice thoát. App vẫn sống trên menu bar.",
                systemImage: "menubar.arrow.up.rectangle"
            )
        }
        .foregroundStyle(theme.secondaryText)
    }
}
```

- [ ] **Step 7: Route the root view through the wizard**

In `Sources/SubVoiceUI/SubVoiceRootView.swift`, replace the whole `body` with:

```swift
    public var body: some View {
        Group {
            if viewModel.state.settings.hasCompletedOnboarding {
                dashboard
            } else {
                OnboardingView(state: viewModel.state, viewModel: viewModel)
            }
        }
        .environment(\.aurora, theme)
        .sheet(item: $route) { route in
            sheet(for: route)
                .environment(\.aurora, theme)
        }
    }

    private var dashboard: some View {
        FocusDashboardView(
            state: viewModel.state,
            viewModel: viewModel,
            onOpenSettings: { route = .settings },
            onOpenVoiceStudio: { route = .voiceStudio },
            onOpenTranscript: { route = .transcript }
        )
    }
```

- [ ] **Step 8: Add the rerun control to Settings**

In `Sources/SubVoiceUI/SettingsView.swift`, add this to the `"Khởi động"` section,
immediately after the launch-at-login `Toggle`:

```swift
                        Button("Chạy lại hướng dẫn") {
                            viewModel.send(.restartOnboarding)
                        }
```

- [ ] **Step 9: Handle the two intents in the coordinator**

In `Sources/SubVoiceApp/AppCoordinator.swift`, add these cases to `handle(_:)`
immediately after `case .cancelKokoroDownload:` and its body:

```swift
        case .finishOnboarding:
            settings.hasCompletedOnboarding = true
            Store.saveSettings(settings)
            publishSnapshot()
        case .restartOnboarding:
            settings.hasCompletedOnboarding = false
            Store.saveSettings(settings)
            publishSnapshot()
            showMainWindow()
```

In `start()`, add this immediately after the existing `Store.saveSettings(settings)`
call that follows the Kokoro availability check:

```swift
        // Người dùng bản cũ đã có vùng đọc thì coi như đã onboard — không bắt
        // họ xem lại wizard chỉ vì nâng cấp app.
        if !settings.hasCompletedOnboarding && region != nil {
            settings.hasCompletedOnboarding = true
            Store.saveSettings(settings)
        }
```

- [ ] **Step 10: Run the full suite and build**

Run: `swift test && swift build --product SubVoiceApp`

Expected: every test passes and the app builds.

- [ ] **Step 11: Verify the wizard by hand**

Run:

```bash
defaults delete com.williens.subvoice subvoice.settings
defaults delete com.williens.subvoice subvoice.region
./Scripts/bundle.sh debug
open "$HOME/Applications/SubVoice.app"
```

Check all of the following:

- The wizard opens at step 1 of 5 instead of the dashboard.
- **Bỏ qua** at any step lands on the dashboard and the wizard does not return on relaunch.
- Step 2 shows live permission state and warns that a relaunch is required.
- Step 3 starts a background download and the wizard still advances.
- Step 4 opens the region overlay and shows the chosen size afterwards.
- Settings → **Chạy lại hướng dẫn** brings the wizard back.
- Tab reaches every button and Escape does not trap focus.

- [ ] **Step 12: Commit**

```bash
git add Sources/SubVoiceUI/OnboardingStep.swift Sources/SubVoiceUI/OnboardingView.swift Sources/SubVoiceUI/SubVoiceRootView.swift Sources/SubVoiceUI/SettingsView.swift Sources/SubVoiceUI/AppViewState.swift Sources/SubVoiceCore/Settings.swift Sources/SubVoiceApp/AppCoordinator.swift Tests/SubVoiceUITests/OnboardingStepTests.swift
git commit -m "feat: add first-run onboarding wizard"
```

---

### Task 8: Ship it — bundle script, docs and a clean-machine check

**Files:**

- Modify: `Scripts/bundle.sh`
- Modify: `README.md`

**Interfaces:**

- Consumes: everything above.
- Produces: a bundle script that no longer copies a venv, and a README a stranger can follow.

- [ ] **Step 1: Stop copying the venv**

In `Scripts/bundle.sh`, delete the entire block that begins with the comment
`# Kokoro nặng khoảng 1.3 GB nên chỉ cài khi người dùng chủ động bật cờ này.`
and ends with the line `fi` that closes `if [ "${SUBVOICE_INCLUDE_KOKORO:-0}" = "1" ]; then`.

Replace it with:

```bash
# Người dùng cuối tải Kokoro từ trong app. Cờ này chỉ để người phát triển thử
# một archive cục bộ mà không phải đẩy lên GitHub Release trước.
if [ -n "${SUBVOICE_KOKORO_ARCHIVE:-}" ]; then
    if [ ! -f "${SUBVOICE_KOKORO_ARCHIVE}" ]; then
        echo "LỖI: không thấy archive ${SUBVOICE_KOKORO_ARCHIVE}" >&2
        exit 1
    fi
    KOKORO_RUNTIME="${HOME}/Library/Application Support/SubVoice/Kokoro"
    rm -rf "${KOKORO_RUNTIME}"
    mkdir -p "${KOKORO_RUNTIME}"
    tar --zstd -xf "${SUBVOICE_KOKORO_ARCHIVE}" -C "${KOKORO_RUNTIME}"
    echo "Đã cài Kokoro tu archive: ${KOKORO_RUNTIME}"
fi
```

- [ ] **Step 2: Rewrite the README install section**

In `README.md`, replace the whole `#### Chuẩn bị Kokoro` subsection — from that
heading through the line ending the `SUBVOICE_INCLUDE_KOKORO=1 ./Scripts/bundle.sh release`
code fence — with:

```markdown
#### Cài Kokoro

Không cần chuẩn bị gì. Mở SubVoice, vào **Cài đặt → Chẩn đoán → Kokoro** rồi bấm
**Tải giọng Kokoro**. App tải một gói tự chứa gồm cả Python runtime lẫn model, kiểm
tra chữ ký SHA-256 rồi cài vào:

```text
~/Library/Application Support/SubVoice/Kokoro
```

Tải xong là 14 giọng Kokoro xuất hiện ngay, không cần khởi động lại app. Gói này
chỉ có bản Apple Silicon.

Trong lúc tải, SubVoice vẫn dùng được bình thường với giọng hệ thống. Thoát app
giữa chừng cũng không mất phần đã tải — lần mở sau tải tiếp.

#### Đóng gói lại Kokoro (dành cho người bảo trì)

```bash
./Scripts/package-kokoro.sh 1.0.0
```

Script in ra `SHA256` và `SIZE`. Dán hai giá trị đó vào `KokoroPackage.current`
trong `Sources/SubVoiceCore/KokoroPackage.swift`, rồi attach archive vào một
GitHub Release trùng tên với `downloadURL`.
```

Then in the **Sử dụng** section, insert this as a new first step and renumber the
rest:

```markdown
1. Lần đầu mở, SubVoice dẫn bạn qua năm bước: cấp quyền, chọn giọng, chọn vùng.
   Bỏ qua bước nào cũng được, và chạy lại được từ **Cài đặt → Chạy lại hướng dẫn**.
```

Finally, add this bullet to **Điểm nổi bật**, immediately after the Voice Studio
bullet:

```markdown
- **Cài Kokoro từ trong app** — một gói tự chứa, tải nền, không cần Python trên máy.
```

- [ ] **Step 3: Run everything**

Run:

```bash
swift test
./Scripts/smoke-overlay.sh
./Scripts/smoke-window.sh
git diff --check
```

Expected: all tests pass, both smoke scripts exit zero, no whitespace errors.

- [ ] **Step 4: Build and verify the release bundle**

Run:

```bash
./Scripts/bundle.sh release
codesign --verify --deep --strict "$HOME/Applications/SubVoice.app"
plutil -extract LSUIElement raw "$HOME/Applications/SubVoice.app/Contents/Info.plist"
du -sh "$HOME/Applications/SubVoice.app"
```

Expected: signature verifies, `LSUIElement` prints `false`, and the bundle is a
few megabytes — no Python or model inside it.

- [ ] **Step 5: Prove it works on a machine that has never seen Kokoro**

This is the whole point of the plan, so do not skip it. Create a second macOS user
account, log in as that user, copy `SubVoice.app` across, and check:

- The app launches and shows the wizard.
- Granting Screen Recording and relaunching makes capture work.
- **Tải giọng Kokoro** downloads, installs and produces audio — on a machine with
  no Python, no `uv`, and no `ThirdParty/` checkout.
- Quitting mid-download and reopening resumes rather than restarting.

- [ ] **Step 6: Commit**

```bash
git add Scripts/bundle.sh README.md
git commit -m "docs: document in-app Kokoro install"
```

- [ ] **Step 7: Final check and push**

Run:

```bash
git status --short --branch
git log --format='%h %an <%ae> %s' origin/feat/subvoice..HEAD
```

Expected: clean worktree, and every new commit authored by
`Anthony <creative@williens.com>`.

Ask the user before pushing.
