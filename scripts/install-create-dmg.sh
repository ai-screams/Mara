#!/usr/bin/env bash
# 핀·체크섬 검증된 create-dmg 설치 (공급망: `brew install create-dmg`의 버전 드리프트/포뮬러 변조 제거).
# release.yml이 DMG를 만들 때 쓰고, ci.yml이 같은 스크립트로 설치와 실행까지 확인한다 — 핀이 깨지면
# 릴리스 전에 PR에서 잡힌다. DMG 생성 자체는 릴리스 경로에서만 돌므로 rc 태그로 확인한다.
#
# 버전 올릴 때: VERSION 과 SHA256 을 함께 교체.
#   sha256 = `curl -fsSL <tarball URL> | shasum -a 256`
#   Homebrew 포뮬러(formulae.brew.sh/api/formula/create-dmg.json의 urls.stable.checksum)가 같은
#   tarball의 sha256을 따로 싣고 있어 교차 확인에 쓴다. v1.3.0 은 둘이 일치했다.
set -euo pipefail

VERSION="1.3.0"
SHA256="c50d2bc97c3d6292642bac55f530d247eaf4bf65ee605f26b4caf339383e381c"
URL="https://github.com/create-dmg/create-dmg/archive/refs/tags/v${VERSION}.tar.gz"

DEST="${RUNNER_TEMP:-/tmp}/create-dmg-${VERSION}"
TARBALL="${DEST}.tar.gz"
SRC="${DEST}-src"

curl -fsSL -o "$TARBALL" "$URL"
# 불일치 시 즉시 실패 — 다운로드 바이트가 핀과 다르면 공급망 변조로 간주하고 중단.
# (SHA256 한 글자를 바꾸면 shasum 이 FAILED 로 exit 1 — 로컬에서 확인.)
echo "${SHA256}  ${TARBALL}" | shasum -a 256 -c - >&2

rm -rf "$SRC" "$DEST" && mkdir -p "$SRC"
tar -xzf "$TARBALL" -C "$SRC" --strip-components 1

# create-dmg는 support/ 디렉터리를 `<bin>/../share/create-dmg/support`에서 찾는다.
# 저장소의 Makefile install 이 그 구조를 만든다.
make -C "$SRC" install prefix="$DEST" >/dev/null

BIN_DIR="${DEST}/bin"
# install prefix 를 다른 곳으로 바꾸면 이 가드가 exit 1 — 로컬에서 확인.
[ -x "${BIN_DIR}/create-dmg" ] || { echo "::error::create-dmg missing after install"; exit 1; }
"${BIN_DIR}/create-dmg" --version >&2

if [ -n "${GITHUB_PATH:-}" ]; then
  # 후속 워크플로 스텝(release.sh)이 PATH 에서 create-dmg 를 찾도록 등록.
  echo "$BIN_DIR" >> "$GITHUB_PATH"
  echo "✅ create-dmg ${VERSION} pinned & added to PATH" >&2
else
  # 로컬: 표준출력으로 bin 경로만 반환 (예: PATH="$(scripts/install-create-dmg.sh):$PATH").
  echo "$BIN_DIR"
fi
