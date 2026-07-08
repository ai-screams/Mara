#!/usr/bin/env bash
#
# release.sh — Build, Developer-ID-sign, notarize, staple, and package Mara
#              into a distributable, Gatekeeper-clean .dmg.
#
# ── One-time setup (done by YOU — see README "배포 (릴리스)") ────────────────
#   1. Apple Developer Program 가입.
#   2. "Developer ID Application" 인증서를 login keychain에 설치
#        (Xcode ▸ Settings ▸ Accounts ▸ Manage Certificates ▸ + ▸ Developer ID Application).
#   3. notarytool 자격증명 프로파일 저장(1회):
#        xcrun notarytool store-credentials mara-notary \
#          --apple-id "you@example.com" --team-id "TEAMID" \
#          --password "APP_SPECIFIC_PASSWORD"     # appleid.apple.com에서 발급
#
# ── 사용법 ──────────────────────────────────────────────────────────────────
#   NOTARY_PROFILE="mara-notary" scripts/release.sh
#
#   DEVELOPER_ID를 지정하지 않으면 keychain의 유일한 "Developer ID Application"
#   인증서를 자동 감지한다. 여러 개면 명시:
#     DEVELOPER_ID="Developer ID Application: Your Name (TEAMID)" \
#     NOTARY_PROFILE="mara-notary" scripts/release.sh
#
# ── 선택 env ────────────────────────────────────────────────────────────────
#   CONFIGURATION (기본 Release), BUILD_DIR, DIST_DIR
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

CONFIGURATION="${CONFIGURATION:-Release}"
BUILD_DIR="${BUILD_DIR:-$REPO_ROOT/build/release}"
DIST_DIR="${DIST_DIR:-$REPO_ROOT/dist}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"
DEVELOPER_ID="${DEVELOPER_ID:-}"
APP_NAME="Mara"

die() { echo "❌ $*" >&2; exit 1; }
step() { echo; echo "▶ $*"; }

# ── Preflight ────────────────────────────────────────────────────────────────
step "Preflight"
command -v xcodegen  >/dev/null || die "xcodegen 없음 (brew install xcodegen)"
command -v xcodebuild >/dev/null || die "xcodebuild 없음 (Xcode 필요)"
command -v xcrun     >/dev/null || die "xcrun 없음 (Xcode 필요)"
xcrun --find notarytool >/dev/null 2>&1 || die "notarytool 없음 (Xcode 13+ 필요)"
xcrun --find stapler    >/dev/null 2>&1 || die "stapler 없음 (Xcode 필요)"

[ -n "$NOTARY_PROFILE" ] || die "NOTARY_PROFILE 미설정. 먼저 'xcrun notarytool store-credentials <name> …' 후 NOTARY_PROFILE=<name> 지정."

if [ -z "$DEVELOPER_ID" ]; then
  # 유일한 Developer ID Application 인증서 자동 감지 (bash 3.2 호환 — mapfile 미사용).
  ids=()
  while IFS= read -r line; do
    [ -n "$line" ] && ids+=("$line")
  done < <(security find-identity -v -p codesigning 2>/dev/null \
    | grep "Developer ID Application" | sed -E 's/.*"([^"]+)".*/\1/')
  [ "${#ids[@]}" -gt 0 ] || die "keychain에 'Developer ID Application' 인증서 없음. Xcode ▸ Settings ▸ Accounts에서 발급."
  [ "${#ids[@]}" -eq 1 ] || die "Developer ID Application 인증서가 여러 개. DEVELOPER_ID=\"...\"로 명시: ${ids[*]}"
  DEVELOPER_ID="${ids[0]}"
fi
echo "  서명 정체성: $DEVELOPER_ID"
echo "  공증 프로파일: $NOTARY_PROFILE"

# ── Build (unsigned; 이후 수동 Developer ID 서명) ────────────────────────────
step "Build ($CONFIGURATION)"
xcodegen generate
rm -rf "$BUILD_DIR"
xcodebuild -project "$APP_NAME.xcodeproj" -scheme "$APP_NAME" \
  -configuration "$CONFIGURATION" -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO CONFIGURATION_BUILD_DIR="$BUILD_DIR" \
  build | tail -1

APP="$BUILD_DIR/$APP_NAME.app"
[ -d "$APP" ] || die "빌드 산출물 없음: $APP"
VERSION="$(plutil -extract CFBundleShortVersionString raw "$APP/Contents/Info.plist")"
echo "  버전: $VERSION"

# ── Sign (Hardened Runtime + timestamp) ─────────────────────────────────────
# MaraCore는 정적 링크되어 내장 프레임워크가 없다 → 앱 번들만 서명하면 된다.
step "Codesign (Developer ID + Hardened Runtime)"
codesign --force --options runtime --timestamp --sign "$DEVELOPER_ID" "$APP"
codesign --verify --strict --verbose=2 "$APP"

# ── Notarize + staple the .app (오프라인 첫 실행 대비) ───────────────────────
step "Notarize app"
APP_ZIP="$BUILD_DIR/$APP_NAME.app.zip"
ditto -c -k --keepParent "$APP" "$APP_ZIP"
xcrun notarytool submit "$APP_ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$APP"
rm -f "$APP_ZIP"

# ── Package .dmg (앱 + /Applications 심볼릭 링크) ────────────────────────────
step "Create .dmg"
mkdir -p "$DIST_DIR"
STAGE="$(mktemp -d)"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
DMG="$DIST_DIR/$APP_NAME-$VERSION.dmg"
rm -f "$DMG"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"

# ── Sign + notarize + staple the .dmg (다운로드 Gatekeeper clean) ────────────
step "Notarize dmg"
codesign --force --timestamp --sign "$DEVELOPER_ID" "$DMG"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$DMG"

# ── Verify ──────────────────────────────────────────────────────────────────
step "Verify"
echo "• app:"; spctl -a -t exec -vvv "$APP" 2>&1 | sed 's/^/    /'
echo "• app staple:"; xcrun stapler validate "$APP" | sed 's/^/    /'
echo "• dmg staple:"; xcrun stapler validate "$DMG" | sed 's/^/    /'

echo
echo "✅ 완료: $DMG"
echo "   이 .dmg를 배포하면 사용자는 열어서 Mara를 /Applications로 드래그하면 된다(Gatekeeper 경고 없음)."
