#!/usr/bin/env bash
# 빌드된 Mara.app의 번들 정체성 키와 PkgInfo를 확인한다 (CI "Bundle identity keys").
# App/Info.plist는 사용자 지정이라 Xcode가 이 키들을 대신 넣지 않는다 — 빠지면 이름이 바뀐 사본("Mara 2.app")의
# 서명이 "not signed at all"로 판정되고 spctl이 "does not seem to be an app"으로 거부한다.
set -euo pipefail

APP="${1:?usage: bundle-identity-gate.sh <path/to/Mara.app>}"
PLIST="$APP/Contents/Info.plist"
fail=0

expect_key() {
  local key="$1" want="$2" got
  got="$(/usr/libexec/PlistBuddy -c "Print :$key" "$PLIST" 2>/dev/null || true)"
  if [[ "$got" == "$want" ]]; then
    echo "ok   $key = $got"
  else
    echo "FAIL $key = '${got}' (want '$want')"
    fail=1
  fi
}

expect_key CFBundleExecutable Mara
expect_key CFBundlePackageType APPL
expect_key CFBundleInfoDictionaryVersion 6.0
expect_key CFBundleDevelopmentRegion en

if [[ -x "$APP/Contents/MacOS/Mara" ]]; then
  echo "ok   Contents/MacOS/Mara is executable"
else
  echo "FAIL Contents/MacOS/Mara missing or not executable"
  fail=1
fi

pkginfo="$(head -c 4 "$APP/Contents/PkgInfo" 2>/dev/null || true)"
if [[ "$pkginfo" == "APPL" ]]; then
  echo "ok   PkgInfo starts with APPL"
else
  echo "FAIL PkgInfo starts with '${pkginfo}' (want 'APPL')"
  fail=1
fi

exit "$fail"
