#!/bin/zsh
#
# Mara 배포본 빌드: xcodegen → archive → Developer ID export → 공증(notarize) → staple → DMG
#
# 결과물: dist/Mara-<version>.dmg  (드래그-투-Applications, Gatekeeper 통과)
#
# 정공법: Developer ID Application 인증서로 정상 서명 + Hardened Runtime + Apple 공증.
# (Apple Development/ad-hoc 서명은 배포 불가 — 공증이 거부된다.)
#
# ── 필요한 환경변수 ───────────────────────────────────────────────────────────
#   DEVELOPMENT_TEAM        Apple Developer Team ID (예: 7K6MK3KP9K)               [필수]
#   DEVELOPER_ID_IDENTITY   codesign 인증서 이름. 기본 "Developer ID Application"   [선택]
#
#   공증 자격은 아래 둘 중 하나:
#   (A) NOTARY_PROFILE      `xcrun notarytool store-credentials`로 저장한 키체인 프로필 이름
#   (B) APPLE_ID + APPLE_APP_PASSWORD(앱 암호) + DEVELOPMENT_TEAM
#
#   VERSION                 미지정 시 git 최신 태그(앞의 v 제거), 없으면 0.0.0-dev  [선택]
# ─────────────────────────────────────────────────────────────────────────────
#
# 자세한 사용법·CI 자동화는 RELEASING.md 참조.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

APP_NAME="Mara"
SCHEME="Mara"
PROJECT="$ROOT_DIR/$APP_NAME.xcodeproj"
BUILD_DIR="$ROOT_DIR/build/release"
DIST_DIR="$ROOT_DIR/dist"
ARCHIVE="$BUILD_DIR/$APP_NAME.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"
APP="$EXPORT_DIR/$APP_NAME.app"
EXPORT_OPTS="$BUILD_DIR/ExportOptions.plist"

DEVELOPER_ID_IDENTITY="${DEVELOPER_ID_IDENTITY:-Developer ID Application}"

die() { print -u2 "release: $1"; exit 1; }

# 실패 중단 시 임시 산출물 정리.
STAGE=""; ZIP=""
cleanup() { rm -rf "$STAGE" "$ZIP" 2>/dev/null || true; }
trap cleanup EXIT

# ── 사전 점검 ────────────────────────────────────────────────────────────────
command -v xcodegen >/dev/null 2>&1 || die "xcodegen 없음 (brew install xcodegen)"
xcrun --find notarytool >/dev/null 2>&1 || die "notarytool 없음 (Xcode 13+ 필요)"

[[ -n "${DEVELOPMENT_TEAM:-}" ]] || die "DEVELOPMENT_TEAM 미설정 (Apple Team ID)"
if [[ -z "${NOTARY_PROFILE:-}" ]]; then
    [[ -n "${APPLE_ID:-}" && -n "${APPLE_APP_PASSWORD:-}" ]] \
        || die "공증 자격 없음: NOTARY_PROFILE 또는 (APPLE_ID + APPLE_APP_PASSWORD) 필요"
fi

# 버전 결정: 인자 > VERSION > git 태그 > 기본값
VERSION="${1:-${VERSION:-}}"
if [[ -z "$VERSION" ]]; then
    VERSION="$(git describe --tags --abbrev=0 2>/dev/null || echo "0.0.0-dev")"
fi
VERSION="${VERSION#v}"  # 앞의 v 제거
# 형식 방어: SemVer만 허용. CI에서 VERSION은 git 태그(github.ref_name)에서 오는데, 태그명에
# 셸/경로/XML 특수문자가 들어가면 DMG 경로·ExportOptions.plist를 오염시킬 수 있다(모든 사용처는
# 인용돼 인젝션은 불가하나, 방어적으로 형식을 강제한다).
[[ "$VERSION" =~ '^[0-9]+\.[0-9]+\.[0-9]+([-.][0-9A-Za-z.-]+)?$' ]] \
    || die "예상치 못한 VERSION 거부: '$VERSION' (SemVer X.Y.Z 형식만 허용)"
DMG="$DIST_DIR/$APP_NAME-$VERSION.dmg"

# CFBundleVersion(=CURRENT_PROJECT_VERSION)은 단조 증가해야 하므로 git 커밋 수를 빌드번호로 쓴다.
# 표시용 MARKETING_VERSION은 태그의 SemVer 유지. CI 체크아웃은 fetch-depth: 0이어야 정확.
BUILD_NUMBER="$(git rev-list --count HEAD 2>/dev/null || echo 1)"

print "▸ $APP_NAME $VERSION (build $BUILD_NUMBER) 배포본 빌드 (team=$DEVELOPMENT_TEAM, id='$DEVELOPER_ID_IDENTITY')"

rm -rf "$BUILD_DIR" "$DIST_DIR"
mkdir -p "$BUILD_DIR" "$DIST_DIR"

# ── 0) Xcode 프로젝트 생성 (Mara.xcodeproj는 gitignore된 생성물) ──────────────
print "▸ [0/6] xcodegen generate…"
xcodegen generate

# ── 1) Archive (Release + Hardened Runtime, Developer ID 서명) ────────────────
print "▸ [1/6] archive…"
xcodebuild archive \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration Release \
    -destination "generic/platform=macOS" \
    -archivePath "$ARCHIVE" \
    DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" \
    MARKETING_VERSION="$VERSION" \
    CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY="$DEVELOPER_ID_IDENTITY" \
    ENABLE_HARDENED_RUNTIME=YES \
    OTHER_CODE_SIGN_FLAGS="--timestamp" \
    | tail -3

# ── 2) ExportOptions.plist (developer-id) ────────────────────────────────────
cat > "$EXPORT_OPTS" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key><string>developer-id</string>
    <key>teamID</key><string>$DEVELOPMENT_TEAM</string>
    <key>signingStyle</key><string>manual</string>
    <key>signingCertificate</key><string>$DEVELOPER_ID_IDENTITY</string>
    <key>destination</key><string>export</string>
</dict>
</plist>
PLIST

# ── 3) Export (서명된 .app) ──────────────────────────────────────────────────
print "▸ [2/6] export (Developer ID)…"
xcodebuild -exportArchive \
    -archivePath "$ARCHIVE" \
    -exportPath "$EXPORT_DIR" \
    -exportOptionsPlist "$EXPORT_OPTS" \
    | tail -3
[[ -d "$APP" ]] || die "export 실패: $APP 없음"

# 방어: MaraCore는 정적 링크라 내장 프레임워크가 없다(app-only 서명 가정). 동적 의존성이
# 추가돼 Contents/Frameworks가 생기면 inside-out 서명이 필요하므로 여기서 크게 실패시킨다.
[[ -d "$APP/Contents/Frameworks" ]] \
    && die "Contents/Frameworks 감지 — 동적 의존성 추가됨. inside-out 서명 필요(app-only 가정 위반)."

# ── 4) 서명/Hardened Runtime 검증 ────────────────────────────────────────────
print "▸ [3/6] 서명 검증…"
codesign --verify --strict --verbose=2 "$APP"
codesign -dvvv "$APP" 2>&1 | grep -iE "^Authority=Developer ID|runtime" >/dev/null \
    || die "Developer ID/Hardened Runtime 확인 실패 — 인증서를 점검하라"

# ── 공증 헬퍼 (자격: NOTARY_PROFILE 또는 APPLE_ID+APP_PASSWORD) ────────────────
# 실패 시 notary 로그를 덤프해 디버깅 가능하게 한다.
notarize() {
    local target="$1" out id
    if [[ -n "${NOTARY_PROFILE:-}" ]]; then
        # 단일 제출(--wait). 결과 JSON을 잡아 로그를 덤프하고, status가 Accepted가 아니면 중단한다.
        # (notarytool exit-code에 의존하지 않음 + stapler staple이 미공증을 하드 차단하는 백스톱.)
        out="$(xcrun notarytool submit "$target" --keychain-profile "$NOTARY_PROFILE" \
                --wait --output-format json)" || true
        print -r -- "$out" >&2
        id="$(print -r -- "$out" | plutil -extract id raw -o - - 2>/dev/null || true)"
        [[ -n "$id" ]] && xcrun notarytool log "$id" --keychain-profile "$NOTARY_PROFILE" >&2 2>/dev/null || true
        print -r -- "$out" | plutil -extract status raw -o - - 2>/dev/null | grep -q '^Accepted$' \
            || die "공증 결과가 Accepted 아님 (위 로그 참조): $target"
    else
        xcrun notarytool submit "$target" \
            --apple-id "$APPLE_ID" --password "$APPLE_APP_PASSWORD" --team-id "$DEVELOPMENT_TEAM" --wait
    fi
}

# ── 5) 공증 (notarytool) + staple the .app ───────────────────────────────────
print "▸ [4/6] 공증 제출 (수 분 소요)…"
ZIP="$BUILD_DIR/$APP_NAME.zip"
ditto -c -k --keepParent "$APP" "$ZIP"
notarize "$ZIP"
print "▸ [5/6] staple…"
xcrun stapler staple "$APP"
rm -f "$ZIP"; ZIP=""

# ── 6) DMG (드래그-투-Applications) ──────────────────────────────────────────
print "▸ [6/6] DMG 생성…"
STAGE="$BUILD_DIR/dmg-stage"
rm -rf "$STAGE"; mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"

# 앱 아이콘으로 DMG 볼륨 아이콘(.icns) 생성 → create-dmg --volicon.
ICONSET="$BUILD_DIR/$APP_NAME.iconset"
VOLICON="$BUILD_DIR/$APP_NAME.icns"
rm -rf "$ICONSET"; mkdir -p "$ICONSET"
cp "$ROOT_DIR/App/Assets.xcassets/AppIcon.appiconset/"icon_*.png "$ICONSET/" 2>/dev/null || true
iconutil -c icns "$ICONSET" -o "$VOLICON" 2>/dev/null || VOLICON=""

if command -v create-dmg >/dev/null 2>&1; then
    # create-dmg는 성공해도 종료코드가 비정상일 때가 있어 가드한다.
    create-dmg \
        --volname "$APP_NAME" \
        ${VOLICON:+--volicon "$VOLICON"} \
        --window-size 500 340 \
        --icon-size 100 \
        --icon "$APP_NAME.app" 130 180 \
        --app-drop-link 370 180 \
        --no-internet-enable \
        "$DMG" "$STAGE" || true
fi
if [[ ! -f "$DMG" ]]; then
    print "  (create-dmg 미사용/실패 → hdiutil 폴백)"
    ln -s /Applications "$STAGE/Applications"
    hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
fi

# create-dmg는 실패해도 부분 산출물을 남길 수 있어(위 `|| true`), 유효한 이미지인지 확인한다.
hdiutil imageinfo "$DMG" >/dev/null 2>&1 || die "생성된 DMG가 유효하지 않음: $DMG"

# DMG 컨테이너도 Developer ID 서명 → 공증 → staple(다운로드 시 경고 0, spctl open 통과).
print "▸ [+] DMG 서명 + 공증 + staple…"
codesign --force --timestamp --sign "$DEVELOPER_ID_IDENTITY" "$DMG"
notarize "$DMG"
xcrun stapler staple "$DMG"

# ── 게시 전 자가검증 ─────────────────────────────────────────────────────────
# 앱은 stapler로 검증한다(공증 티켓 부착 여부 = 권위 있는 확인). `spctl -a -t exec`는
# LSUIElement(메뉴바 agent) 앱에서 "does not seem to be an app" 오탐을 내므로 게이트로 쓰지 않는다.
# DMG는 사용자가 실제로 겪는 다운로드-오픈 Gatekeeper 흐름(`spctl -t open`)으로 검증한다.
print "▸ 검증…"
xcrun stapler validate "$APP" | sed 's/^/    /'
spctl -a -t open --context context:primary-signature -vv "$DMG" 2>&1 | sed 's/^/    /'
xcrun stapler validate "$DMG" | sed 's/^/    /'

print "✅ 완료: $DMG"
ls -la "$DMG" | cat
