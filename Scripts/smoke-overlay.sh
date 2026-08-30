#!/bin/bash
# Test hồi quy cho vòng đời cửa sổ overlay chọn vùng.
#
# Bắt lại đúng lỗi đã làm app tắt ngay khi bấm "Chọn lại vùng…": NSWindow tạo
# bằng code mặc định `isReleasedWhenClosed = true`, nên `close()` tự release
# cửa sổ một lần và ARC release lần nữa khi mảng `overlays` bị xoá. Cú release
# thừa đó không crash ngay mà nổ muộn trong CA transaction, nên stack trace của
# crash không chỉ ra thủ phạm — phải chạy dưới NSZombie mới thấy.
#
# Lưu ý: script bật một lớp phủ mờ toàn màn hình trong khoảng 2 giây.
set -uo pipefail
cd "$(dirname "$0")/.."

APP="${HOME}/Applications/SubVoice.app/Contents/MacOS/SubVoiceApp"
if [ ! -x "${APP}" ]; then
    echo "Chưa cài app. Chạy ./Scripts/bundle.sh trước."
    exit 1
fi

OUTPUT=$(NSZombieEnabled=YES MallocScribble=1 "${APP}" --smoke-overlay 2>&1)
STATUS=$?

if echo "${OUTPUT}" | grep -q "message sent to deallocated instance"; then
    echo "${OUTPUT}"
    echo "THẤT BẠI: cửa sổ overlay bị over-release."
    exit 1
fi
if ! echo "${OUTPUT}" | grep -q "OVERLAY-SMOKE-OK"; then
    echo "${OUTPUT}"
    echo "THẤT BẠI: app không chạy hết chu trình chọn vùng (exit ${STATUS}), có thể đã crash."
    exit 1
fi

echo "ĐẠT: vòng đời cửa sổ overlay sạch."
