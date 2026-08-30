#!/bin/bash
# Đọc log chẩn đoán của SubVoice. Mặc định 10 phút gần nhất.
#   ./Scripts/trace.sh          # 10 phút
#   ./Scripts/trace.sh 3m       # 3 phút
set -uo pipefail
WINDOW="${1:-10m}"
log show --predicate 'process == "SubVoiceApp"' --last "${WINDOW}" --style compact 2>/dev/null \
  | grep -E "TRACE|Độ trễ" \
  | sed -E 's/^[^ ]+ +([0-9:.]+) +.*(TRACE|Độ trễ)/\1 \2/'
