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

IDENTITY="${SUBVOICE_SIGN_IDENTITY:--}"
codesign --force --sign "${IDENTITY}" --timestamp=none "${APP_DIR}"
if [ "${IDENTITY}" = "-" ]; then
    echo "CẢNH BÁO: đang ký ad-hoc. macOS có thể hỏi lại quyền Screen Recording"
    echo "sau mỗi lần build. Xem hướng dẫn ở đầu file này để tránh."
fi

mkdir -p "${INSTALL_DIR}"
rm -rf "${INSTALL_DIR}/${APP_NAME}.app"
cp -R "${APP_DIR}" "${INSTALL_DIR}/${APP_NAME}.app"

echo "Đã cài: ${INSTALL_DIR}/${APP_NAME}.app"
echo "Chạy:   open ${INSTALL_DIR}/${APP_NAME}.app"
