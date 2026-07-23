#!/usr/bin/env bash
# 릴리스 버전/태그 문법 검증 — release.sh(빌드 경로)와 release.yml appcast 스텝(피드 경로)의 단일 출처.
#
# 배경: 예전엔 두 곳이 각자 검사를 갖고 있었고 둘 다 느슨했다. release.sh 정규식은 접미사 첫 문자로
# '-' 말고 '.'도 허용해 `1.2.3.foo`·`1.2.3..`을 통과시켰고, appcast 스텝은 정규식이 아니라 셸 glob
# (`v[0-9]*.[0-9]*.[0-9]*`)이라 `v1foo.2bar.3baz`까지 통과시켰다. `*`가 점을 포함해 무엇이든 먹기 때문이다.
# 특히 `v1.2.3.foo`는 두 가드를 모두 통과하면서 하이픈이 없어 GitHub Release가 stable로 분류한다
# (release.yml의 `prerelease: contains(ref_name, '-')`) → 잘못된 태그가 DMG 이름·MARKETING_VERSION·
# appcast에 그대로 들어간다. 두 곳에 정규식을 복제하면 같은 드리프트가 재발하므로 여기로 합친다.
#
# 문법은 완전한 SemVer가 아니라 **Mara 릴리스 버전 문법**이다(정직한 이름). 이 프로젝트가 쓰는 태그는
# `v0.11.1`, `v1.2.0-rc1`, `v1.2.0-rc.1` 뿐이라 build metadata(`+meta`)나 prerelease의 선행 0 규칙까지
# 구현하지 않는다 — 필요해지면 그때 넓힌다(YAGNI).
#
# 사용법:
#   scripts/check-release-version.sh v1.2.3   # 또는 1.2.3 (앞의 v는 선택)
#   scripts/check-release-version.sh --selftest
set -euo pipefail

# 앞의 'v'를 뗀 본체 문법. ERE만 사용한다 — 공식 SemVer 정규식은 비캡처 그룹 `(?:…)`(PCRE)을 쓰는데
# grep -E/bash/zsh의 기본 ERE에는 없다.
VERSION_RE='^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z]+([.-][0-9A-Za-z]+)*)?$'

# 매칭은 셸 내장 `=~` 대신 `grep -qE`로 한다. `[[ $x =~ $re ]]`의 우변 인용 의미가 셸마다 반대이기
# 때문이다: zsh는 인용해도 정규식으로 보지만 bash는 인용하면 **리터럴 문자열 비교**가 돼 가드가
# 조용히 무력화된다. release.sh는 zsh, 워크플로 스텝은 bash라 이 스크립트는 양쪽에서 호출된다.
version_ok() {
    local v="${1#v}"   # 'v' 접두는 선택 — release.sh는 v를 뗀 VERSION을, appcast 스텝은 태그명을 넘긴다.
    # 허용 문자 집합 밖(공백·개행·셸/경로 메타문자)은 정규식 이전에 잘라낸다. grep은 줄 단위라
    # 개행이 든 값은 첫 줄만 맞아도 통과하는데, 그 경로를 애초에 막는다.
    case "$v" in
        ''|*[!0-9A-Za-z.-]*) return 1 ;;
    esac
    printf '%s' "$v" | grep -qE "$VERSION_RE"
}

selftest() {
    local failed=0 input expect
    # 개행이 든 값은 아래 heredoc `read` 루프로 표현할 수 없어(한 줄에 개행을 담을 수 없다) 여기서
    # 따로 고정한다. 이걸 거부하는 건 version_ok의 `case` 가드뿐이다 — grep은 줄 단위라 앵커된
    # 정규식만으론 첫 줄만 보고 통과시킨다. 이 케이스가 없으면 `case` 가드는 앵커 정규식 옆에서
    # 중복처럼 보여 정리 대상이 되는데, 지워도 selftest가 초록이라 회귀가 안 보인다(실측 확인).
    if version_ok "$(printf '1.2.3\nevil')"; then
        printf '  FAIL %-18s expected=reject got=accept\n' '1.2.3\nevil'
        failed=1
    else
        printf '  ok   %-18s reject\n' '1.2.3\nevil'
    fi
    # 반례는 실제로 두 가드를 통과했던 것들 + 경로/셸 오염 방어용.
    while read -r input expect; do
        [ -n "$input" ] || continue
        if version_ok "$input"; then local got=accept; else local got=reject; fi
        if [ "$got" = "$expect" ]; then
            printf '  ok   %-18s %s\n' "$input" "$got"
        else
            printf '  FAIL %-18s expected=%s got=%s\n' "$input" "$expect" "$got"
            failed=1
        fi
    done <<'CASES'
v1.2.3            accept
1.2.3             accept
v0.11.1           accept
v1.2.3-rc1        accept
v1.2.3-rc.1       accept
v1.2.3-beta.2     accept
v1.2.3.foo        reject
v1.2.3..          reject
v1foo.2bar.3baz   reject
v1.2              reject
v1.2.3-           reject
v1.2.3.           reject
v1.2.3+build.1    reject
v1.2.3/../evil    reject
CASES
    if [ "$failed" -ne 0 ]; then
        echo "❌ check-release-version: selftest 실패" >&2
        exit 1
    fi
    echo "✅ check-release-version: selftest 통과 (Mara 릴리스 버전 문법)"
}

if [ "${1:-}" = "--selftest" ]; then
    selftest
    exit 0
fi

[ $# -eq 1 ] || { echo "usage: $0 <version|tag> | --selftest" >&2; exit 2; }

version_ok "$1" || {
    echo "❌ check-release-version: 거부된 릴리스 버전 '$1' — Mara 문법은 X.Y.Z 또는 X.Y.Z-prerelease (앞의 v 선택)" >&2
    exit 1
}
