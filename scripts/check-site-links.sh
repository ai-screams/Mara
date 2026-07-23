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

# 후보 패턴은 대소문자 무시로 찾고, 아래에서 canonical 철자만 제거한 뒤 남은 변형을 거부한다.
# 단순히 소문자 `/mara`만 금지하면 `/MARA`, `/MaRa` 같은 또 다른 404가 통과한다.
# http:// 도 금지한다 — 이 페이지가 DMG 다운로드 링크를 제공하므로 평문 HTTP로 참조할 이유가 없다.
CANDIDATE_RE='ai-scream\.ai/mara|ai-screams/mara|http://ai-scream\.ai'

# 이 스크립트 자신은 금지 패턴을 '문자열로' 담고 있으므로 스캔에서 제외한다(자기 오탐 방지).
SELF="scripts/check-site-links.sh"

fail() { echo "❌ site-links: $1" >&2; exit 1; }

check_repo() {
  local record sanitized bad=0 f
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 \
    || fail "git 리포 안에서 실행해야 함(가드가 아무것도 검사 못 함)"

  # `git grep`가 tracked file을 직접 순회하므로 `git ls-files | xargs grep`의 공백 파일명 분해가 없다.
  # 후보를 -i로 넓게 찾은 뒤 정확한 canonical 두 문자열만 제거한다. 한 줄에 정상·오류 URL이 함께
  # 있어도 오류 변형이 남으므로 fail한다. -I는 png 같은 바이너리를 건너뛴다.
  while IFS= read -r record; do
    if printf '%s\n' "$record" | grep -qE 'http://ai-scream\.ai'; then
      echo "$record" >&2
      bad=1
      continue
    fi
    sanitized="${record//ai-scream.ai\/Mara/}"
    sanitized="${sanitized//ai-screams\/Mara/}"
    if printf '%s\n' "$sanitized" | grep -qiE 'ai-scream\.ai/mara|ai-screams/mara'; then
      echo "$record" >&2
      bad=1
    fi
  done < <(git grep -InEi "$CANDIDATE_RE" -- . ":(exclude)$SELF" || true)

  [ "$bad" -eq 0 ] \
    || fail "잘못된 대소문자 또는 평문 HTTP URL 발견 — 위 위치를 ${SITE_URL} / ${REPO_URL} 형태로 고칠 것"

  for f in "${REQUIRE_SITE[@]}"; do
    [ -f "$f" ] || fail "표면 파일 없음: $f"
    grep -qF "$SITE_URL" "$f" || fail "$f 에 canonical 사이트 URL($SITE_URL) 없음"
  done

  echo "✅ site-links: 커밋 대상 전체에 소문자/평문 URL 없음, canonical 존재"
}

# --selftest: 임시 git 리포 fixture로 '가드가 실제로 잡는지' 검증한다.
# git grep로 tracked file을 탐색하므로 fixture도 git init + add가 필요하다.
selftest() {
  local failed=0
  run_case() { # name expect(pass|fail) readme_url [extra_file_content] [extra_file_name]
    local name="$1" expect="$2" url="$3" extra="${4:-}" extra_name="${5:-Info.plist}" tmp rc got
    tmp="$(mktemp -d)"
    mkdir -p "$tmp/docs"
    printf '<a href="%s">Website</a>\n' "$url" > "$tmp/README.md"
    printf '<link rel="canonical" href="%s" />\n' "$url" > "$tmp/docs/index.html"
    [ -z "$extra" ] || printf '%s\n' "$extra" > "$tmp/$extra_name"
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
  run_case "대문자 변형 사이트 경로"       fail "https://ai-scream.ai/MARA/"
  run_case "혼합 대소문자(다른 파일)"       fail "https://ai-scream.ai/Mara/" \
    "https://ai-scream.ai/MaRa/"
  run_case "평문 HTTP"                   fail "http://ai-scream.ai/Mara/"
  # 다른 파일(예: Info.plist)에 숨은 소문자 리포 URL도 잡아야 한다 — 이번에 실제로 놓쳤던 유형.
  run_case "다른 파일의 소문자 리포 URL"  fail "https://ai-scream.ai/Mara/" \
    "<string>https://github.com/ai-screams/mara/releases/latest/download/appcast.xml</string>"
  run_case "다른 파일이 올바르면 통과"     pass "https://ai-scream.ai/Mara/" \
    "<string>https://github.com/ai-screams/Mara/releases/latest/download/appcast.xml</string>"
  run_case "공백 파일명의 오류 URL"         fail "https://ai-scream.ai/Mara/" \
    "https://ai-scream.ai/mara/" "bad file.txt"

  if [ "$failed" -ne 0 ]; then
    echo "❌ site-links: selftest 실패 (가드가 반례를 잡지 못함)" >&2
    exit 1
  fi
  echo "✅ site-links: selftest 통과 (모든 대소문자 변형·평문 HTTP·공백 파일명 거부)"
}

SCRIPT_PATH="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"

if [ "${1:-}" = "--selftest" ]; then
  selftest
else
  check_repo
fi
