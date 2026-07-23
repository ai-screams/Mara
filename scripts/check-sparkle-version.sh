#!/usr/bin/env bash
# project.yml의 사람이 읽는 exactVersion, committed Package.resolved, upstream 최신 stable release를 대조한다.
# Dependabot Swift entry는 외부 dependency가 없는 MaraCore만 보므로 Sparkle을 감시하지 못한다.
set -euo pipefail

normalize() { printf '%s\n' "${1#v}"; }
fail() { echo "❌ sparkle-version: $1" >&2; exit 1; }

selftest() {
  [ "$(normalize v2.9.4)" = "2.9.4" ] || fail "v prefix 정규화 실패"
  [ "$(normalize 2.9.4)" = "2.9.4" ] || fail "stable version 정규화 실패"
  echo "✅ sparkle-version: selftest 통과"
}

check_repo() {
  local declared resolved latest latest_tag
  declared="$(sed -n '/^  Sparkle:$/,/^[^ ]/p' project.yml \
    | awk '$1 == "exactVersion:" { gsub(/"/, "", $2); print $2; exit }')"
  [ -n "$declared" ] || fail "project.yml에서 Sparkle exactVersion을 찾지 못함"

  resolved="$(python3 -c 'import json; p=json.load(open("config/Package.resolved")); print(next(x["state"]["version"] for x in p["pins"] if x["identity"] == "sparkle"))')"
  [ "$declared" = "$resolved" ] \
    || fail "project.yml($declared)과 Package.resolved($resolved)가 다름"

  command -v gh >/dev/null || fail "upstream 조회에 gh CLI가 필요함"
  latest_tag="$(gh api repos/sparkle-project/Sparkle/releases/latest --jq .tag_name)" \
    || fail "GitHub API에서 Sparkle 최신 release를 조회하지 못함"
  [ -n "$latest_tag" ] || fail "GitHub API가 빈 Sparkle release tag를 반환함"
  latest="$(normalize "$latest_tag")"
  [ "$declared" = "$latest" ] || {
    echo "::error::Sparkle update available: current=$declared latest=$latest" >&2
    echo "https://github.com/sparkle-project/Sparkle/releases/tag/$latest" >&2
    exit 1
  }

  echo "✅ sparkle-version: declared=$declared resolved=$resolved latest=$latest"
}

case "${1:-}" in
  --selftest) selftest ;;
  "") check_repo ;;
  *) fail "사용법: $0 [--selftest]" ;;
esac
