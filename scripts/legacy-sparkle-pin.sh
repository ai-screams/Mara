#!/usr/bin/env bash
# 레거시 의존성 핀 단언: Sparkle 2.9.6 exact(10.13을 지원하는 마지막 보안 수정 라인)와 revision,
# 그리고 OpenCombine revision이 앱 workspace(config/Package.resolved)와 MaraCore 단독 경로
# (MaraCore/Package.resolved)에서 같은지. branch CI와 릴리스 빌드에서 모두 돈다.
set -euo pipefail
cd "$(dirname "$0")/.."

SPARKLE_VERSION="2.9.6"
SPARKLE_REVISION="ac2def288cbff5cfc7df3ffef6abdf45b72bcb0a"
fail() { echo "❌ legacy-sparkle-pin: $1" >&2; exit 1; }

pin() { # <resolved 파일> <identity> <version|revision>
  python3 -c 'import json,sys; p=json.load(open(sys.argv[1])); print(next(x["state"][sys.argv[3]] for x in p["pins"] if x["identity"]==sys.argv[2]))' "$@"
}

declared="$(sed -n '/^  Sparkle:$/,/^  [A-Za-z]/p' project.yml | awk '$1 == "exactVersion:" { print $2; exit }')"
[ "$declared" = "$SPARKLE_VERSION" ] || fail "project.yml Sparkle exactVersion=$declared (기대 $SPARKLE_VERSION)"
[ "$(pin config/Package.resolved sparkle version)" = "$SPARKLE_VERSION" ] || fail "config/Package.resolved Sparkle version 불일치"
[ "$(pin config/Package.resolved sparkle revision)" = "$SPARKLE_REVISION" ] || fail "config/Package.resolved Sparkle revision 불일치"

app_oc="$(pin config/Package.resolved opencombine revision)"
core_oc="$(pin MaraCore/Package.resolved opencombine revision)"
[ "$app_oc" = "$core_oc" ] || fail "OpenCombine revision 불일치: config=$app_oc MaraCore=$core_oc"

echo "✅ legacy-sparkle-pin: Sparkle $SPARKLE_VERSION ($SPARKLE_REVISION), OpenCombine $app_oc"
