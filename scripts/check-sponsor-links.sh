#!/usr/bin/env bash
# 후원 링크 파리티 검사 — 앱·README·랜딩·FUNDING의 sponsor URL이 갈라지지 않게 CI에서 고정한다.
#
# 배경: 후원 URL이 리포 네 곳(App/SponsorLink.swift, README.md, docs/index.html, .github/FUNDING.yml)에
# 흩어져 있고 그동안 자동 검사가 없었다. 계정 핸들 하나만 바꾸고 일부 표면을 놓치면 README·랜딩 페이지
# 버튼이 조용히 404가 된다(돈 흐르는 링크인데 가드 0이던 문제). 이 스크립트가 그 드리프트를 CI에서 막는다.
#
# 계정 정체성 단일 출처 = .github/FUNDING.yml 핸들 → canonical URL 유도.
# 검사: (1) FUNDING 핸들에서 canonical URL 유도 → (2) 각 표면이 canonical URL을 담는지(링크 누락 방지)
#       → (3) 각 표면의 '모든' sponsor URL이 canonical과 일치하는지(오타·스테일 divergence 방지).
#
# 사용법:
#   scripts/check-sponsor-links.sh              # 리포 루트에서 실행
#   scripts/check-sponsor-links.sh --selftest   # 가드 자체를 fixture로 검증
set -euo pipefail

FUNDING=".github/FUNDING.yml"
APP="App/SponsorLink.swift"
# 앱 소스도 표면에 포함 — 4곳 전부 같은 URL을 쓰는지 한 번에 고정.
SURFACES=("$APP" "README.md" "docs/index.html")

# 파일 안의 sponsor URL만 추출하는 정규식(리포 링크 github.com/<org>/<repo>·website는 제외).
#
# 문자 클래스가 URL '경계'지 핸들 문자가 아니라는 점이 중요하다. 예전엔 핸들까지만
# (`[A-Za-z0-9_-]+`) 읽어서 `https://ko-fi.com/pignuante/typo` 같은 오타에서 `/typo`를 잘라내고
# canonical만 돌려줬다 → (2)는 substring이라 통과, (3)은 잘린 값이 canonical과 같아 통과. 즉 가드가
# "모든 URL이 canonical"이라고 주장하면서 손상된 꼬리를 못 봤다. 이제 공백·따옴표·꺾쇠·괄호를
# 경계로 URL 토큰 전체를 읽는다 — Swift 문자열 따옴표, Markdown 링크 괄호, HTML 속성 따옴표가
# 현재 세 표면의 실제 구분자다.
# 한계(의도된 트레이드오프): 경계 문자 집합에 없는 것은 전부 토큰에 붙는다 — 문장 끝 마침표·쉼표뿐
# 아니라 홑따옴표 HTML 속성(href='…'), Markdown 백틱(`…`)도 마찬가지다. 이건 **일부러 안 넓힌다**:
# `'`나 백틱을 경계에 추가하면 A-04가 방금 막은 `/typo`형 false negative가 다시 열린다(경계가 늘수록
# 잘려나가는 꼬리도 늘어난다). 방향이 fail-safe라 괜찮다 — 문제 토큰을 찍으며 CI가 시끄럽게 실패할
# 뿐 조용히 통과하지 않으므로, 그때 표면을 큰따옴표/링크 형식으로 맞추면 된다.
# 모든 임베딩을 처리한다고 주장하지 않는다.
SPONSOR_RE='https://(github\.com/sponsors|ko-fi\.com)/[^[:space:]"<>()]+'

fail() { echo "❌ sponsor-links: $1" >&2; exit 1; }

check_repo() {
  # 1) FUNDING.yml 핸들 → canonical URL. github는 리스트 형식(`[handle]`), ko_fi는 스칼라.
  local gh_handle kofi_handle gh_url kofi_url f urls u
  gh_handle="$(grep -E '^github:'  "$FUNDING" | sed -E 's/^github:[[:space:]]*//; s/^\[//; s/\].*//; s/[[:space:]]//g; s/,.*//')"
  kofi_handle="$(grep -E '^ko_fi:' "$FUNDING" | sed -E 's/^ko_fi:[[:space:]]*//; s/[[:space:]]//g')"
  [[ -n "$gh_handle"   ]] || fail "$FUNDING github 핸들 파싱 실패"
  [[ -n "$kofi_handle" ]] || fail "$FUNDING ko_fi 핸들 파싱 실패"

  gh_url="https://github.com/sponsors/${gh_handle}"
  kofi_url="https://ko-fi.com/${kofi_handle}"
  echo "canonical (from $FUNDING): $gh_url | $kofi_url"

  # 2)+3) 각 표면: canonical 존재(누락 방지) + divergent 부재(오타·스테일 방지).
  # 두 검사 모두 '추출된 URL 토큰 전체'를 대상으로 한다. 존재 검사를 파일 substring(grep -F)으로
  # 하면 canonical이 더 긴 오타 URL의 접두사일 때 통과해버린다 — 토큰 exact match(-Fxq)로 막는다.
  for f in "${SURFACES[@]}"; do
    [[ -f "$f" ]] || fail "표면 파일 없음: $f"
    urls="$(grep -oE "$SPONSOR_RE" "$f" || true)"
    grep -Fxq "$gh_url"   <<< "$urls" || fail "$f 에 GitHub Sponsors 링크($gh_url) 누락/불일치"
    grep -Fxq "$kofi_url" <<< "$urls" || fail "$f 에 Ko-fi 링크($kofi_url) 누락/불일치"
    while IFS= read -r u; do
      [[ -n "$u" ]] || continue
      case "$u" in
        "$gh_url"|"$kofi_url") : ;;
        *) fail "$f 에 canonical과 다른 sponsor URL 발견: $u (FUNDING.yml 핸들과 함께 갱신했는지 확인)" ;;
      esac
    done <<< "$urls"
  done

  echo "✅ sponsor-links: App·README·docs·FUNDING 4개 표면 URL 정합"
}

# --selftest: 임시 fixture로 '가드가 실제로 잡는지'를 검증한다. 이 검사는 도입 당시 조용한 false
# negative(`/typo` 접미사 통과)를 갖고 있었으므로, 반례가 확실히 실패하는지 고정해 둔다.
selftest() {
  local tmp rc failed=0
  # gh_line은 생략 가능(기본 canonical) — 두 표면을 각각 독립적으로 변조해 시험하기 위해서다.
  # 예전엔 kofi만 파라미터고 GitHub URL은 하드코딩이라 가드의 GitHub 분기에 반례가 0이었다.
  run_case() { # name expect(pass|fail) kofi_line [gh_line]
    local name="$1" expect="$2" kofi="$3" gh="${4:-https://github.com/sponsors/ai-screams}" tmp rc
    tmp="$(mktemp -d)"
    mkdir -p "$tmp/.github" "$tmp/App" "$tmp/docs"
    printf 'github: [ai-screams]\nko_fi: pignuante\n' > "$tmp/.github/FUNDING.yml"
    printf 'let gh = "%s"\nlet kofi = "%s"\n' "$gh" "$kofi" > "$tmp/App/SponsorLink.swift"
    printf '[Sponsor](%s) [Ko-fi](%s)\n' "$gh" "$kofi" > "$tmp/README.md"
    printf '<a href="%s">s</a><a href="%s">k</a>\n' "$gh" "$kofi" > "$tmp/docs/index.html"
    rc=0
    ( cd "$tmp" && "$SCRIPT_PATH" ) >/dev/null 2>&1 || rc=$?
    rm -rf "$tmp"
    local got; if [ "$rc" -eq 0 ]; then got=pass; else got=fail; fi
    if [ "$got" = "$expect" ]; then
      printf '  ok   %-28s %s\n' "$name" "$got"
    else
      printf '  FAIL %-28s expected=%s got=%s\n' "$name" "$expect" "$got"
      failed=1
    fi
  }

  run_case "canonical"              pass "https://ko-fi.com/pignuante"
  run_case "handle 오타"             fail "https://ko-fi.com/pignuant"
  run_case "path suffix (/typo)"    fail "https://ko-fi.com/pignuante/typo"
  run_case "query suffix (?ref=)"   fail "https://ko-fi.com/pignuante?ref=typo"
  run_case "canonical 누락"          fail "https://example.com/nope"
  # GitHub Sponsors 분기도 같은 반례로 시험한다 — 두 URL이 대칭적으로 보호되는지 확인.
  run_case "gh path suffix"         fail "https://ko-fi.com/pignuante" "https://github.com/sponsors/ai-screams/typo"
  run_case "gh handle 오타"          fail "https://ko-fi.com/pignuante" "https://github.com/sponsors/ai-scream"

  # 동일 canonical이 한 파일에 여러 번 나와도 통과해야 한다(버튼+푸터 등 실제 배치).
  tmp="$(mktemp -d)"
  mkdir -p "$tmp/.github" "$tmp/App" "$tmp/docs"
  printf 'github: [ai-screams]\nko_fi: pignuante\n' > "$tmp/.github/FUNDING.yml"
  for f in App/SponsorLink.swift README.md docs/index.html; do
    printf '"https://github.com/sponsors/ai-screams" "https://ko-fi.com/pignuante"\n"https://github.com/sponsors/ai-screams" "https://ko-fi.com/pignuante"\n' > "$tmp/$f"
  done
  rc=0; ( cd "$tmp" && "$SCRIPT_PATH" ) >/dev/null 2>&1 || rc=$?
  rm -rf "$tmp"
  if [ "$rc" -eq 0 ]; then printf '  ok   %-28s pass\n' "canonical 반복"
  else printf '  FAIL %-28s expected=pass got=fail\n' "canonical 반복"; failed=1; fi

  if [ "$failed" -ne 0 ]; then
    echo "❌ sponsor-links: selftest 실패 (가드가 반례를 잡지 못함)" >&2
    exit 1
  fi
  echo "✅ sponsor-links: selftest 통과 (오타·접미사·누락 반례를 모두 거부)"
}

SCRIPT_PATH="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"

if [ "${1:-}" = "--selftest" ]; then
  selftest
else
  check_repo
fi
