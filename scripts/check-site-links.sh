#!/usr/bin/env bash
# 공개 사이트·리포 URL의 대소문자 파리티 검사 — 커밋되는 모든 파일을 훑는다.
#
# 배경: GitHub Pages 프로젝트 사이트 경로는 **리포 이름 그대로 대소문자를 구분**한다. 리포가 `Mara`라
# `https://ai-scream.ai/Mara/`만 200이고 `/mara/`는 404다. 그런데 리포 안 URL이 전부 소문자였다:
# README의 Website 링크, 랜딩 페이지의 canonical·og:url·og:image·twitter:image·structured data가
# 모두 404를 가리켰다(og:image 404 = X·Slack·Discord 미리보기 이미지 깨짐). 대문자 참조는 0개였다.
#
# github.com 쪽(`github.com/ai-screams/mara`)은 GitHub이 302로 리다이렉트해 지금은 동작한다. 그래도
# 고정하는 이유: 그중 하나가 App/Info.plist의 **SUFeedURL**이라 출시된 앱 바이너리에 박히고, 자동
# 업데이트 채널이 GitHub의 대소문자 리다이렉트 동작에 의존하게 된다. 의존할 이유가 없는 의존이다.
#
# 이 검사는 sponsor 파리티 검사(check-sponsor-links.sh)와 같은 병을 막는다 — URL이 여러 표면에
# 흩어져 조용히 갈라지는 것. 다만 그쪽은 FUNDING.yml에서 canonical을 유도할 수 있는 반면 여기는
# 리포 밖 사실(org 커스텀 도메인 + 리포 이름)이 출처라, 아래 상수가 단일 출처다.
#
# 사용법:
#   scripts/check-site-links.sh              # 리포 루트에서 실행
#   scripts/check-site-links.sh --selftest   # 가드 자체를 fixture로 검증
set -euo pipefail

SITE_URL="https://ai-scream.ai/Mara/"          # org 커스텀 도메인 + 리포 이름(대소문자 구분)
REPO_URL="https://github.com/ai-screams/Mara"

# canonical을 담아야 하는 표면(누락 방지). 나머지 파일은 아래 금지 패턴으로만 검사한다.
REQUIRE_SITE=("README.md" "docs/index.html")

# 금지 패턴. `/mara`는 소문자만 매칭되므로 올바른 `/Mara`는 걸리지 않는다.
# http:// 도 금지한다 — 이 페이지가 DMG 다운로드 링크를 제공하므로 평문 HTTP로 참조할 이유가 없다.
FORBIDDEN_RE='ai-scream\.ai/mara|ai-screams/mara|http://ai-scream\.ai'

# 이 스크립트 자신은 금지 패턴을 '문자열로' 담고 있으므로 스캔에서 제외한다(자기 오탐 방지).
SELF="scripts/check-site-links.sh"

fail() { echo "❌ site-links: $1" >&2; exit 1; }

check_repo() {
  local files hits f
  # 대상은 `git ls-files`로 **자동 탐색** — 표면 목록을 하드코딩하면 새 파일이 조용히 빠진다.
  # 실제로 이번 감사는 README·docs만 봐서 App/Info.plist·RELEASING.md·배지 URL을 놓쳤다.
  files="$(git ls-files | grep -v "^${SELF}$" || true)"
  [ -n "$files" ] || fail "git ls-files가 비었다 — 리포 루트에서 실행했는지 확인(가드가 아무것도 검사 못 함)"

  # -I: 바이너리(png 등) 건너뜀. 히트가 있으면 파일:라인을 그대로 보여준다.
  hits="$(echo "$files" | xargs grep -InE "$FORBIDDEN_RE" || true)"
  if [ -n "$hits" ]; then
    echo "$hits" >&2
    fail "소문자 경로 또는 평문 HTTP URL 발견 — 위 위치를 ${SITE_URL} / ${REPO_URL} 형태로 고칠 것"
  fi

  for f in "${REQUIRE_SITE[@]}"; do
    [ -f "$f" ] || fail "표면 파일 없음: $f"
    grep -qF "$SITE_URL" "$f" || fail "$f 에 canonical 사이트 URL($SITE_URL) 없음"
  done

  echo "✅ site-links: 커밋 대상 전체에 소문자/평문 URL 없음, canonical 존재"
}

# --selftest: 임시 git 리포 fixture로 '가드가 실제로 잡는지' 검증한다.
# git ls-files로 탐색하므로 fixture도 git init + add가 필요하다.
selftest() {
  local failed=0
  run_case() { # name expect(pass|fail) readme_url [extra_file_content]
    local name="$1" expect="$2" url="$3" extra="${4:-}" tmp rc got
    tmp="$(mktemp -d)"
    mkdir -p "$tmp/docs"
    printf '<a href="%s">Website</a>\n' "$url" > "$tmp/README.md"
    printf '<link rel="canonical" href="%s" />\n' "$url" > "$tmp/docs/index.html"
    [ -z "$extra" ] || printf '%s\n' "$extra" > "$tmp/Info.plist"
    ( cd "$tmp" && git init -q . && git add -A ) >/dev/null 2>&1
    rc=0
    ( cd "$tmp" && "$SCRIPT_PATH" ) >/dev/null 2>&1 || rc=$?
    rm -rf "$tmp"
    if [ "$rc" -eq 0 ]; then got=pass; else got=fail; fi
    if [ "$got" = "$expect" ]; then
      printf '  ok   %-34s %s\n' "$name" "$got"
    else
      printf '  FAIL %-34s expected=%s got=%s\n' "$name" "$expect" "$got"
      failed=1
    fi
  }

  run_case "canonical"                  pass "https://ai-scream.ai/Mara/"
  run_case "소문자 사이트 경로"           fail "https://ai-scream.ai/mara/"
  run_case "평문 HTTP"                   fail "http://ai-scream.ai/Mara/"
  # 다른 파일(예: Info.plist)에 숨은 소문자 리포 URL도 잡아야 한다 — 이번에 실제로 놓쳤던 유형.
  run_case "다른 파일의 소문자 리포 URL"  fail "https://ai-scream.ai/Mara/" \
    "<string>https://github.com/ai-screams/mara/releases/latest/download/appcast.xml</string>"
  run_case "다른 파일이 올바르면 통과"     pass "https://ai-scream.ai/Mara/" \
    "<string>https://github.com/ai-screams/Mara/releases/latest/download/appcast.xml</string>"

  if [ "$failed" -ne 0 ]; then
    echo "❌ site-links: selftest 실패 (가드가 반례를 잡지 못함)" >&2
    exit 1
  fi
  echo "✅ site-links: selftest 통과 (소문자 경로·평문 HTTP·타 파일 은닉 URL 거부)"
}

SCRIPT_PATH="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"

if [ "${1:-}" = "--selftest" ]; then
  selftest
else
  check_repo
fi
