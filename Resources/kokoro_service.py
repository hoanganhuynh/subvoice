#!/usr/bin/env python3
"""JSON-lines Kokoro TTS sidecar for SubVoice; stdout is protocol only."""
import argparse
import json
import os
import sys
from pathlib import Path

import soundfile as sf
import torch
from kokoro_vietnamese.core import SAMPLE_RATE, VOICES
from kokoro_vietnamese.onnx_cli import KokoroVietnameseONNX


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
        voicepack_path=models / "voicepacks" / "diem_trinh.pt",
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
            tts.voicepack = torch.load(models / VOICES[voice]["filename"], map_location="cpu", weights_only=True)
            audio, _ = tts.synthesize(text, speed=float(request.get("speed", 1.0)))
            path = args.output_dir / f"{identifier}.wav"
            sf.write(path, audio, SAMPLE_RATE)
            reply({"id": identifier, "path": str(path)})
        except Exception as error:
            reply({"id": request.get("id", "?"), "error": str(error)})

    # Một số bản PyTorch/ONNX trên macOS có thể đụng thứ tự huỷ mutex khi
    # interpreter đóng. Toàn bộ response đã flush, nên thoát thẳng sau EOF.
    os._exit(0)


if __name__ == "__main__":
    main()
