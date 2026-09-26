#!/usr/bin/env bash
# 레거시 릴리스 태그 문법의 단일 출처.
#
#   legacy-release-tag.sh <tag>        → KEY=VALUE 줄을 출력(eval이 아니라 grep/cut으로 읽는다)
#   legacy-release-tag.sh --selftest
#
# 허용: legacy-v<X.Y.Z>-<N>(공개 릴리스), legacy-rc-v<X.Y.Z>-<N>(RC — 빌드만, 게시 없음). N은 1–99.
# 빌드 번호 CFBundleVersion = 114.N: 본판 v0.11.2의 빌드 번호(커밋 수 115)보다 항상 작아 Sparkle이
# 레거시를 본판보다 오래된 것으로 판정한다 → OS를 올린 레거시 사용자가 본판으로 이주한다.
# Apple 형식상 두 번째 정수는 두 자리까지라 N ≥ 100은 거부한다(도달하면 레거시 종료·재설계).
set -euo pipefail

LEGACY_BUILD_MAJOR=114
TAG_RE='^legacy-(rc-)?v([0-9]+\.[0-9]+\.[0-9]+)-([1-9][0-9]?)$'

parse() {
    local tag="$1"
    case "$tag" in
        ''|*[!0-9A-Za-z.-]*) return 1 ;;   # 개행·셸/경로 메타문자는 정규식 전에 거른다(grep은 줄 단위)
    esac
    [[ "$tag" =~ $TAG_RE ]] || return 1
    local rc="${BASH_REMATCH[1]}" version="${BASH_REMATCH[2]}" n="${BASH_REMATCH[3]}"
    echo "KIND=$([ -n "$rc" ] && echo rc || echo release)"
    echo "VERSION=$version"
    echo "N=$n"
    echo "BUILD=$LEGACY_BUILD_MAJOR.$n"
    echo "RELEASE_TAG=legacy-v$version-$n"
    echo "RC_TAG=legacy-rc-v$version-$n"
}

selftest() {
    local failed=0 input expect got
    while read -r input expect; do
        [ -n "$input" ] || continue
        if out="$(parse "$input")"; then got="$(echo "$out" | grep '^BUILD=' | cut -d= -f2)"; else got=reject; fi
        if [ "$got" = "$expect" ]; then printf '  ok   %-28s %s\n' "$input" "$got"
        else printf '  FAIL %-28s expected=%s got=%s\n' "$input" "$expect" "$got"; failed=1; fi
    done <<'CASES'
legacy-v0.11.2-1              114.1
legacy-v0.11.2-99             114.99
legacy-rc-v0.11.2-3           114.3
legacy-v0.11.2-0              reject
legacy-v0.11.2-100            reject
legacy-v0.11.2-01             reject
legacy-v0.11.2                reject
v0.11.2                       reject
legacy-v0.11-1                reject
legacy-v0.11.2-1-rc           reject
legacy-rc-0.11.2-1            reject
legacy-v0.11.2-1;rm           reject
CASES
    if parse "$(printf 'legacy-v0.11.2-1\nevil')" >/dev/null; then echo "  FAIL multi-line accepted"; failed=1; else echo "  ok   multi-line rejected"; fi
    [ "$(parse legacy-rc-v0.11.2-3 | grep '^RELEASE_TAG=')" = "RELEASE_TAG=legacy-v0.11.2-3" ] \
        || { echo "  FAIL RC → RELEASE_TAG mapping"; failed=1; }
    if [ $failed -ne 0 ]; then echo "❌ legacy-release-tag: selftest failed"; exit 1; fi
    echo "✅ legacy-release-tag: selftest passed"
}

case "${1:-}" in
    --selftest) selftest ;;
    '') echo "usage: $0 <tag> | --selftest" >&2; exit 2 ;;
    *) parse "$1" || { echo "❌ not a legacy release tag: $1" >&2; exit 1; } ;;
esac
