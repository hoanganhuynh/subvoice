#!/bin/bash
# Lắp SubVoice.app từ output của SwiftPM rồi cài vào ~/Applications.
#
# Quyền Screen Recording gắn với chữ ký + đường dẫn app. Ký ad-hoc đổi chữ ký
# sau mỗi lần build nên macOS sẽ hỏi lại quyền liên tục. Tạo một chứng chỉ tự ký
# trong Keychain (Keychain Access › Certificate Assistant › Create a Certificate,
# loại Code Signing) rồi đặt biến môi trường để giữ quyền qua các lần build:
#
#   export SUBVOICE_SIGN_IDENTITY="Ten Chung Chi Cua Ban"
set -euo pipefail

cd "$(dirname "$0")/.."
PROJECT_DIR="$(pwd)"

CONFIG="${1:-release}"
APP_NAME="SubVoice"
BUILD_DIR=".build/${CONFIG}"
APP_DIR="build/${APP_NAME}.app"
INSTALL_DIR="${HOME}/Applications"

swift build -c "${CONFIG}" --product SubVoiceApp

rm -rf "${APP_DIR}"
mkdir -p "${APP_DIR}/Contents/MacOS" "${APP_DIR}/Contents/Resources"

cp "${BUILD_DIR}/SubVoiceApp" "${APP_DIR}/Contents/MacOS/SubVoiceApp"
cp Resources/Info.plist "${APP_DIR}/Contents/Info.plist"
cp Resources/AppIcon.icns "${APP_DIR}/Contents/Resources/AppIcon.icns"
cp Resources/Assets.car "${APP_DIR}/Contents/Resources/Assets.car"

# Tự dò một chứng chỉ ổn định nếu chưa đặt biến môi trường. Chữ ký ad-hoc gắn
# danh tính app vào cdhash của binary, mà cdhash đổi sau MỖI lần build -> quyền
# Screen Recording đã cấp lập tức thành vô hiệu. Chứng chỉ Apple Development gắn
# danh tính vào Team ID nên quyền giữ nguyên qua các lần build.
IDENTITY="${SUBVOICE_SIGN_IDENTITY:-}"
if [ -z "${IDENTITY}" ]; then
    IDENTITY=$(security find-identity -v -p codesigning \
        | grep -oE '"(Developer ID Application|Apple Development)[^"]*"' \
        | head -1 | tr -d '"')
fi
if [ -z "${IDENTITY}" ]; then
    IDENTITY="-"
fi

codesign --force --sign "${IDENTITY}" --timestamp=none "${APP_DIR}"

if [ "${IDENTITY}" = "-" ]; then
    echo "CẢNH BÁO: ký ad-hoc vì không tìm thấy chứng chỉ nào."
    echo "macOS sẽ hỏi lại quyền Screen Recording sau MỖI lần build."
else
    echo "Đã ký bằng: ${IDENTITY}"
fi

mkdir -p "${INSTALL_DIR}"
rm -rf "${INSTALL_DIR}/${APP_NAME}.app"
cp -R "${APP_DIR}" "${INSTALL_DIR}/${APP_NAME}.app"

# Kokoro nặng khoảng 1.3 GB nên chỉ cài khi người dùng chủ động bật cờ này.
# Runtime nằm ngoài .app để việc build/ký lại app không phải sao chép model
# mỗi lần và để backend có thể tìm ở đường dẫn ổn định.
if [ "${SUBVOICE_INCLUDE_KOKORO:-0}" = "1" ]; then
    KOKORO_SOURCE="${PROJECT_DIR}/ThirdParty/Kokoro-Vietnamese"
    KOKORO_RUNTIME="${HOME}/Library/Application Support/SubVoice/Kokoro"
    if [ ! -x "${KOKORO_SOURCE}/.venv/bin/python" ] \
        || [ ! -f "${KOKORO_SOURCE}/models/kokoro_vi.onnx" ]; then
        echo "LỖI: chưa có runtime Kokoro tại ${KOKORO_SOURCE}" >&2
        exit 1
    fi

    mkdir -p "${KOKORO_RUNTIME}"
    ditto "${KOKORO_SOURCE}/.venv" "${KOKORO_RUNTIME}/.venv"
    ditto "${KOKORO_SOURCE}/models" "${KOKORO_RUNTIME}/models"
    ditto "${KOKORO_SOURCE}/src" "${KOKORO_RUNTIME}/src"
    cp "${PROJECT_DIR}/Resources/kokoro_service.py" "${KOKORO_RUNTIME}/kokoro_service.py"
    if [ -f "${KOKORO_SOURCE}/LICENSE" ]; then
        cp "${KOKORO_SOURCE}/LICENSE" "${KOKORO_RUNTIME}/LICENSE"
    fi
    echo "Đã cài Kokoro: ${KOKORO_RUNTIME}"
fi

echo "Đã cài: ${INSTALL_DIR}/${APP_NAME}.app"
echo "Chạy:   open ${INSTALL_DIR}/${APP_NAME}.app"
