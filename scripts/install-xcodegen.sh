#!/usr/bin/env bash
# 핀·체크섬 검증된 XcodeGen 설치 (공급망: `brew install`의 버전 드리프트/포뮬러 변조 제거).
# ci.yml·release.yml이 이 스크립트를 "동일하게" 호출한다 — PR의 CI가 릴리스와 같은 설치 경로를
# 실제로 실행하므로, 핀이 깨지면 릴리스 전에 PR에서 잡힌다.
#
# 버전 올릴 때: VERSION 과 SHA256 을 함께 교체.
#   sha256 = `curl -fsSL <xcodegen.zip URL> | shasum -a 256`
set -euo pipefail

VERSION="2.45.4"
SHA256="090ec29491aad50aec10631bf6e62253fed733c50f3aab0f5ffc86bc170bdbef"
URL="https://github.com/yonaskolb/XcodeGen/releases/download/${VERSION}/xcodegen.zip"

DEST="${RUNNER_TEMP:-/tmp}/xcodegen-${VERSION}"
ZIP="${DEST}.zip"

curl -fsSL -o "$ZIP" "$URL"
# 불일치 시 즉시 실패 — 다운로드 바이트가 핀과 다르면 공급망 변조로 간주하고 중단.
echo "${SHA256}  ${ZIP}" | shasum -a 256 -c -

rm -rf "$DEST" && mkdir -p "$DEST"
unzip -q "$ZIP" -d "$DEST"

# 배포 zip 레이아웃: xcodegen/bin/xcodegen + xcodegen/share/xcodegen/SettingPresets.
# 바이너리는 SettingPresets 를 `<bin>/../share` 에서 찾으므로 이 구조를 그대로 유지한다.
BIN_DIR="${DEST}/xcodegen/bin"
[ -x "${BIN_DIR}/xcodegen" ] || { echo "::error::xcodegen binary missing after unzip"; exit 1; }
"${BIN_DIR}/xcodegen" --version >&2

if [ -n "${GITHUB_PATH:-}" ]; then
  # 후속 워크플로 스텝이 PATH 에서 xcodegen 을 찾도록 등록.
  echo "$BIN_DIR" >> "$GITHUB_PATH"
  echo "✅ XcodeGen ${VERSION} pinned & added to PATH" >&2
else
  # 로컬: 표준출력으로 bin 경로만 반환 (예: PATH="$(scripts/install-xcodegen.sh):$PATH").
  echo "$BIN_DIR"
fi
