#!/usr/bin/env bash
# 릴리스 앱에 프로비저닝 프로파일을 넣고, 릴리스 전용 entitlements로 최상위 앱을 다시 서명한 뒤 검증한다 (#91).
#
# 왜 export 뒤에 하나: 이 entitlement(topology-observation)는 제한 키라 프로파일 없이 선언하면 실행 즉시 죽는다.
# project.yml에 두면 로컬 Apple Development 빌드가 전부 죽고, 명령줄 PROVISIONING_PROFILE_SPECIFIER는
# SwiftPM 타깃(MaraCore)에도 적용돼 빌드가 깨진다. 그래서 릴리스 경로에서만, 서명된 export 산출물에 적용한다.
# 중첩 코드(Sparkle)는 export가 이미 서명했으므로 건드리지 않고 최상위 번들만 다시 서명한다.
#
# usage: embed-release-entitlements.sh <Mara.app> <profile.provisionprofile> <entitlements.plist> <codesign identity> <team id>
set -euo pipefail

APP="${1:?app path}"
PROFILE="${2:?provisioning profile path}"
ENTITLEMENTS="${3:?entitlements path}"
IDENTITY="${4:?codesign identity}"
TEAM="${5:?team id}"
KEY="com.apple.developer.networking.topology-observation"

die() { echo "embed-release-entitlements: $1" >&2; exit 1; }

[[ -d "$APP" ]] || die "app not found: $APP"
[[ -f "$PROFILE" ]] || die "provisioning profile not found: $PROFILE"
[[ -f "$ENTITLEMENTS" ]] || die "entitlements not found: $ENTITLEMENTS"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# 프로파일을 먼저 검사한다 — 다른 앱·팀의 프로파일이나 키가 없는 프로파일을 넣으면 앱이 실행 즉시 죽는다.
security cms -D -i "$PROFILE" > "$work/profile.plist" 2>/dev/null || die "cannot decode provisioning profile"
plist_get() { /usr/libexec/PlistBuddy -c "Print :$1" "$2" 2>/dev/null || true; }
bundle_id="$(plist_get CFBundleIdentifier "$APP/Contents/Info.plist")"
[[ -n "$bundle_id" ]] || die "CFBundleIdentifier missing in app"
[[ "$(plist_get Entitlements:com.apple.application-identifier "$work/profile.plist")" == "$TEAM.$bundle_id" ]] \
  || die "profile is not for $TEAM.$bundle_id"
[[ "$(plist_get TeamIdentifier:0 "$work/profile.plist")" == "$TEAM" ]] || die "profile team is not $TEAM"
[[ "$(plist_get "Entitlements:$KEY" "$work/profile.plist")" == "true" ]] || die "profile does not grant $KEY"
expires="$(plist_get ExpirationDate "$work/profile.plist")"
echo "ok   profile for $TEAM.$bundle_id grants $KEY (expires: $expires)"

# 넣고 다시 서명한다. --options runtime으로 Hardened Runtime을 유지하고, --timestamp는 공증 요건이다.
cp "$PROFILE" "$APP/Contents/embedded.provisionprofile"
codesign --force --timestamp --options runtime \
  --entitlements "$ENTITLEMENTS" --sign "$IDENTITY" "$APP"

# 결과 검증: 서명이 온전하고, 실제로 서명에 그 키가 실렸고, 넣은 프로파일이 그대로인지.
codesign --verify --deep --strict "$APP" || die "signature invalid after re-sign"
codesign -d --entitlements - --xml "$APP" > "$work/signed.plist" 2>/dev/null || die "cannot read signed entitlements"
[[ "$(plist_get "$KEY" "$work/signed.plist")" == "true" ]] || die "signed app does not carry $KEY"
cmp -s "$PROFILE" "$APP/Contents/embedded.provisionprofile" || die "embedded profile differs from input"
echo "ok   $APP signed with $KEY and embedded profile"
