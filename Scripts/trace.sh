#!/bin/bash
# Đọc file trace của SubVoice (chỉ có khi chạy app với cờ --trace).
#   ./Scripts/trace.sh        # toàn bộ
#   ./Scripts/trace.sh 60     # 60 dòng cuối
set -uo pipefail
FILE=/tmp/subvoice-trace.log
if [ ! -f "${FILE}" ]; then
    echo "Chưa có ${FILE}. Chạy: open ~/Applications/SubVoice.app --args --trace"
    exit 1
fi
if [ $# -ge 1 ]; then tail -n "$1" "${FILE}"; else cat "${FILE}"; fi
