#!/bin/bash
# Test hồi quy cho vòng đời cửa sổ chính.
#
# Phải chạy qua bản .app đã cài chứ không phải binary trong .build: cửa sổ chỉ
# hiện đúng khi app có Info.plist với `LSUIElement=false` và được khởi động như
# một ứng dụng thật.
set -euo pipefail
cd "$(dirname "$0")/.."

rm -f /tmp/subvoice-window-smoke.txt
./Scripts/bundle.sh debug
open "$HOME/Applications/SubVoice.app" --args --smoke-window

for _ in $(seq 1 30); do
    if [ -f /tmp/subvoice-window-smoke.txt ]; then
        grep -q '^WINDOW-SMOKE-OK$' /tmp/subvoice-window-smoke.txt
        echo "ĐẠT: cửa sổ chính hiện được."
        exit 0
    fi
    sleep 0.2
done

echo "Window smoke test timed out" >&2
exit 1
