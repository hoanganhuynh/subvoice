#!/bin/bash
# Đóng gói runtime Kokoro thành một archive tự chứa, chạy được trên máy chưa
# từng cài Python. Script này dành cho người bảo trì, không phải người dùng.
#
# Khác biệt cốt lõi so với cách cũ: KHÔNG dùng venv. Venv ghi đường dẫn tuyệt
# đối của máy build vào pyvenv.cfg và symlink, nên gói chép sang máy khác là
# chết ngay. CPython relocatable + `pip install --target` thì không có gì để
# hỏng.
set -euo pipefail

cd "$(dirname "$0")/.."
PROJECT_DIR="$(pwd)"

VERSION="${1:-1.0.0}"
PBS_TAG="20250818"
PBS_FILE="cpython-3.12.11+${PBS_TAG}-aarch64-apple-darwin-install_only.tar.gz"
OUT_DIR="${PROJECT_DIR}/build"
OUT="${OUT_DIR}/kokoro-runtime-${VERSION}-arm64.tar.zst"

STAGE="$(mktemp -d)"
trap 'rm -rf "${STAGE}"' EXIT

PY="${STAGE}/python/bin/python3"

echo "==> CPython relocatable"
curl -fL --progress-bar -o "${STAGE}/python.tar.gz" \
    "https://github.com/astral-sh/python-build-standalone/releases/download/${PBS_TAG}/${PBS_FILE}"
tar -xf "${STAGE}/python.tar.gz" -C "${STAGE}"
rm "${STAGE}/python.tar.gz"

echo "==> Dependency"
# torch bị kéo vào ở đây dù đường ONNX không cần nó lúc chạy: transformers,
# safetensors, huggingface_hub và kokoro_vietnamese đều khai báo nó. Không cản
# được lúc cài, nên cắt ở bước prune bên dưới.
"${PY}" -m pip install --quiet --upgrade pip
"${PY}" -m pip install --quiet --target "${STAGE}/site-packages" \
    onnxruntime numpy soundfile sea-g2p \
    "kokoro-vietnamese @ git+https://github.com/iamdinhthuan/Kokoro-Vietnamese.git"

echo "==> Model"
mkdir -p "${STAGE}/models"
PYTHONPATH="${STAGE}/site-packages" "${PY}" - "${STAGE}/models" <<'PY'
import sys
from huggingface_hub import snapshot_download
snapshot_download("contextboxai/Kokoro-Vietnamese", local_dir=sys.argv[1])
PY

echo "==> Convert voicepack .pt -> .npy"
# Phải làm TRƯỚC khi prune, vì đọc .pt cần torch. Sau bước này gói không còn
# tệp .pt nào và sidecar nạp voicepack bằng numpy.
PYTHONPATH="${STAGE}/site-packages" "${PY}" - "${STAGE}/models/voicepacks" <<'PY'
import sys
from pathlib import Path
import numpy as np
import torch

folder = Path(sys.argv[1])
sources = sorted(folder.glob("*.pt"))
if not sources:
    raise SystemExit(f"Khong tim thay voicepack .pt nao trong {folder}")
for source in sources:
    tensor = torch.load(source, map_location="cpu", weights_only=True)
    array = tensor.detach().cpu().numpy()
    if array.ndim != 3 or array.shape[1:] != (1, 256):
        raise SystemExit(f"{source.name}: shape la {array.shape}, can [n, 1, 256]")
    np.save(source.with_suffix(".npy"), array)
    source.unlink()
print(f"Da convert {len(sources)} voicepack")
PY

cp "${PROJECT_DIR}/Resources/kokoro_service.py" "${STAGE}/kokoro_service.py"
printf '{"version": "%s"}\n' "${VERSION}" > "${STAGE}/manifest.json"

echo "==> Truoc khi prune: $(du -sh "${STAGE}/site-packages" | cut -f1)"

echo "==> Prune"
# Chỉ đường ONNX được dùng lúc chạy, nên toàn bộ stack PyTorch và web UI của
# upstream là thừa. Self-test bên dưới là thứ quyết định danh sách này đúng hay
# sai — đừng nới nó ra mà không chạy lại self-test.
for junk in torch torchgen functorch transformers safetensors huggingface_hub \
    gradio gradio_client fastapi uvicorn; do
    rm -rf "${STAGE}/site-packages/${junk}" \
           "${STAGE}/site-packages/${junk}"-*.dist-info \
           "${STAGE}/site-packages/${junk}".libs
done
find "${STAGE}" -name '__pycache__' -type d -prune -exec rm -rf {} + 2>/dev/null || true
find "${STAGE}" -name '*.pyc' -delete 2>/dev/null || true

echo "==> Sau khi prune:  $(du -sh "${STAGE}/site-packages" | cut -f1)"

echo "==> Self-test (env -i, khong ke thua gi tu may build)"
# `env -i` xoá sạch môi trường: nếu bước này chạy được thì gói thật sự tự chứa.
# Đây là hàng rào duy nhất chặn một archive hỏng đi tới người dùng.
if ! env -i PYTHONPATH="${STAGE}/site-packages" "${PY}" - "${STAGE}" <<'PY'
import sys
from pathlib import Path

root = Path(sys.argv[1])
sys.path.insert(0, str(root))

import kokoro_service  # cai stub torch roi import kokoro_vietnamese

models = root / "models"
tts = kokoro_service.KokoroVietnameseONNX(
    voice="diem_trinh",
    onnx_path=models / "kokoro_vi.onnx",
    voicepack_path=kokoro_service.voicepack_path(models, "diem_trinh"),
    config_path=models / "config.json",
)
audio, _ = tts.synthesize("Xin chào, đây là giọng đọc của SubVoice.", speed=1.0)
if audio is None or len(audio) == 0:
    raise SystemExit("Tong hop ra audio rong")

# Stub la module tao trong bo nho nen khong co __file__; torch that thi co.
if getattr(sys.modules["torch"], "__file__", None):
    raise SystemExit("torch that van bi nap — prune chua sach")

print(f"SELF-TEST-OK: {len(audio)} mau")
PY
then
    echo "LOI: self-test that bai. Archive KHONG duoc tao." >&2
    echo "Nhieu kha nang danh sach prune da cat nham mot goi con can luc chay." >&2
    exit 1
fi

echo "==> Nen"
mkdir -p "${OUT_DIR}"
rm -f "${OUT}"
tar --zstd -cf "${OUT}" -C "${STAGE}" .

SIZE="$(stat -f%z "${OUT}")"
SHA="$(shasum -a 256 "${OUT}" | awk '{print $1}')"

echo
echo "Archive: ${OUT}"
echo "SIZE:    ${SIZE}"
echo "SHA256:  ${SHA}"
echo
echo "Buoc tiep theo:"
echo "  1. Dan hai gia tri tren vao KokoroPackage.current trong"
echo "     Sources/SubVoiceCore/KokoroPackage.swift"
echo "  2. Tao GitHub Release tag kokoro-runtime-${VERSION} va attach archive nay"
