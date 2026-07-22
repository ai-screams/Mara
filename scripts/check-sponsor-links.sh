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
set -euo pipefail

FUNDING=".github/FUNDING.yml"
APP="App/SponsorLink.swift"
# 앱 소스도 표면에 포함 — 4곳 전부 같은 URL을 쓰는지 한 번에 고정.
SURFACES=("$APP" "README.md" "docs/index.html")

# 파일 안의 sponsor URL만 추출하는 정규식(리포 링크 github.com/<org>/<repo>·website는 제외).
SPONSOR_RE='https://github\.com/sponsors/[A-Za-z0-9_-]+|https://ko-fi\.com/[A-Za-z0-9_-]+'

fail() { echo "❌ sponsor-links: $1" >&2; exit 1; }

# 1) FUNDING.yml 핸들 → canonical URL. github는 리스트 형식(`[handle]`), ko_fi는 스칼라.
gh_handle="$(grep -E '^github:'  "$FUNDING" | sed -E 's/^github:[[:space:]]*//; s/^\[//; s/\].*//; s/[[:space:]]//g; s/,.*//')"
kofi_handle="$(grep -E '^ko_fi:' "$FUNDING" | sed -E 's/^ko_fi:[[:space:]]*//; s/[[:space:]]//g')"
[[ -n "$gh_handle"   ]] || fail "$FUNDING github 핸들 파싱 실패"
[[ -n "$kofi_handle" ]] || fail "$FUNDING ko_fi 핸들 파싱 실패"

gh_url="https://github.com/sponsors/${gh_handle}"
kofi_url="https://ko-fi.com/${kofi_handle}"
echo "canonical (from $FUNDING): $gh_url | $kofi_url"

# 2)+3) 각 표면: canonical 존재(누락 방지) + divergent 부재(오타·스테일 방지).
for f in "${SURFACES[@]}"; do
  [[ -f "$f" ]] || fail "표면 파일 없음: $f"
  grep -qF "$gh_url"   "$f" || fail "$f 에 GitHub Sponsors 링크($gh_url) 누락/불일치"
  grep -qF "$kofi_url" "$f" || fail "$f 에 Ko-fi 링크($kofi_url) 누락/불일치"
  while IFS= read -r u; do
    case "$u" in
      "$gh_url"|"$kofi_url") : ;;
      *) fail "$f 에 canonical과 다른 sponsor URL 발견: $u (FUNDING.yml 핸들과 함께 갱신했는지 확인)" ;;
    esac
  done < <(grep -oE "$SPONSOR_RE" "$f" || true)
done

echo "✅ sponsor-links: App·README·docs·FUNDING 4개 표면 URL 정합"
