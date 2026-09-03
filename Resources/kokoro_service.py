#!/usr/bin/env python3
"""JSON-lines Kokoro TTS sidecar for SubVoice; stdout is protocol only."""
import argparse
import json
import os
import sys
import types
from pathlib import Path

import numpy as np
import soundfile as sf


def _install_numpy_torch_stub():
    """Cho phép bỏ hẳn torch (~430 MB) ra khỏi gói runtime.

    Đường ONNX của Kokoro chỉ dùng torch đúng một chỗ: `torch.load` để nạp
    voicepack trong `KokoroVietnameseONNX.__init__`. Voicepack đã được đóng gói
    sang .npy, và `select_voice_style` vốn nhận thẳng mảng numpy, nên một module
    giả có mỗi hàm `load` là đủ. `setdefault` để torch thật — nếu có, như khi
    chạy từ cây nguồn lúc phát triển — vẫn thắng.

    `np.load` chỉ đọc mảng thuần; nó từ chối tệp cần deserialise đối tượng.
    """
    stub = types.ModuleType("torch")
    stub.load = lambda path, *_args, **_kwargs: np.load(path)
    sys.modules.setdefault("torch", stub)


_install_numpy_torch_stub()

from kokoro_vietnamese.core import SAMPLE_RATE, VOICES  # noqa: E402
from kokoro_vietnamese.onnx_cli import KokoroVietnameseONNX  # noqa: E402


def voicepack_path(models: Path, voice: str) -> Path:
    """Đường dẫn .npy của một giọng. Gói runtime không còn tệp .pt nào."""
    return (models / VOICES[voice]["filename"]).with_suffix(".npy")


def reply(payload):
    print(json.dumps(payload, ensure_ascii=False), flush=True)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--models", required=True, type=Path)
    parser.add_argument("--output-dir", required=True, type=Path)
    args = parser.parse_args()
    models = args.models.resolve()
    args.output_dir.mkdir(parents=True, exist_ok=True)
    tts = KokoroVietnameseONNX(
        voice="diem_trinh",
        onnx_path=models / "kokoro_vi.onnx",
        voicepack_path=voicepack_path(models, "diem_trinh"),
        config_path=models / "config.json",
    )
    for raw in sys.stdin:
        request = {}
        try:
            request = json.loads(raw)
            identifier, text = request["id"], request["text"]
            voice = request.get("voice", "diem_trinh")
            if voice not in VOICES or not isinstance(text, str) or not text.strip():
                raise ValueError("Yêu cầu Kokoro không hợp lệ")
            tts.voicepack = np.load(voicepack_path(models, voice))
            audio, _ = tts.synthesize(text, speed=float(request.get("speed", 1.0)))
            path = args.output_dir / f"{identifier}.wav"
            sf.write(path, audio, SAMPLE_RATE)
            reply({"id": identifier, "path": str(path)})
        except Exception as error:
            reply({"id": request.get("id", "?"), "error": str(error)})

    # Một số bản ONNX trên macOS có thể đụng thứ tự huỷ mutex khi interpreter
    # đóng. Toàn bộ response đã flush, nên thoát thẳng sau EOF.
    os._exit(0)


if __name__ == "__main__":
    main()
